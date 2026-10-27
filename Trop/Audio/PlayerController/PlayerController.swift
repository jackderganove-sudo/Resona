//
//  PlayerController.swift
//  Trop
//
//  Created by 686udjie on 28/06/2026.
//

import Foundation
import Libmpv
import MediaPlayer
import Combine
import AVFoundation
import UIKit
import Metal

// MARK: - DetectedCrop (parsed from mpv log)

struct DetectedCrop {
    let width: Int
    let height: Int
    let x: Int
    let y: Int
}

// MARK: - PlayerController

@MainActor
final class PlayerController {
    static let shared = PlayerController()

    nonisolated(unsafe) private var _mpv: OpaquePointer?
    /// Second, equivalent mpv instance for crossfades (A/B): created on
    /// demand, swapped with `_mpv` when the next song starts on it, while the
    /// old song fades out on the previous handle. Only the active handle's
    /// events drive the app.
    nonisolated(unsafe) private var _spare: OpaquePointer?
    /// Serial queue for all mpv property read/write calls
    let mpvAccessQueue = DispatchQueue(label: "com.686udjie.PlayerController.mpvAccess")

    nonisolated(unsafe) private var eventLoopThread: Thread?

    nonisolated(unsafe) var isRunning = false
    nonisolated(unsafe) var currentVideoId: String?
    nonisolated(unsafe) var pendingVideoId: String?
    private var lastDetectedCrop: String?
    private var detectedCropRepeatCount = 0
    var currentLoudnessDb: Double?
    var pendingURL: String?
    nonisolated(unsafe) var desiredPlaying = false
    /// Extra volume factor while a crossfade runs (CrossfadeEngine).
    nonisolated(unsafe) var crossfadeGain: Double = 1
    private var wasPlayingBeforeInterruption = false

    /// Video-mode state. Reads happen on the event loop thread from event handlers;
    /// writes happen on the main actor from `setVideoMode` / `loadFileReplacing`.
    /// Cross-thread access is serialized by the event loop reading these values
    /// synchronously before dispatching work to the main actor.
    nonisolated(unsafe) var videoModeSwitchInFlight = false
    nonisolated(unsafe) var loadedMuxedURL: String?
    nonisolated(unsafe) var loadedVideoOnlyURL: String?
    nonisolated(unsafe) var voWarmedVideoId: String?
    nonisolated(unsafe) var muxedActive = false
    nonisolated(unsafe) var muxedVideoId: String?
    nonisolated(unsafe) var hasPresentedVideo = false
    nonisolated(unsafe) var voInitDrawableSize: CGSize = .zero
    private var lastGeometryRefreshAt = Date.distantPast
    nonisolated(unsafe) var videoFlipAwaitingRestart = false
    private var videoAttachTask: Task<Bool, Never>?
    private var videoAttachTaskId: String?

    var videoLayer: CAMetalLayer = {
        let layer = CAMetalLayer()
        layer.device = MTLCreateSystemDefaultDevice()
        layer.framebufferOnly = true
        layer.isOpaque = false
        layer.contentsScale = 1
        layer.contentsGravity = .resizeAspect
        layer.backgroundColor = UIColor.clear.cgColor
        let bounds = CGRect(x: 0, y: 0, width: 320, height: 180)
        layer.frame = bounds
        layer.drawableSize = CGSize(
            width: bounds.width * layer.contentsScale,
            height: bounds.height * layer.contentsScale
        )
        return layer
    }()

    let playState = CurrentValueSubject<State, Never>(.stopped)
    var pendingResumeAt: TimeInterval = 0
    var nowPlayingInfo = [String: Any]()
    private var pendingSeek: (target: TimeInterval, deadline: Date)?

    var currentTime: TimeInterval {
        withMpv { mpv in
            var val = Double(0)
            mpv_get_property(mpv, "time-pos", MPV_FORMAT_DOUBLE, &val)
            return val
        } ?? 0
    }

    /// What mpv is playing right now (resolved stream URL or local file)
    /// and its audio filter chain — the crossfade tail reuses both.
    var currentSource: (path: String, audioFilter: String)? {
        withMpv { mpv -> (path: String, audioFilter: String)? in
            guard let raw = mpv_get_property_string(mpv, "path") else { return nil }
            let path = String(cString: raw)
            mpv_free(raw)
            var filter = ""
            if let af = mpv_get_property_string(mpv, "af") {
                filter = String(cString: af)
                mpv_free(af)
            }
            return (path, filter)
        } ?? nil
    }

    var duration: TimeInterval {
        withMpv { mpv in
            var val = Double(0)
            mpv_get_property(mpv, "duration", MPV_FORMAT_DOUBLE, &val)
            return val
        } ?? 0
    }

    enum State: Equatable { case stopped, playing, paused }

    private init() {
        assertAudioSession()
        setupRemoteCommands()
        observeInterruptions()
        observeAudioSessionReset()
        startMpv()
    }

    deinit {
        isRunning = false
        if let mpv = _mpv { mpv_wakeup(mpv) }
    }

    nonisolated func withMpv<T: Sendable>(_ body: @escaping @Sendable (OpaquePointer) -> T) -> T? {
        var result: T?
        mpvAccessQueue.sync {
            guard let handle = _mpv else { return }
            result = body(handle)
        }
        return result
    }

    /// Fire-and-forget variant for UI-triggered writes (play/pause, seek,
    /// volume): the main thread never waits on mpv's serial queue, which
    /// can be busy loading a stream (Resona: tap latency).
    nonisolated func withMpvAsync(_ body: @escaping @Sendable (OpaquePointer) -> Void, completion: (@MainActor @Sendable () -> Void)? = nil) {
        mpvAccessQueue.async { [weak self] in
            guard let handle = self?._mpv else { return }
            body(handle)
            if let completion {
                Task { @MainActor in completion() }
            }
        }
    }

    // MARK: - Layer helper

