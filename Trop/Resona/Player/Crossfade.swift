//
//  Crossfade.swift
//  Resona
//
//  Crossfade between songs with a lightweight second mpv instance ("tail")
//  for the END of the outgoing song, so the main player keeps its normal
//  role (queue, lyrics clock, lock screen, history all follow the next song
//  as usual):
//
//  1. ~1.2 s before the handover the tail opens the SAME source as the main
//     player (mpv `path`: the resolved stream URL or the local file, plus
//     the same `af` chain = normalization/EQ) a little ahead, silent.
//  2. While still silent its position is matched to the main player via
//     time-pos (exact relative seeks; streamed WEBM/Opus seeks can be off by
//     hundreds of ms, so this is measured, not assumed).
//  3. Handover: a 150 ms equal-power micro crossfade main → tail (both play
//     the old song) masks any remaining offset.
//  4. The main player starts the next song at gain 0; once its audio runs,
//     the long equal-power crossfade (tail cos, main sin) over the chosen
//     length. Then the tail stops.
//
//  Skipped for manual skips, repeat-one, sleep timer "end of song", video
//  mode, the end of the queue, and with gapless on when the next song is
//  from the same album. Any skip/pause/song change aborts it cleanly.
//

import Foundation
import Libmpv
import QuartzCore

@MainActor
final class CrossfadeEngine {
    static let shared = CrossfadeEngine()

    private var monitor: Task<Void, Never>?
    private var run: Task<Void, Never>?
    private var runningFor: String?
    private let tail = CrossfadeTail()

    private init() {}

