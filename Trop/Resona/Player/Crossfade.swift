//
//  Crossfade.swift
//  Resona
//
//  Crossfade with two equivalent mpv instances (A/B) that take turns — no
//  handover in the middle of a song:
//
//  1. Shortly before the end the second instance (same configuration as
//     the main one) is made ACTIVE and the next song starts on it from 0,
//     silent (crossfade gain 0) — through the normal queue path, so
//     NowPlaying, lyrics clock, lock screen, history, seek, pause, EQ and
//     normalization all follow the active instance automatically.
//  2. The old song keeps playing on the previous instance until its end.
//  3. As soon as the new song's audio runs: equal-power crossfade (new sin,
//     old cos — as audible amplitudes, i.e. through mpv's cubic volume
//     curve) over the chosen length (bounded by what's left of the old
//     song). Then the old instance is stopped and becomes the spare.
//
//  Skip / pause / seek during the fade abort cleanly: the old instance stops
//  at once and the new one plays at full volume. Not used for manual skips,
//  repeat one, sleep timer "end of song", video mode, the end of the queue,
//  or same-album transitions with gapless on. With crossfade off nothing of
//  this runs (the spare is never created).
//

import Foundation
import QuartzCore

@MainActor
final class CrossfadeEngine {
    static let shared = CrossfadeEngine()

    private var monitor: Task<Void, Never>?
    private var run: Task<Void, Never>?
    /// The instance still playing the outgoing song during a fade.
    private var fading: OpaquePointer?
    private let log = Log.player

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
    /// Time between swapping instances and the old song's end: the next
    /// song needs a moment to resolve/buffer before it can fade in.
    private static let leadIn: Double = 2.5

    private func fmt(_ value: Double, _ digits: Int = 2) -> String {
        String(format: "%.\(digits)f", value)
    }

    private func tick() {
        let np = NowPlaying.shared
        guard run == nil else { return }
        let length = fadeSeconds
        guard length >= 1, let videoId = np.videoId, eligible(np, length: length) else { return }
        let player = PlayerController.shared
        let swapAt = np.duration - length - Self.leadIn
        let position = player.currentTime
        // Prepare the second instance well ahead.
        if position >= swapAt - 20, !player.hasSpareInstance {
            player.ensureSpareInstance()
        }
        guard position >= swapAt, position < swapAt + 1.5, player.hasSpareInstance else { return }
        run = Task { [weak self] in
            await self?.perform(videoId: videoId, length: length)
            self?.run = nil
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

    private func perform(videoId: String, length: Double) async {
        let player = PlayerController.shared
        let np = NowPlaying.shared
        let skipMark = np.lastManualSkipTime
        let base = SettingsStore.shared.playerVolume * 100
        guard np.videoId == videoId, np.isPlaying else { return }

        // 1) New song on the other instance, silent.
        player.crossfadeGain = 0
        guard let old = player.swapToSpareInstance() else {
            log.info("CROSSFADE skip: no spare instance")
            player.crossfadeGain = 1
            return
        }
        fading = old
        let oldTimes = player.playbackTimes(ofInstance: old)
        log.info("CROSSFADE start id=\(videoId) length=\(length)s old pos=\(fmt(oldTimes.position)) dur=\(fmt(oldTimes.duration))")
        np.playNext(automatic: true)
        let nextId = np.videoId
        func newValid() -> Bool { np.videoId == nextId && np.lastManualSkipTime == skipMark }

        // 2) Wait until the new song's audio actually runs.
        let started = await waitUntil({ player.currentTime > 0.05 && np.isPlaying }, while: newValid, timeout: 8)
        guard newValid() else {
            log.info("CROSSFADE abort: skip during start")
            return finish()
        }
        if !started {
            // New song didn't start in time: let it come in normally.
            log.error("CROSSFADE next song not started after 8 s → no fade")
            return finish()
        }

        // 3) Equal-power crossfade.
        let now = player.playbackTimes(ofInstance: old)
        let remaining = max(0.3, now.duration - now.position - 0.1)
        let fade = min(length, remaining)
        log.info("CROSSFADE fading over \(fmt(fade))s (old remaining \(fmt(remaining))s, new pos \(fmt(player.currentTime)))")
        var lastLog = CACurrentMediaTime()
        let completed = await ramp(duration: fade, while: { newValid() && np.isPlaying }) { t in
            // mpv's software volume is cubic (amplitude = (volume/100)³), so
            // the volume values are the cube roots of the wanted amplitudes:
            // that way the audible amplitudes really are sin/cos and the
            // power sum stays constant (measured: −6 dB dip without this).
            let mainGain = Self.volumeFactor(forAmplitude: sin(t * .pi / 2))
            let oldVolume = base * Self.volumeFactor(forAmplitude: cos(t * .pi / 2))
            player.crossfadeGain = mainGain
            player.setVolume(oldVolume, onInstance: old)
            if CACurrentMediaTime() - lastLog > 0.5 {
                lastLog = CACurrentMediaTime()
                let o = player.playbackTimes(ofInstance: old)
                self.log.info("CROSSFADE ramp t=\(self.fmt(t)) new=\(self.fmt(base * mainGain, 1)) old=\(self.fmt(oldVolume, 1)) oldPos=\(self.fmt(o.position)) newPos=\(self.fmt(player.currentTime))")
            }
        }
        log.info(completed ? "CROSSFADE finished" : "CROSSFADE aborted (skip/pause)")
        finish()
    }

    /// Factor for mpv's `volume` that yields `amplitude` (0…1) after mpv's
    /// cubic volume curve.
    nonisolated static func volumeFactor(forAmplitude amplitude: Double) -> Double {
        cbrt(min(1, max(0, amplitude)))
    }

    /// ~60 Hz ramp; `body` gets 0…1. Returns false when `valid` failed.
    private func ramp(duration: Double, while valid: () -> Bool, _ body: @escaping (Double) -> Void) async -> Bool {
        let start = CACurrentMediaTime()
        while true {
            guard valid() else { return false }
            let t = min(1, (CACurrentMediaTime() - start) / max(0.01, duration))
            body(t)
            PlayerController.shared.applyPlayerVolume()
            if t >= 1 { return true }
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

    /// Old instance stops (becomes the spare), new one at full volume.
    private func finish() {
        if let fading {
            PlayerController.shared.stopInstance(fading)
            self.fading = nil
        }
        PlayerController.shared.crossfadeGain = 1
        PlayerController.shared.applyPlayerVolume()
    }

    /// Manual skip / pause / seek while a crossfade runs.
    func cancel() {
        guard run != nil || fading != nil else { return }
        run?.cancel()
        run = nil
        finish()
    }
}