    func clearVideoLayer() {
        guard let device = videoLayer.device,
              let queue = device.makeCommandQueue(),
              let commandBuffer = queue.makeCommandBuffer(),
              let drawable = videoLayer.nextDrawable() else { return }
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = drawable.texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) {
            encoder.endEncoding()
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    @MainActor
    func applyPendingResumeIfNeeded() {
        guard pendingResumeAt > 0 else { return }
        let target = pendingResumeAt
        pendingResumeAt = 0
        seek(to: target)
    }
}

// MARK: - Playback

extension PlayerController {
    @MainActor
    func play(
        url: String,
        title: String? = nil,
        artist: String? = nil,
        videoId: String? = nil,
        duration: TimeInterval? = nil,
        artists: [YTArtist] = [],
        loudnessDb: Double? = nil,
        thumbnailUrl: String? = nil
    ) async {
        currentLoudnessDb = loudnessDb
        guard let url = URL(string: url) else {
            Log.player.error("Invalid URL: \(url)")
            return
        }

        if let videoId, let title, videoId != NowPlaying.shared.videoId {
            NowPlaying.shared.update(title: title, artist: artist, videoId: videoId, artists: artists, thumbnailUrl: thumbnailUrl)
        }

        let skipStart = await SponsorBlockIntegration.shared.preloadedStartOffset(for: videoId)
        guard NowPlaying.shared.videoId == videoId else {
            return
        }

        let prevVideoId = currentVideoId
        let isNewSong = prevVideoId != nil && videoId != prevVideoId

        desiredPlaying = true
        assertAudioSession()
        loadedMuxedURL = nil
        loadedVideoOnlyURL = nil
        voWarmedVideoId = nil
        muxedActive = false
        muxedVideoId = nil
        pendingResumeAt = 0
        pendingSeek = nil
        videoModeSwitchInFlight = false
        videoFlipAwaitingRestart = false
        NowPlaying.shared.isVideoMode = false
        NowPlaying.shared.isVideoReady = false
        if hasPresentedVideo { clearVideoLayer() }
        let isReady = withMpv { _ in true } ?? false
        guard isReady else {
            Log.player.info("mpv not ready yet, parking URL for deferred load")
            pendingURL = url.absoluteString
            pendingVideoId = videoId
            return
        }

        applyPlaybackSettings()
        setVideoCrop(.none)

        pendingVideoId = videoId
        let loadStart = skipStart > 0 ? Int(skipStart.rounded(.up)) : 0
        let loadArguments = loadStart > 0
            ? ["loadfile", url.absoluteString, "replace", "-1", "start=\(loadStart)"]
            : ["loadfile", url.absoluteString, "replace"]
        Log.player.info(
            "TRANSITION play videoId=\(videoId ?? "nil") isNewSong=\(isNewSong) muxedActive=\(muxedActive) "
                + "url=\(url.absoluteString.prefix(80))"
        )
        let cmdResult = withMpv { mpv -> Int32 in
            mpv_set_property_string(mpv, "pause", "no")
            return loadArguments.withUnsafeCArg { mpv_command(mpv, $0) }
        } ?? -1
        if cmdResult != 0 {
            Log.player.error("mpv_command loadfile failed result=\(cmdResult)")
            pendingVideoId = nil
            return
        }
        if isNewSong {
            await PlaybackStateService.shared.stopTracking()
        }
        if let videoId { await PlaybackStateService.shared.startTracking(videoId: videoId) }
        playState.send(.playing)
        NowPlaying.shared.isPlaying = true
        NowPlaying.shared.currentTime = 0
        NowPlaying.shared.duration = max(0, duration ?? 0)
        setNowPlayingMetadata()
    }

    func seek(to time: TimeInterval) {
        CrossfadeEngine.shared.cancel()
        pendingSeek = (time, Date().addingTimeInterval(1.5))
        NowPlaying.shared.currentTime = time
        PlaybackClock.shared.didSeek(to: time)
        withMpvAsync { mpv in
            var val = time
            let result = mpv_set_property(mpv, "time-pos", MPV_FORMAT_DOUBLE, &val)
            if result < 0 { Log.player.error("seek failed: mpv error \(result)") }
        }
    }

    func setPaused(_ paused: Bool) {
        if paused { CrossfadeEngine.shared.cancel() }
        desiredPlaying = !paused
        let currentlyPaused = playState.value != .playing
        guard currentlyPaused != paused else {
            updateNowPlayingProgress()
            return
        }
        // Optimistic: the UI flips immediately, mpv follows asynchronously.
        playState.send(paused ? .paused : .playing)
        NowPlaying.shared.isPlaying = !paused
        if !paused { assertAudioSession() }
        withMpvAsync({ mpv in
            var flag: Int32 = paused ? 1 : 0
            mpv_set_property(mpv, "pause", MPV_FORMAT_FLAG, &flag)
        }, completion: { [weak self] in
            self?.updateNowPlayingProgress()
        })
    }

    func togglePlayPause() {
        setPaused(playState.value == .playing)
    }

    func applyPlayerVolume() {
        let vol = SettingsStore.shared.playerVolume
        let gain = crossfadeGain
        withMpvAsync { mpv in
            var val = Double(vol * 100) * gain
            mpv_set_property(mpv, "volume", MPV_FORMAT_DOUBLE, &val)
        }
    }

    func applyPlaybackSettings() {
        let settings = SettingsStore.shared
        let loudness = currentLoudnessDb
        let eqEnabled = settings.equalizerEnabled
        let eqGains = settings.equalizerGains
        let gapless = settings.gaplessPlayback
        let norm = settings.audioNormalization

        let chain: String = {
            var filters: [String] = []
            if eqEnabled {
                let entries = zip(equalizerFrequencies, eqGains)
                    .map { "entry(\(Self.fmt($0.0)),\(Self.fmt($0.1)))" }
                    .joined(separator: ";")
                if !entries.isEmpty {
                    filters.append("firequalizer=gain_entry=\"\(entries)\"")
                }
            }
            if norm, let loudness, loudness.isFinite {
                let gain = max(-12, min(12, -14 - loudness))
                filters.append("volume=\(Self.fmt(gain))dB")
            }
            return filters.joined(separator: ",")
        }()

        withMpv { mpv in
            mpv_set_property_string(mpv, "gapless-audio", gapless ? "yes" : "no")
            let result = mpv_set_property_string(mpv, "af", chain.isEmpty ? "" : chain)
            if result < 0 { Log.player.error("Failed to set af chain '\(chain)': mpv error \(result)") }
        }
        applyPlayerVolume()
    }

