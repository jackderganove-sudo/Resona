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
    private let log = Log.player

    private func fmt(_ value: Double, _ digits: Int) -> String {
        String(format: "%.\(digits)f", value)
    }

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

        guard let source = player.currentSource else {
            log.info("CROSSFADE skip: no current source")
            return
        }
        let base = SettingsStore.shared.playerVolume * 100
        let tailStart = handover - 1.2
        let isLocal = source.path.hasPrefix("/") || source.path.hasPrefix("file:")
        log.info("CROSSFADE prepare id=\(videoId) length=\(length)s handover=\(fmt(handover, 2)) local=\(isLocal) af='\(source.audioFilter)'")

        // 1) Same source + options as the main player, a bit ahead, silent.
        await tail.prepare(source: source.path, audioFilter: source.audioFilter, start: tailStart)

        // 2) Start silently when the main player gets there …
        guard await waitUntil({ player.currentTime >= tailStart - 0.03 }, while: stillValid, timeout: 5) else {
            log.info("CROSSFADE abort before start (skip/pause/timeout)")
            return abort()
        }
        tail.setVolume(0)
        tail.resume()

        // … and VERIFY it really plays: file loaded, no error, audio output
        // active, not idle, time-pos moving. Otherwise no handover at all —
        // the song simply plays to its end on the main player.
        let verifyStart = tail.status()
        var verified = false
        for attempt in 0..<10 {
            try? await Task.sleep(for: .milliseconds(150))
            guard stillValid() else { return abort() }
            let st = tail.status()
            let moved = (st.timePos ?? 0) - (verifyStart.timePos ?? tailStart)
            log.info("CROSSFADE verify#\(attempt) loaded=\(st.loaded) failed=\(st.failed) idle=\(st.idleActive) coreIdle=\(st.coreIdle) ao='\(st.audioOutput)' pos=\(fmt(st.timePos ?? -1, 3)) moved=\(fmt(moved, 3))")
            if st.failed { break }
            if st.loaded, !st.idleActive, !st.coreIdle, !st.audioOutput.isEmpty, moved > 0.2 {
                verified = true
                break
            }
        }
        guard verified else {
            log.error("CROSSFADE tail not playing → no handover, normal song change")
            return abort()
        }

        // Align positions while the tail is still muted.
        for round in 0..<5 {
            try? await Task.sleep(for: .milliseconds(160))
            guard stillValid() else { return abort() }
            guard let tailPos = tail.status().timePos else { continue }
            let drift = player.currentTime - tailPos
            log.info("CROSSFADE align#\(round) main=\(fmt(player.currentTime, 3)) tail=\(fmt(tailPos, 3)) drift=\(fmt(drift, 3))")
            if abs(drift) <= 0.02 { break }
            tail.seek(by: drift)
        }

        // 3) Micro crossfade main → tail at the handover (both: old song).
        guard await waitUntil({ player.currentTime >= handover }, while: stillValid, timeout: 4) else { return abort() }
        guard tail.status().isPlaying else {
            log.error("CROSSFADE tail stopped before handover → normal song change")
            return abort()
        }
        await ramp(duration: 0.15, while: stillValid) { t in
            player.crossfadeGain = cos(t * .pi / 2)
            self.tail.setVolume(base * sin(t * .pi / 2))
        }
        guard stillValid() else { return abort() }
        player.crossfadeGain = 0
        player.applyPlayerVolume()
        log.info("CROSSFADE handover done → next song on main (gain 0)")

        // 4) Next song on the main player (silent until its audio runs).
        np.playNext(automatic: true)
        let nextId = np.videoId
        let started = await waitUntil({ np.videoId != videoId && player.currentTime > 0.05 }, while: {
            np.videoId == nextId && np.lastManualSkipTime == skipMark
        }, timeout: 6)
        guard np.videoId == nextId, np.lastManualSkipTime == skipMark else { return abort() }
        log.info("CROSSFADE next song audio=\(started) after handover; tail pos=\(fmt(self.tail.status().timePos ?? -1, 2))")

        let status = tail.status()
        let remaining = max(0.3, (status.duration ?? 0) - (status.timePos ?? 0) - 0.05)
        let fade = min(length, remaining)
        var lastLog = CACurrentMediaTime()
        await ramp(duration: fade, while: { np.videoId == nextId && np.isPlaying && np.lastManualSkipTime == skipMark }) { t in
            let mainGain = sin(t * .pi / 2)
            let tailVolume = base * cos(t * .pi / 2)
            player.crossfadeGain = mainGain
            self.tail.setVolume(tailVolume)
            if CACurrentMediaTime() - lastLog > 0.5 {
                lastLog = CACurrentMediaTime()
                let st = self.tail.status()
                self.log.info("CROSSFADE ramp t=\(fmt(t, 2)) main=\(fmt(base * mainGain, 1)) tail=\(fmt(tailVolume, 1)) tailPlaying=\(st.isPlaying) tailPos=\(fmt(st.timePos ?? -1, 2))")
            }
        }
        log.info("CROSSFADE finished")
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