    /// Starts the 4 Hz watcher (idempotent).
    func start() {
        guard monitor == nil else { return }
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                self?.tick()
            }
        }
    }

    private var fadeSeconds: Double { SettingsStore.shared.crossfadeSeconds }

    private func tick() {
        let np = NowPlaying.shared
        guard run == nil else { return }
        let length = fadeSeconds
        guard length >= 1, let videoId = np.videoId, eligible(np, length: length) else { return }
        let handover = np.duration - length - 1.0
        let position = PlayerController.shared.currentTime
        guard position >= handover - 2.5, position < handover - 1.4 else { return }
        runningFor = videoId
        run = Task { [weak self] in
            await self?.perform(videoId: videoId, length: length, handover: handover)
            self?.run = nil
            self?.runningFor = nil
        }
    }

    private func eligible(_ np: NowPlaying, length: Double) -> Bool {
        guard np.isPlaying, np.duration > 2 * length + 20, np.hasNext,
              !np.isRepeatOn, !np.isVideoMode, !SleepTimer.shared.stopAtSongEnd else { return false }
        if SettingsStore.shared.gaplessPlayback,
           np.queueSongs.indices.contains(np.queueIndex + 1),
           let current = np.queueSongs[safe: np.queueIndex]?.albumId,
           current == np.queueSongs[np.queueIndex + 1].albumId {
            return false   // gapless album transition has priority
        }
        return true
    }

    // MARK: Sequence

    private func perform(videoId: String, length: Double, handover: TimeInterval) async {
        let player = PlayerController.shared
        let np = NowPlaying.shared
        let skipMark = np.lastManualSkipTime
        func stillValid() -> Bool {
            np.videoId == videoId && np.isPlaying && np.lastManualSkipTime == skipMark
        }

        guard let source = player.currentSource else { return }
        let base = SettingsStore.shared.playerVolume * 100
        let tailStart = handover - 1.2

        // 1) Same source, a bit ahead, silent and paused.
        await tail.prepare(source: source.path, audioFilter: source.audioFilter, start: tailStart)

        // 2) Start silently when the main player gets there, then align.
        guard await waitUntil({ player.currentTime >= tailStart - 0.03 }, while: stillValid, timeout: 5) else { return abort() }
        tail.setVolume(0)
        tail.resume()
        for _ in 0..<5 {
            try? await Task.sleep(for: .milliseconds(180))
            guard stillValid() else { return abort() }
            guard let tailPos = tail.position else { continue }
            let drift = player.currentTime - tailPos
            if abs(drift) <= 0.02 { break }
            tail.seek(by: drift)
        }

        // 3) Micro crossfade main → tail at the handover point.
        guard await waitUntil({ player.currentTime >= handover }, while: stillValid, timeout: 4) else { return abort() }
        await ramp(duration: 0.15, while: stillValid) { t in
            player.crossfadeGain = cos(t * .pi / 2)
            self.tail.setVolume(base * sin(t * .pi / 2))
        }
        guard stillValid() else { return abort() }
        player.crossfadeGain = 0
        player.applyPlayerVolume()

        // 4) Next song on the main player (silent until its audio runs).
        np.playNext(automatic: true)
        let nextId = np.videoId
        _ = await waitUntil({ np.videoId != videoId && player.currentTime > 0.05 }, while: {
            np.videoId == nextId && np.lastManualSkipTime == skipMark
        }, timeout: 6)
        guard np.videoId == nextId, np.lastManualSkipTime == skipMark else { return abort() }

        let remaining = max(0.3, (tail.duration ?? 0) - (tail.position ?? 0) - 0.05)
        let fade = min(length, remaining)
        await ramp(duration: fade, while: { np.videoId == nextId && np.isPlaying && np.lastManualSkipTime == skipMark }) { t in
            player.crossfadeGain = sin(t * .pi / 2)
            self.tail.setVolume(base * cos(t * .pi / 2))
        }
        finish()
    }

    /// Equal-power ramps at ~60 Hz; `body` gets 0…1. Stops early (and the
    /// caller then finishes) as soon as `valid` fails (skip, pause, …).
    private func ramp(duration: Double, while valid: () -> Bool, _ body: @escaping (Double) -> Void) async {
        let start = CACurrentMediaTime()
        while true {
            guard valid() else { return }
            let t = min(1, (CACurrentMediaTime() - start) / max(0.01, duration))
            body(t)
            PlayerController.shared.applyPlayerVolume()
            if t >= 1 { break }
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    private func waitUntil(_ condition: () -> Bool, while valid: () -> Bool, timeout: Double) async -> Bool {
        let deadline = CACurrentMediaTime() + timeout
        while CACurrentMediaTime() < deadline {
            if condition() { return true }
            guard valid() else { return false }
            try? await Task.sleep(for: .milliseconds(15))
        }
        return condition()
    }

    private func finish() {
        tail.stop()
        PlayerController.shared.crossfadeGain = 1
        PlayerController.shared.applyPlayerVolume()
    }

    private func abort() {
        finish()
    }

    /// Manual skip / pause from the UI while a crossfade runs.
    func cancel() {
        run?.cancel()
        run = nil
        runningFor = nil
        finish()
    }
}

// MARK: - Tail player

/// Minimal second mpv instance: audio only, no observers, no event loop
/// (events are drained on every call).
final class CrossfadeTail: @unchecked Sendable {
    private var mpv: OpaquePointer?
    private let queue = DispatchQueue(label: "dev.resona.crossfade.tail")

    private func handle() -> OpaquePointer? {
        if let mpv { return mpv }
        guard let created = mpv_create() else { return nil }
        mpv_set_option_string(created, "vo", "null")
        mpv_set_option_string(created, "vid", "no")
        mpv_set_option_string(created, "audio-display", "no")
        mpv_set_option_string(created, "msg-level", "all=error")
        mpv_set_option_string(created, "cache", "yes")
        mpv_set_option_string(created, "hr-seek", "yes")
        mpv_set_option_string(created, "keep-open", "yes")
        #if targetEnvironment(simulator)
        mpv_set_option_string(created, "audio-exclusive", "no")
        #else
        mpv_set_option_string(created, "audio-exclusive", "yes")
        #endif
        guard mpv_initialize(created) >= 0 else {
            mpv_destroy(created)
            return nil
        }
        if let caPath = Bundle.main.path(forResource: "cacert", ofType: "pem") {
            mpv_set_property_string(created, "tls-ca-file", caPath)
        }
        mpv_set_property_string(created, "user-agent", "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15" +
            " (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1")
        mpv = created
        return created
    }

    private func drain(_ mpv: OpaquePointer) {
        while let event = mpv_wait_event(mpv, 0), event.pointee.event_id != MPV_EVENT_NONE {}
    }

    func prepare(source path: String, audioFilter: String, start: TimeInterval) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                guard let mpv = handle() else { return done.resume() }
                drain(mpv)
                var zero = Double(0)
                mpv_set_property(mpv, "volume", MPV_FORMAT_DOUBLE, &zero)
                mpv_set_property_string(mpv, "pause", "yes")
                mpv_set_property_string(mpv, "af", audioFilter)
                let args = ["loadfile", path, "replace", "-1", "start=\(String(format: "%.3f", start))"]
                _ = args.withUnsafeCArg { mpv_command(mpv, $0) }
                done.resume()
            }
        }
    }

    func resume() { set("pause", "no") }

    func stop() {
        queue.async { [self] in
            guard let mpv else { return }
            _ = ["stop"].withUnsafeCArg { mpv_command(mpv, $0) }
            drain(mpv)
        }
    }

    func setVolume(_ value: Double) {
        queue.async { [self] in
            guard let mpv else { return }
            var v = max(0, value)
            mpv_set_property(mpv, "volume", MPV_FORMAT_DOUBLE, &v)
        }
    }

    func seek(by seconds: Double) {
        queue.async { [self] in
            guard let mpv else { return }
            _ = ["seek", String(format: "%.3f", seconds), "relative+exact"].withUnsafeCArg { mpv_command(mpv, $0) }
            drain(mpv)
        }
    }

    var position: TimeInterval? { double("time-pos") }
    var duration: TimeInterval? { double("duration") }

    private func double(_ name: String) -> Double? {
        queue.sync {
            guard let mpv else { return nil }
            var value = Double(0)
            return mpv_get_property(mpv, name, MPV_FORMAT_DOUBLE, &value) >= 0 ? value : nil
        }
    }

    private func set(_ name: String, _ value: String) {
        queue.async { [self] in
            guard let mpv else { return }
            mpv_set_property_string(mpv, name, value)
        }
    }
}