    private static func fmt(_ value: Double) -> String {
        String(format: "%.4f", value)
    }
}

// MARK: - mpv lifecycle & event loop

extension PlayerController {
    fileprivate func startMpv() {
        mpvAccessQueue.async { [weak self] in
            guard let self else { return }
            _ = setenv("MVK_CONFIG_LOG_LEVEL", "1", 1)
            guard let mpv = Self.createConfiguredHandle() else { return }

            self._mpv = mpv
            Log.player.info("mpv handle published — event loop starting")

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.applyPlaybackSettings()
                if let url = self.pendingURL {
                    self.pendingURL = nil
                    Log.player.info("mpv ready: loading deferred URL \(url.prefix(80))")
                    _ = self.withMpv { mpv in
                        mpv_set_property_string(mpv, "pause", "no")
                        return ["loadfile", url, "replace"].withUnsafeCArg { mpv_command(mpv, $0) }
                    }
                }
            }

            let thread = Thread { [weak self] in
                guard let self else { return }
                self.isRunning = true
                self.eventLoop(mpv)
            }
            self.eventLoopThread = thread
            thread.name = "com.686udjie.PlayerController.eventLoop"
            thread.start()
        }
    }

    /// Creates a fully configured mpv instance (startup options, init,
    /// post-init properties, observed properties) — used for the main
    /// handle and for the crossfade spare, so both are identical.
    nonisolated static func createConfiguredHandle() -> OpaquePointer? {
        guard let mpv = mpv_create() else {
            Log.player.error("mpv_create failed")
            return nil
        }
        mpv_request_log_messages(mpv, "warn")
        applyMpvStartupOptions(mpv)
        Log.player.info("mpv initializing...")
        let initResult = mpv_initialize(mpv)
        guard initResult >= 0 else {
            let errStr = String(cString: mpv_error_string(initResult))
            Log.player.error("mpv_initialize failed: \(initResult) (\(errStr))")
            mpv_destroy(mpv)
            return nil
        }
        Log.player.info("mpv initialized successfully")
        applyPostInitProperties(mpv)
        applyObservedProperties(mpv)
        return mpv
    }

    /// Shared with the crossfade tail so both instances use identical
    /// network/cache/audio-session options.
    nonisolated static func applyMpvStartupOptions(_ mpv: OpaquePointer) {
        mpv_set_option_string(mpv, "vo", "null")
        mpv_set_option_string(mpv, "vid", "no")
        mpv_set_option_string(mpv, "force-window", "no")
        mpv_set_option_string(mpv, "msg-level", "all=error")

        #if targetEnvironment(simulator)
        mpv_set_option_string(mpv, "hwdec", "no")
        mpv_set_option_string(mpv, "audio-exclusive", "no")
        #else
        mpv_set_option_string(mpv, "hwdec", "videotoolbox")
        mpv_set_option_string(mpv, "audio-exclusive", "yes")
        #endif

        mpv_set_option_string(mpv, "keep-open", "no")
        mpv_set_option_string(mpv, "cache", "yes")
        mpv_set_option_string(mpv, "cache-secs", "120")
        mpv_set_option_string(mpv, "demuxer-max-bytes", "200M")
        mpv_set_option_string(mpv, "gapless-audio", "yes")
    }

    nonisolated static func applyPostInitProperties(_ mpv: OpaquePointer) {
        if let caPath = Bundle.main.path(forResource: "cacert", ofType: "pem") {
            mpv_set_property_string(mpv, "tls-ca-file", caPath)
            Log.player.info("mpv tls-ca-file set: \(caPath)")
        } else {
            Log.player.warning("mpv cacert.pem not found in main bundle")
        }
        let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15" +
            " (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        mpv_set_property_string(mpv, "user-agent", userAgent)
        mpv_set_property_string(mpv, "video-unscaled", "no")
        mpv_set_property_string(mpv, "keepaspect", "no")
    }

    nonisolated private static func applyObservedProperties(_ mpv: OpaquePointer) {
        mpv_observe_property(mpv, 0, "duration", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 1, "video-params/w", MPV_FORMAT_INT64)
        mpv_observe_property(mpv, 2, "video-out-params", MPV_FORMAT_NODE)
    }

    nonisolated fileprivate func eventLoop(_ mpv: OpaquePointer) {
        while isRunning {
            guard let event = mpv_wait_event(mpv, 0.2) else { continue }
            // Crossfade A/B: the fading (inactive) instance must never drive
            // NowPlaying — its END_FILE would look like the new song ending.
            if mpv != _mpv {
                if event.pointee.event_id == MPV_EVENT_END_FILE {
                    Log.player.info("CROSSFADE inactive instance END_FILE (ignored)")
                }
                continue
            }
            switch event.pointee.event_id {
            case MPV_EVENT_NONE:
                break
            case MPV_EVENT_LOG_MESSAGE:
                handleLogMessage(event)
            case MPV_EVENT_FILE_LOADED:
                handleFileLoaded(mpv)
            case MPV_EVENT_PROPERTY_CHANGE:
                handlePropertyChange(event)
            case MPV_EVENT_START_FILE:
                Log.player.debug("TRANSITION START_FILE")
            case MPV_EVENT_END_FILE:
                handleEndFile(event)
            case MPV_EVENT_VIDEO_RECONFIG:
                handleVideoReconfig()
            case MPV_EVENT_PLAYBACK_RESTART:
                handlePlaybackRestart()
            default:
                break
            }
        }
        mpvAccessQueue.sync {
            if self._mpv == mpv { self._mpv = nil }
            if self._spare == mpv { self._spare = nil }
        }
        mpv_destroy(mpv)
    }

