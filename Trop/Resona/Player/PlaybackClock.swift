//
//  PlaybackClock.swift
//  Resona
//
//  High-resolution playback position for time-critical UI (synced lyrics).
//
//  NowPlaying.currentTime is refreshed by a 250 ms timer — fine for a seek bar,
//  far too coarse for word-level lyrics. The clock samples mpv's `time-pos` on
//  a background queue (never blocking the main thread on mpv's serial queue)
//  and extrapolates between samples with the host clock, so readers get a
//  smooth, monotonic position on every display frame (120 Hz on ProMotion).
//
//  Output latency: mpv's iOS audio output captures AVAudioSession.outputLatency
//  only when playback starts. If the route changes afterwards (e.g. AirPods
//  connect while playing), the heard audio drifts by the latency difference.
//  The clock tracks the latency at play start and subtracts any increase.
//

import AVFoundation
import Foundation
import Libmpv
import os
import QuartzCore
import SwiftUI

final class PlaybackClock: @unchecked Sendable {
    static let shared = PlaybackClock()

    private struct Sample {
        var position: TimeInterval = 0
        var host: CFTimeInterval = CACurrentMediaTime()
        var playing = false
        var latencyAtStart: TimeInterval = 0
        var currentLatency: TimeInterval = 0
        var lastReported: TimeInterval = 0
    }

    private let lock = OSAllocatedUnfairLock(initialState: Sample())
    private let queue = DispatchQueue(label: "dev.resona.playbackclock", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var subscribers = 0
    private var controller: PlayerController?

    private init() {}

    // MARK: Lifecycle

    /// Starts sampling (reference counted; call `release()` when done).
    @MainActor
    func retain() {
        subscribers += 1
        guard timer == nil else { return }
        // Seed from the player state so the very first frames (e.g. lyrics
        // opened mid-song) read the right position instead of a stale or
        // zero sample; the first real sample follows within 33 ms.
        let position = NowPlaying.shared.currentTime
        let playing = NowPlaying.shared.isPlaying
        lock.withLock {
            $0.position = position
            $0.host = CACurrentMediaTime()
            $0.playing = playing
            $0.lastReported = position
        }
        controller = PlayerController.shared
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(33), leeway: .milliseconds(4))
        t.setEventHandler { [weak self] in self?.sample() }
        t.resume()
        timer = t
    }

    @MainActor
    func release() {
        subscribers = max(0, subscribers - 1)
        guard subscribers == 0 else { return }
        timer?.cancel()
        timer = nil
    }

    /// Re-anchors immediately after a user seek so the UI doesn't wait for
    /// the next sample.
    func didSeek(to time: TimeInterval) {
        lock.withLock {
            $0.position = time
            $0.host = CACurrentMediaTime()
            $0.lastReported = time
        }
    }

    // MARK: Reading

    /// Current audible position in seconds (extrapolated, latency-corrected).
    func now() -> TimeInterval {
        let host = CACurrentMediaTime()
        return lock.withLock { s in
            var t = s.position
            if s.playing {
                // Never extrapolate further than a few samples — if mpv
                // stalls (buffering) the lyrics should stall too.
                t += min(max(0, host - s.host), 0.25)
            }
            // Route changed after playback started → audio is heard later.
            let latencyDrift = max(0, s.currentLatency - s.latencyAtStart)
            t -= latencyDrift
            // Monotonic while playing: hide tiny backwards jitter between
            // a fresh sample and the previous extrapolation.
            if s.playing, t < s.lastReported, s.lastReported - t < 0.12 {
                t = s.lastReported
            }
            s.lastReported = t
            return max(0, t)
        }
    }

    // MARK: Sampling (background queue)

    private func sample() {
        guard let controller else { return }
        let values: (pos: Double, paused: Bool)? = controller.withMpv { mpv in
            var pos = Double(0)
            var pause: Int32 = 1
            mpv_get_property(mpv, "time-pos", MPV_FORMAT_DOUBLE, &pos)
            mpv_get_property(mpv, "pause", MPV_FORMAT_FLAG, &pause)
            return (pos, pause != 0)
        }
        guard let values else { return }
        let host = CACurrentMediaTime()
        let latency = AVAudioSession.sharedInstance().outputLatency
        lock.withLock { s in
            let wasPlaying = s.playing
            let playing = !values.paused
            s.currentLatency = latency
            // Phase-locked tracking instead of hard re-anchoring: mpv's
            // time-pos arrives with a few ms of jitter, and snapping to every
            // sample made the time (and with it the word mask, lift and
            // glow) wobble back and forth. While playing steadily the
            // extrapolated line is nudged 15 % towards each sample; real
            // jumps (seek, pause/resume, > 0.25 s off) still snap.
            let predicted = s.position + max(0, host - s.host)
            let error = values.pos - predicted
            if playing, wasPlaying, abs(error) < 0.25 {
                s.position = predicted + error * 0.15
            } else {
                s.position = values.pos
            }
            s.host = host
            s.playing = playing
            if playing && !wasPlaying {
                // mpv re-reads outputLatency whenever its audio unit starts.
                s.latencyAtStart = latency
            }
            if !playing { s.lastReported = values.pos }
        }
    }
}

// MARK: - Smooth progress for views

/// Supplies the current playback time/progress on every display frame
/// while playing (from the PlaybackClock), so seek bars and rings glide
/// continuously like a clock hand instead of stepping with the 250 ms
/// NowPlaying timer; frozen while paused.
struct PlaybackProgressReader<Content: View>: View {
    @ViewBuilder let content: (_ time: TimeInterval, _ progress: Double) -> Content
    private let np = NowPlaying.shared

    var body: some View {
        TimelineView(.animation(paused: !np.isPlaying)) { _ in
            // Reading currentTime keeps paused views in sync after seeks.
            let fallback = np.currentTime
            let clock = PlaybackClock.shared.now()
            let t = np.isPlaying ? clock : (abs(clock - fallback) < 1 ? clock : fallback)
            let d = np.duration
            content(t, d > 0 ? min(max(t / d, 0), 1) : 0)
        }
        .onAppear { PlaybackClock.shared.retain() }
        .onDisappear { PlaybackClock.shared.release() }
    }
}