/// Second mpv instance created with EXACTLY the main player's options
/// (same functions: user agent, TLS, cache, demuxer, audio-exclusive — the
/// latter only decides whether the app-wide audio session mixes with other
/// apps, so both instances must match or lock-screen controls break).
/// Its events are processed and logged, not thrown away.
final class CrossfadeTail: @unchecked Sendable {
    struct Status {
        var loaded = false
        var failed = false
        var idleActive = true
        var coreIdle = true
        var audioOutput = ""
        var timePos: Double?
        var duration: Double?
        var isPlaying: Bool { loaded && !failed && !idleActive && !coreIdle }
    }

    private var mpv: OpaquePointer?
    private let queue = DispatchQueue(label: "dev.resona.crossfade.tail")
    private var loaded = false
    private var failed = false

    private func handle() -> OpaquePointer? {
        if let mpv { return mpv }
        guard let created = mpv_create() else {
            Log.player.error("CROSSFADE tail mpv_create failed")
            return nil
        }
        mpv_request_log_messages(created, "warn")
        PlayerController.applyMpvStartupOptions(created)
        mpv_set_option_string(created, "keep-open", "yes")
        mpv_set_option_string(created, "hr-seek", "yes")
        guard mpv_initialize(created) >= 0 else {
            Log.player.error("CROSSFADE tail mpv_initialize failed")
            mpv_destroy(created)
            return nil
        }
        PlayerController.applyPostInitProperties(created)
        mpv = created
        return created
    }

    /// Processes pending events: tracks load/end-file errors, logs warnings.
    private func pump(_ mpv: OpaquePointer) {
        while let event = mpv_wait_event(mpv, 0), event.pointee.event_id != MPV_EVENT_NONE {
            switch event.pointee.event_id {
            case MPV_EVENT_FILE_LOADED:
                loaded = true
                Log.player.info("CROSSFADE tail FILE_LOADED")
            case MPV_EVENT_END_FILE:
                if let data = event.pointee.data?.assumingMemoryBound(to: mpv_event_end_file.self).pointee {
                    let reason = data.reason
                    if reason == MPV_END_FILE_REASON_ERROR {
                        failed = true
                        Log.player.error("CROSSFADE tail END_FILE error=\(String(cString: mpv_error_string(data.error)))")
                    } else {
                        Log.player.info("CROSSFADE tail END_FILE reason=\(reason.rawValue)")
                    }
                }
                loaded = false
            case MPV_EVENT_LOG_MESSAGE:
                if let msg = event.pointee.data?.assumingMemoryBound(to: mpv_event_log_message.self).pointee {
                    let prefix = msg.prefix.map { String(cString: $0) } ?? ""
                    let text = msg.text.map { String(cString: $0) } ?? ""
                    Log.player.info("CROSSFADE tail mpv[\(prefix)] \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
            default:
                break
            }
        }
    }

    func prepare(source path: String, audioFilter: String, start: TimeInterval) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                guard let mpv = handle() else { return done.resume() }
                pump(mpv)
                loaded = false
                failed = false
                var zero = Double(0)
                mpv_set_property(mpv, "volume", MPV_FORMAT_DOUBLE, &zero)
                mpv_set_property_string(mpv, "pause", "yes")
                mpv_set_property_string(mpv, "af", audioFilter)
                let args = ["loadfile", path, "replace", "-1", "start=\(String(format: "%.3f", start))"]
                let result = args.withUnsafeCArg { mpv_command(mpv, $0) }
                if result < 0 {
                    failed = true
                    Log.player.error("CROSSFADE tail loadfile failed: \(String(cString: mpv_error_string(result)))")
                }
                done.resume()
            }
        }
    }

    func resume() { set("pause", "no") }

    func stop() {
        queue.async { [self] in
            guard let mpv else { return }
            _ = ["stop"].withUnsafeCArg { mpv_command(mpv, $0) }
            pump(mpv)
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
            pump(mpv)
        }
    }

    func status() -> Status {
        queue.sync {
            guard let mpv else { return Status() }
            pump(mpv)
            func flag(_ name: String) -> Bool {
                var value: Int32 = 1
                return mpv_get_property(mpv, name, MPV_FORMAT_FLAG, &value) >= 0 ? value != 0 : true
            }
            func double(_ name: String) -> Double? {
                var value = Double(0)
                return mpv_get_property(mpv, name, MPV_FORMAT_DOUBLE, &value) >= 0 ? value : nil
            }
            var ao = ""
            if let raw = mpv_get_property_string(mpv, "current-ao") {
                ao = String(cString: raw)
                mpv_free(raw)
            }
            return Status(
                loaded: loaded,
                failed: failed,
                idleActive: flag("idle-active"),
                coreIdle: flag("core-idle"),
                audioOutput: ao,
                timePos: double("time-pos"),
                duration: double("duration")
            )
        }
    }

    private func set(_ name: String, _ value: String) {
        queue.async { [self] in
            guard let mpv else { return }
            mpv_set_property_string(mpv, name, value)
        }
    }
}