    nonisolated private func handleLogMessage(_ event: UnsafeMutablePointer<mpv_event>) {
        if let prop = event.pointee.data?.load(as: mpv_event_log_message.self),
           let textPtr = prop.text {
            let text = String(cString: textPtr)
            let prefix = prop.prefix.map { String(cString: $0) } ?? ""
            let level = prop.level.map { String(cString: $0) } ?? ""
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if trimmed.range(of: "primitive restart", options: .caseInsensitive) != nil { return }
                Log.mpv.debug("[\(prefix)] [\(level)] \(trimmed)")
                if let crop = detectedCrop(from: trimmed) {
                    Task { @MainActor in self.applyDetectedCrop(crop) }
                }
            }
        }
    }

    nonisolated private func handleFileLoaded(_ mpv: OpaquePointer) {
        var pauseFlag = Int32(1)
        mpv_get_property(mpv, "pause", MPV_FORMAT_FLAG, &pauseFlag)
        if pauseFlag != 0, desiredPlaying {
            var unpause = Int32(0)
            mpv_set_property(mpv, "pause", MPV_FORMAT_FLAG, &unpause)
            mpv_get_property(mpv, "pause", MPV_FORMAT_FLAG, &pauseFlag)
        }
        let actuallyPlaying = pauseFlag == 0
        let pendingVideoId = self.pendingVideoId
        Task { @MainActor [weak self] in
            guard let self else { return }
            Log.player.debug("TRANSITION FILE_LOADED videoId=\(pendingVideoId ?? "nil") playing=\(actuallyPlaying)")
            self.playState.send(actuallyPlaying ? .playing : .paused)
            NowPlaying.shared.isPlaying = actuallyPlaying
            self.currentVideoId = pendingVideoId
            self.pendingVideoId = nil
            self.assertAudioSession()
            self.setNowPlayingMetadata()
            self.applyPendingResumeIfNeeded()
            let checkId = pendingVideoId
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard self.currentVideoId == checkId else { return }
                self.updateNowPlayingArtwork()
                self.updateNowPlayingProgress()
            }
        }
    }

    nonisolated private func handlePropertyChange(_ event: UnsafeMutablePointer<mpv_event>) {
        guard let prop = event.pointee.data?.load(as: mpv_event_property.self),
              let namePtr = prop.name else { return }
        let name = String(cString: namePtr)

        if name == "duration", prop.format == MPV_FORMAT_DOUBLE {
            let newDur: Double = prop.data?.load(as: Double.self) ?? 0
            if newDur > 0 {
                Task { @MainActor in
                    NowPlaying.shared.duration = newDur
                    self.setNowPlayingMetadata()
                }
            }
        } else if name == "video-params/w", prop.format == MPV_FORMAT_INT64 {
            let width: Int64 = prop.data?.load(as: Int64.self) ?? 0
            if width > 0 {
                Task { @MainActor in
                    let ok = self.muxedActive && NowPlaying.shared.videoId == self.muxedVideoId
                    guard ok else { return }
                    if self.hasPresentedVideo { self.clearVideoLayer() }
                    // Only the flip owns the mount; background prerender must
                    // never pop the UI (ready is still recorded below).
                    if self.videoModeSwitchInFlight { NowPlaying.shared.isVideoMode = true }
                    self.hasPresentedVideo = true
                }
            }
        } else if name == "video-out-params", prop.format == MPV_FORMAT_NODE {
            Task { @MainActor in
                let ok = self.muxedActive && NowPlaying.shared.videoId == self.muxedVideoId
                guard ok else { return }
                if self.videoModeSwitchInFlight { NowPlaying.shared.isVideoMode = true }
                NowPlaying.shared.isVideoReady = true
                self.hasPresentedVideo = true
            }
        }
    }

    nonisolated private func handleVideoReconfig() {
        Task { @MainActor in
            let ok = self.muxedActive && NowPlaying.shared.videoId == self.muxedVideoId
            guard ok else { return }
            if self.videoModeSwitchInFlight { NowPlaying.shared.isVideoMode = true }
            NowPlaying.shared.isVideoReady = true
            self.hasPresentedVideo = true
        }
    }

    nonisolated private func handlePlaybackRestart() {
        let flipPending = self.videoFlipAwaitingRestart
        Task { @MainActor in
            guard flipPending else { return }
            let ok = self.muxedActive && NowPlaying.shared.videoId == self.muxedVideoId
            self.videoFlipAwaitingRestart = false
            guard ok else { return }
            if self.videoModeSwitchInFlight { NowPlaying.shared.isVideoMode = true }
            NowPlaying.shared.isVideoReady = true
            self.hasPresentedVideo = true
        }
    }

    nonisolated private func handleEndFile(_ event: UnsafeMutablePointer<mpv_event>) {
        guard let data = event.pointee.data else { return }
        let endFile = data.load(as: mpv_event_end_file.self)
        let reason = endFile.reason
        let isEof = reason == MPV_END_FILE_REASON_EOF
        let isError = reason == MPV_END_FILE_REASON_ERROR
        let stoppedVideoId = self.currentVideoId
        Task { @MainActor [weak self] in
            guard let self else { return }
            let videoId = stoppedVideoId
            Log.player.debug(
                "TRANSITION END_FILE reason=\(reason.rawValue) isEof=\(isEof) isError=\(isError) stoppedVideoId=\(videoId ?? "nil")"
            )
            if isError, videoId != nil {
                Task { await PlaybackStateService.shared.stopTracking() }
            }
            if isEof {
                self.playState.send(.stopped)
                NowPlaying.shared.stopped(videoId: videoId, isEof: true)
            } else if isError {
                self.currentVideoId = nil
                self.playState.send(.stopped)
                NowPlaying.shared.stopped(videoId: videoId, isEof: false)
            } else {
                Log.player.debug("END_FILE non-EOF ignored for auto-advance")
            }
        }
    }
}

// MARK: - Video mode

extension PlayerController {
    func setVideoMode() {
        // No real video (e.g. art-track): stay in the big player, do nothing.
        guard NowPlaying.shared.hasVideo else { return }
        guard let videoId = NowPlaying.shared.videoId else { return }
        if muxedActive {
            NowPlaying.shared.isVideoMode = true
            NowPlaying.shared.isVideoReady = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard NowPlaying.shared.videoId == videoId,
                      NowPlaying.shared.isVideoMode else { return }
                guard self.videoLayerDrifted() else { return }
                NowPlaying.shared.isVideoReady = false
                self.setVideoTrack()
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard NowPlaying.shared.videoId == videoId,
                      NowPlaying.shared.isVideoMode,
                      !NowPlaying.shared.isVideoReady else { return }
                NowPlaying.shared.isVideoReady = true
            }
            return
        }
        guard !videoModeSwitchInFlight else { return }
        videoModeSwitchInFlight = true
        NowPlaying.shared.isVideoMode = true
        NowPlaying.shared.isVideoReady = false
        Task {
            defer { videoModeSwitchInFlight = false }
            if loadedVideoOnlyURL != nil {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard NowPlaying.shared.videoId == videoId else { return }
            }
            do {
                guard await ensureVideoAttached(videoId: videoId) else {
                    throw StreamError.noSuitableFormat
                }
                guard NowPlaying.shared.videoId == videoId, NowPlaying.shared.isVideoMode else { return }
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard NowPlaying.shared.videoId == videoId, NowPlaying.shared.isVideoMode else { return }
                Log.player.debug("TRANSITION video flipped videoId=\(videoId)")
                NowPlaying.shared.isVideoReady = true
                return
            } catch {
                Log.player.debug("video attach failed, falling back to EDL replace: \(error)")
            }
            do {
                videoFlipAwaitingRestart = false
                let resumeAt = currentTime
                let url: String
                if let loaded = loadedMuxedURL {
                    url = loaded
                } else {
                    url = try await PlaybackManager.shared.resolveMuxedURL(videoId: videoId)
                    guard NowPlaying.shared.videoId == videoId else { return }
                    loadedMuxedURL = url
                }
                guard NowPlaying.shared.videoId == videoId else { return }
                setVideoTrack()
                Log.player.debug("TRANSITION entering video mode videoId=\(videoId) url=\(url.prefix(80))")
                muxedVideoId = videoId
                pendingVideoId = videoId
                loadFileReplacing(url, startAt: resumeAt)
                muxedActive = true
            } catch {
                Log.player.error("setVideoMode failed: \(error)")
                NowPlaying.shared.isVideoMode = false
                NowPlaying.shared.isVideoReady = false
            }
        }
    }

    func ensureVideoAttached(videoId: String) async -> Bool {
        if muxedActive, muxedVideoId == videoId { return true }
        if let task = videoAttachTask, videoAttachTaskId == videoId {
            return await task.value
        }
        let task = Task<Bool, Never> { [weak self] in
            guard let self else { return false }
            return await self.attachVideoTrack(videoId: videoId)
        }
        videoAttachTask = task
        videoAttachTaskId = videoId
        let result = await task.value
        if videoAttachTaskId == videoId {
            videoAttachTask = nil
            videoAttachTaskId = nil
        }
        return result
    }

    private func attachVideoTrack(videoId: String) async -> Bool {
        do {
            // Already initialized at the right size by preload? Don't churn.
            if voWarmedVideoId != videoId || videoLayerDrifted() {
                setVideoTrack()
            }
            let videoURL: String
            if let preloaded = loadedVideoOnlyURL {
                videoURL = preloaded
            } else {
                videoURL = try await PlaybackManager.shared.resolveVideoOnlyURL(videoId: videoId)
                guard NowPlaying.shared.videoId == videoId else { return false }
                loadedVideoOnlyURL = videoURL
            }
            guard NowPlaying.shared.videoId == videoId else { return false }
            let addResult = withMpv { mpv in
                ["video-add", videoURL, "select"].withUnsafeCArg { mpv_command(mpv, $0) }
            } ?? -1
            guard addResult == 0 else { throw StreamError.noSuitableFormat }
            guard await waitForVideoTrack(videoId: videoId) else { throw StreamError.noSuitableFormat }
            guard NowPlaying.shared.videoId == videoId else { return false }
            muxedVideoId = videoId
            muxedActive = true
            voInitDrawableSize = videoLayer.drawableSize
            // video-add starts at 0 while audio is live — seek both to now.
            let syncAt = currentTime
            videoFlipAwaitingRestart = true
            let seekResult = withMpv { mpv in
                ["seek", String(syncAt), "absolute"].withUnsafeCArg { mpv_command(mpv, $0) }
            } ?? -1
            guard seekResult == 0 else {
                videoFlipAwaitingRestart = false
                throw StreamError.noSuitableFormat
            }
            _ = await waitForFlipRestart(videoId: videoId)
            guard NowPlaying.shared.videoId == videoId else { return false }
            videoFlipAwaitingRestart = false
            return true
        } catch {
            videoFlipAwaitingRestart = false
            Log.player.debug("video attach failed videoId=\(videoId): \(error)")
            return false
        }
    }

    private func waitForVideoTrack(videoId: String) async -> Bool {
        for _ in 0..<60 {
            guard NowPlaying.shared.videoId == videoId else { return false }
            let width: Int64 = withMpv { mpv in
                var w = Int64(0)
                mpv_get_property(mpv, "video-params/w", MPV_FORMAT_INT64, &w)
                return w
            } ?? 0
            if width > 0 { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }

    private func waitForFlipRestart(videoId: String) async -> Bool {
        for _ in 0..<50 {
            guard NowPlaying.shared.videoId == videoId else { return false }
            if !videoFlipAwaitingRestart { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }

    func preloadVideoURL() {
        guard let videoId = NowPlaying.shared.videoId else { return }
        guard !isVideoPrerendered(videoId: videoId) else { return }
        Task {
            if loadedVideoOnlyURL == nil {
                do {
                    let url = try await PlaybackManager.shared.resolveVideoOnlyURL(videoId: videoId)
                    guard NowPlaying.shared.videoId == videoId, loadedVideoOnlyURL == nil else { return }
                    loadedVideoOnlyURL = url
                } catch {
                    Log.player.error("Video preload failed: \(error)")
                    return
                }
            }
        }
    }

    private func isVideoPrerendered(videoId: String) -> Bool {
        loadedVideoOnlyURL != nil && voWarmedVideoId == videoId
            && muxedActive && muxedVideoId == videoId
    }

    func handleVideoStreamFailure() {
        guard muxedActive || videoModeSwitchInFlight else { return }
        loadedMuxedURL = nil
        loadedVideoOnlyURL = nil
        voWarmedVideoId = nil
        muxedActive = false
        muxedVideoId = nil
        videoModeSwitchInFlight = false
        videoFlipAwaitingRestart = false
        NowPlaying.shared.isVideoMode = false
        NowPlaying.shared.isVideoReady = false
    }

    private func setVideoTrack() {
        lastDetectedCrop = nil
        detectedCropRepeatCount = 0
        if videoLayer.superlayer == nil {
            presizeVideoLayerForExpectedFrame()
        }
        voInitDrawableSize = videoLayer.drawableSize
        let wid: Int64 = unsafeBitCast(videoLayer, to: Int64.self)
        withMpv { mpv in
            mpv_set_property_string(mpv, "vo", "null")
            mpv_set_property_string(mpv, "vo", "gpu-next")
            mpv_set_property_string(mpv, "gpu-api", "vulkan")
            mpv_set_property_string(mpv, "gpu-context", "moltenvk")
            var widCopy = wid
            mpv_set_property(mpv, "wid", MPV_FORMAT_INT64, &widCopy)
            mpv_set_property_string(mpv, "vid", "auto")
        }
        setVideoCrop(.none)
    }

    private func presizeVideoLayerForExpectedFrame() {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        guard let window = windows.first(where: { $0.isKeyWindow }) ?? windows.first else { return }
        let width = window.bounds.width - 64
        guard width > 0 else { return }
        let height = width * 9 / 16
        let scale = window.screen.nativeScale > 0 ? window.screen.nativeScale : 3
        videoLayer.frame = CGRect(x: 0, y: 0, width: width, height: height)
        videoLayer.contentsScale = scale
        videoLayer.drawableSize = CGSize(width: (width * scale).rounded(), height: (height * scale).rounded())
    }

    func videoLayerDrifted() -> Bool {
        let baseline = voInitDrawableSize
        guard baseline.width > 0, baseline.height > 0 else { return false }
        let current = videoLayer.drawableSize
        return abs(current.width - baseline.width) > 2 || abs(current.height - baseline.height) > 2
    }

    func refreshVideoGeometryIfNeeded() {
        guard muxedActive || hasPresentedVideo else { return }
        guard videoLayerDrifted() else { return }
        guard Date().timeIntervalSince(lastGeometryRefreshAt) > 0.5 else { return }
        lastGeometryRefreshAt = Date()
        Log.player.debug("TRANSITION video VO restart for geometry")
        setVideoTrack()
    }

    nonisolated private func detectedCrop(from log: String) -> DetectedCrop? {
        guard let marker = log.range(of: "crop=") else { return nil }
        let values = log[marker.upperBound...]
            .split(whereSeparator: { $0 == Character(":") || $0 == Character(" ") || $0 == Character("\n") })
            .prefix(4)
            .compactMap { Int($0) }
        guard values.count == 4 else { return nil }
        return DetectedCrop(width: values[0], height: values[1], x: values[2], y: values[3])
    }

    private func applyDetectedCrop(_ crop: DetectedCrop) {
        guard crop.width > 0, crop.height > 0 else { return }
        let signature = "\(crop.width)x\(crop.height)+\(crop.x)+\(crop.y)"
        if lastDetectedCrop == signature {
            detectedCropRepeatCount += 1
        } else {
            lastDetectedCrop = signature
            detectedCropRepeatCount = 1
        }
        guard detectedCropRepeatCount >= 2 else { return }
        _ = withMpv { mpv in
            mpv_set_property_string(mpv, "video-crop", signature)
        }
    }

    enum VideoCropMode { case none, square }

    private struct VideoDims: Sendable {
        var width: Int64
        var height: Int64
        var hasVid: Bool
    }

    private func setVideoCrop(_ mode: VideoCropMode) {
        switch mode {
        case .none:
            _ = withMpv { mpv in
                mpv_set_property_string(mpv, "video-crop", "")
            }
        case .square:
            let dims: VideoDims = withMpv { mpv in
                var w = Int64(0), h = Int64(0)
                mpv_get_property(mpv, "video-params/w", MPV_FORMAT_INT64, &w)
                mpv_get_property(mpv, "video-params/h", MPV_FORMAT_INT64, &h)
                var vid: UnsafeMutablePointer<CChar>?
                defer { if let vid { mpv_free(vid) } }
                let hasVid = mpv_get_property(mpv, "vid", MPV_FORMAT_STRING, &vid) == 0
                    && vid.map { String(cString: $0) != "no" } ?? false
                return VideoDims(width: w, height: h, hasVid: hasVid)
            } ?? VideoDims(width: 0, height: 0, hasVid: false)
            if dims.width > 0, dims.height > 0 {
                let side = min(dims.width, dims.height)
                _ = withMpv { mpv in
                    mpv_set_property_string(mpv, "video-crop", "\(side)x\(side)")
                }
            } else if dims.hasVid {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    self.setVideoCrop(.square)
                }
            }
        }
    }

    private func loadFileReplacing(_ url: String, startAt: TimeInterval = 0) {
        pendingResumeAt = startAt
        Log.player.debug("TRANSITION loadFileReplacing startAt=\(startAt) url=\(url.prefix(80))")
        withMpv { mpv in
            let args = ["loadfile", url, "replace"]
            _ = args.withUnsafeCArg { mpv_command(mpv, $0) }
        }
    }
}

// MARK: - Audio session / interruption handling

extension PlayerController {
    func assertAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            if session.category != .playback || session.mode != .default {
                try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
            }
            try session.setActive(true)
        } catch {
            Log.player.error("Failed to assert audio session: \(error)")
        }
    }

    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            Log.player.info("AUDIO_INTERRUPTION began")
            wasPlayingBeforeInterruption = desiredPlaying || playState.value == .playing
            if playState.value == .playing {
                Task { @MainActor in
                    self.setPaused(true)
                    self.desiredPlaying = self.wasPlayingBeforeInterruption
                }
            }
        case .ended:
            let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            let shouldResume = options.contains(.shouldResume) || wasPlayingBeforeInterruption
            Log.player.info("AUDIO_INTERRUPTION ended")
            Task { @MainActor in
                guard shouldResume else { return }
                self.assertAudioSession()
                if self.playState.value != .playing {
                    self.setPaused(false)
                }
                self.wasPlayingBeforeInterruption = false
            }
        @unknown default:
            break
        }
    }

    private func observeAudioSessionReset() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionReset),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: nil
        )
    }

    @objc private func handleAudioSessionReset() {
        Log.player.notice("AUDIO_SESSION reset")
        Task { @MainActor in
            self.assertAudioSession()
            self.setNowPlayingMetadata()
            if self.desiredPlaying, self.playState.value != .playing {
                self.setPaused(false)
            }
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        Log.player.info("ROUTE_CHANGE reason=\(reason.rawValue)")
        // Headphones / Bluetooth disconnected: always PAUSE (a toggle could
        // start playback if the state was stale).
        if reason == .oldDeviceUnavailable {
            Task { @MainActor in
                if self.playState.value == .playing || self.desiredPlaying { self.setPaused(true) }
            }
        }
    }
}

// MARK: - Now Playing info / lock-screen

extension PlayerController {
    func setNowPlayingMetadata() {
        assertAudioSession()
        let np = NowPlaying.shared
        nowPlayingInfo.removeAll()

        let liveDur = withMpv { mpv in
            var val = Double(0)
            mpv_get_property(mpv, "duration", MPV_FORMAT_DOUBLE, &val)
            return val
        } ?? 0
        let duration = liveDur > 0 ? liveDur : np.duration
        if duration > 0 { np.duration = duration }

        let livePos = withMpv { mpv in
            var val = Double(0)
            mpv_get_property(mpv, "time-pos", MPV_FORMAT_DOUBLE, &val)
            return val
        } ?? 0
        let elapsed = livePos > 0 ? livePos : np.currentTime

        nowPlayingInfo[MPMediaItemPropertyTitle] = np.title
        nowPlayingInfo[MPMediaItemPropertyArtist] = np.displayArtist
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = np.albumTitle
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = np.isPlaying ? 1 : 0
        nowPlayingInfo[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        nowPlayingInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1
        if duration > 0 { nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration }
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueIndex] = np.queueIndex
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueCount] = np.queueSongs.count
        if let image = np.thumbnailUIImage {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = Self.artwork(image)
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        MPNowPlayingInfoCenter.default().playbackState = np.isPlaying ? .playing : .paused
        syncRemoteCommandState()
        Log.player.info(
            "NOW_PLAYING_PUBLISH title='\(np.title)' artist='\(np.artist)' " +
            "duration=\(duration) rate=\(nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] ?? 0) " +
            "artwork=\(np.thumbnailUIImage != nil) keys=\(nowPlayingInfo.keys.count)"
        )
    }

    func updateNowPlayingArtwork() {
        let np = NowPlaying.shared
        if let image = np.thumbnailUIImage {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = Self.artwork(image)
        }
        // The artist may only be known now (resolved uploader).
        nowPlayingInfo[MPMediaItemPropertyArtist] = np.displayArtist
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    /// Full-resolution cover, scaled to whatever size the system asks for
    /// (lock screen, Control Center, CarPlay, AirPlay receivers).
    nonisolated static func artwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { requested in
            guard requested.width > 0, requested.height > 0,
                  requested.width < image.size.width || requested.height < image.size.height else { return image }
            return image.preparingThumbnail(of: requested) ?? image
        }
    }

    /// Like / shuffle / repeat state shown by the system controls.
    func syncRemoteCommandState() {
        let np = NowPlaying.shared
        let center = MPRemoteCommandCenter.shared()
        if let id = np.videoId {
            center.likeCommand.isActive = LikeStore.shared.isLiked(videoId: id)
        }
        center.changeShuffleModeCommand.currentShuffleType = np.isShuffleOn ? .items : .off
        center.changeRepeatModeCommand.currentRepeatType = np.isRepeatOn ? .one : .off
    }

    func updateNowPlayingProgress() {
        let props: (dur: Double, pos: Double)? = withMpv { mpv in
            var dur = Double(0)
            mpv_get_property(mpv, "duration", MPV_FORMAT_DOUBLE, &dur)
            var pos = Double(0)
            mpv_get_property(mpv, "time-pos", MPV_FORMAT_DOUBLE, &pos)
            return (dur, pos)
        }
        guard var props, props.dur > 0 else { return }
        let np = NowPlaying.shared

        if let seek = pendingSeek {
            if abs(props.pos - seek.target) > 1, Date() < seek.deadline {
                props.pos = seek.target
            } else {
                pendingSeek = nil
            }
        }

        var info = nowPlayingInfo
        info[MPMediaItemPropertyPlaybackDuration] = props.dur
        np.duration = props.dur
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = props.pos
        np.currentTime = props.pos
        info[MPNowPlayingInfoPropertyPlaybackRate] = np.isPlaying ? 1 : 0
        info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = np.queueIndex
        info[MPNowPlayingInfoPropertyPlaybackQueueCount] = np.queueSongs.count
        nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = np.isPlaying ? .playing : .paused
        syncRemoteCommandState()
    }
}

// MARK: - Remote commands

extension PlayerController {
    nonisolated static func registerRemoteControlSupport() {
        MainActor.assumeIsolated {
            UIApplication.shared.beginReceivingRemoteControlEvents()
            Log.player.info("REMOTE_COMMANDS launch-time beginReceivingRemoteControlEvents")
        }
    }

    fileprivate func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.removeTarget(nil)
        center.likeCommand.removeTarget(nil)
        center.changeShuffleModeCommand.removeTarget(nil)
        center.changeRepeatModeCommand.removeTarget(nil)

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            Log.player.info("REMOTE_COMMAND play fired")
            Task { @MainActor [weak self] in self?.setPaused(false) }
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            Log.player.info("REMOTE_COMMAND pause fired")
            Task { @MainActor [weak self] in self?.setPaused(true) }
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Log.player.info("REMOTE_COMMAND togglePlayPause fired")
            Task { @MainActor [weak self] in self?.togglePlayPause() }
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { _ in
            Log.player.info("REMOTE_COMMAND next fired")
            Task { @MainActor in NowPlaying.shared.playNext() }
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { _ in
            Log.player.info("REMOTE_COMMAND previous fired")
            Task { @MainActor in NowPlaying.shared.playPrevious() }
            return .success
        }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Log.player.info("REMOTE_COMMAND seek fired to=\(position)")
            Task { @MainActor [weak self] in
                self?.seek(to: position)
                self?.updateNowPlayingProgress()
            }
            return .success
        }

        // "Like" (lock screen / Control Center long-press menu).
        center.likeCommand.isEnabled = true
        center.likeCommand.localizedTitle = String(localized: "Like")
        center.likeCommand.localizedShortTitle = String(localized: "Like")
        center.likeCommand.addTarget { _ in
            Task { @MainActor in
                let np = NowPlaying.shared
                guard np.queueSongs.indices.contains(np.queueIndex) else { return }
                await LikeStore.shared.toggle(song: np.queueSongs[np.queueIndex])
                PlayerController.shared.syncRemoteCommandState()
            }
            return .success
        }

        center.changeShuffleModeCommand.isEnabled = true
        center.changeShuffleModeCommand.addTarget { event in
            guard let event = event as? MPChangeShuffleModeCommandEvent else { return .commandFailed }
            Task { @MainActor in
                let np = NowPlaying.shared
                let on = event.shuffleType != .off
                guard on != np.isShuffleOn else { return }
                np.isShuffleOn = on
                if on { np.shuffleQueue() } else { np.disableShuffle() }
                PlayerController.shared.syncRemoteCommandState()
            }
            return .success
        }

        center.changeRepeatModeCommand.isEnabled = true
        center.changeRepeatModeCommand.addTarget { event in
            guard let event = event as? MPChangeRepeatModeCommandEvent else { return .commandFailed }
            Task { @MainActor in
                NowPlaying.shared.isRepeatOn = event.repeatType != .off
                PlayerController.shared.syncRemoteCommandState()
            }
            return .success
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Keep the audio session alive while the screen is locked so
                // auto-advance can keep playing without user interaction.
                if self.desiredPlaying {
                    self.assertAudioSession()
                }
                self.setNowPlayingMetadata()
                self.updateNowPlayingProgress()
            }
            for delaySeconds in [0.6, 3] as [Double] {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
                    guard let self, UIApplication.shared.applicationState != .active else { return }
                    self.setNowPlayingMetadata()
                    self.updateNowPlayingProgress()
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.assertAudioSession()
                self.updateNowPlayingProgress()
            }
        }
    }
}

extension Array where Element == String {
    func withUnsafeCArg<T>(_ body: (UnsafeMutablePointer<UnsafePointer<CChar>?>?) -> T) -> T {
        let cstrings = map { strdup($0) }
        defer { cstrings.forEach { free($0) } }
        var ptrs = cstrings.map { UnsafePointer($0) } + [nil]
        return ptrs.withUnsafeMutableBufferPointer { buf in
            body(buf.baseAddress)
        }
    }
}

// MARK: - Crossfade A/B instances

extension PlayerController {
    var hasSpareInstance: Bool { mpvAccessQueue.sync { _spare != nil } }

    /// Creates the second instance (same configuration, own event loop).
    func ensureSpareInstance() {
        mpvAccessQueue.async { [weak self] in
            guard let self, self._spare == nil, self._mpv != nil else { return }
            guard let spare = Self.createConfiguredHandle() else { return }
            var zero = Double(0)
            mpv_set_property(spare, "volume", MPV_FORMAT_DOUBLE, &zero)
            self._spare = spare
            Log.player.info("CROSSFADE spare instance ready")
            let thread = Thread { [weak self] in self?.eventLoop(spare) }
            thread.name = "com.686udjie.PlayerController.eventLoop.spare"
            thread.start()
        }
    }

    /// Makes the spare the active instance; returns the previously active
    /// one (still playing the old song) for fading out.
    func swapToSpareInstance() -> OpaquePointer? {
        mpvAccessQueue.sync {
            guard let spare = _spare, let current = _mpv else { return nil }
            _mpv = spare
            _spare = current
            Log.player.info("CROSSFADE swapped active instance")
            return current
        }
    }

    func setVolume(_ value: Double, onInstance handle: OpaquePointer) {
        mpvAccessQueue.async {
            var v = max(0, value)
            mpv_set_property(handle, "volume", MPV_FORMAT_DOUBLE, &v)
        }
    }

    func stopInstance(_ handle: OpaquePointer) {
        mpvAccessQueue.async {
            _ = ["stop"].withUnsafeCArg { mpv_command(handle, $0) }
            var zero = Double(0)
            mpv_set_property(handle, "volume", MPV_FORMAT_DOUBLE, &zero)
        }
    }

    func playbackTimes(ofInstance handle: OpaquePointer) -> (position: Double, duration: Double) {
        mpvAccessQueue.sync {
            var pos = Double(0), dur = Double(0)
            mpv_get_property(handle, "time-pos", MPV_FORMAT_DOUBLE, &pos)
            mpv_get_property(handle, "duration", MPV_FORMAT_DOUBLE, &dur)
            return (pos, dur)
        }
    }
}
