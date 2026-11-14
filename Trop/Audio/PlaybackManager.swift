//
//  PlaybackManager.swift
//  Trop
//
//  Created by 686udjie on 29/06/2026.
//

import Foundation

/// Resolves streams and hands off to PlayerController, trying the client fallback chain.
actor PlaybackManager {
    static let shared = PlaybackManager()

    private var inflightResolutions: [String: Task<PlaybackResult, Error>] = [:]

    private func resolutionKey(videoId: String, forDownload: Bool) -> String {
        forDownload ? "\(videoId):download" : videoId
    }

    private init() {}

    /// Resolve a video and start playback. Returns the result used, or throws.
    @discardableResult
    func resolveAndPlay(videoId: String) async throws -> PlaybackResult {
        await MainActor.run { SponsorBlockIntegration.shared.warm(for: videoId) }
        var local = await DownloadManager.shared.localURL(for: videoId)
        #if DEBUG
        // UI tests in the simulator: YouTube answers CI runner IPs with a bot
        // check, so every song plays a local test tone (metadata, covers and
        // lyrics stay real). Never compiled into release builds.
        if local == nil, TestMode.isUITest { local = TestMode.uiTestToneURL }
        #endif
        if let localPath = local {
            let song = await MainActor.run { NowPlaying.shared.queueSongs.first { $0.videoId == videoId } }
            let artists = song?.artists ?? []
            let resolvedArtist = await MainActor.run { ArtistNameResolver.shared.cached(videoId) }
            let creditedArtist = song?.artists.map(\.name).joined(separator: ", ") ?? ""
            await PlayerController.shared.play(
                url: localPath.absoluteString,
                title: song?.title,
                artist: creditedArtist.isEmpty ? resolvedArtist : creditedArtist,
                videoId: videoId,
                duration: song.map { TimeInterval($0.duration) },
                artists: artists,
                thumbnailUrl: song?.thumbnailUrl
            )
            await MainActor.run {
                NowPlaying.shared.updateVideoAvailability()
            }
            return PlaybackResult(
                streamUrl: localPath.absoluteString,
                itag: 0,
                mimeType: "audio/mp4",
                bitrate: 0,
                audioQuality: "local",
                videoId: videoId,
                title: song?.title,
                author: song?.artists.map(\.name).joined(separator: ", "),
                duration: song?.duration,
                expiresInSeconds: Int.max,
                clientName: "local",
                musicVideoType: nil,
                hasVideoContent: false,
                muxedStreamUrl: nil,
                loudnessDb: nil
            )
        }

        if let cached = await StreamCache.shared.get(videoId: videoId) {
            let queueSong = await queueSong(for: videoId)
            await PlayerController.shared.play(
                url: cached.streamUrl,
                title: cached.title,
                artist: cached.author,
                videoId: videoId,
                duration: cached.duration.flatMap { $0 > 0 ? TimeInterval($0) : nil },
                artists: queueSong?.artists ?? [],
                loudnessDb: cached.loudnessDb,
                thumbnailUrl: queueSong?.thumbnailUrl
            )
            await publishVideoAvailability(result: cached, videoId: videoId, rowType: queueSong?.musicVideoType)
            return cached
        }

        if let existing = inflightResolutions[videoId] {
            return try await existing.value
        }

        let task = Task { [self] in
            try await resolveAndPlayFromNetwork(videoId: videoId)
        }
        inflightResolutions[videoId] = task
        defer { clearInflight(key: videoId) }
        do {
            return try await task.value
        } catch {
            // Visible hint instead of a log line only.
            let title = await MainActor.run { NowPlaying.shared.queueSongs.first { $0.videoId == videoId }?.title }
            await MainActor.run { PlaybackErrorCenter.shared.report(error, videoId: videoId, title: title) }
            throw error
        }
    }

    /// Runs the client fallback chain for playback. Only called once per
    /// videoId by `resolveAndPlay`, which owns the in-flight dedup entry.
    private func resolveAndPlayFromNetwork(videoId: String) async throws -> PlaybackResult {
        // Playback first: downloads wait while this resolves.
        await PlaybackPriorityGate.shared.begin()
        let result: PlaybackResult
        do {
            result = try await resolvePlaybackStream(videoId: videoId)
            await PlaybackPriorityGate.shared.end()
        } catch {
            await PlaybackPriorityGate.shared.end()
            throw error
        }
        await playNetworkResult(result, videoId: videoId)
        return result
    }

    /// Client for each video's current stream, and when it started (player failures).
    private var streamClient: [String: (client: String, started: Date)] = [:]

    /// One client after the other (`StreamClientFallback`), every attempt logged.
    /// All failed: an expired cached URL is still tried, as before.
    private func resolvePlaybackStream(videoId: String) async throws -> PlaybackResult {
        var options = StreamResolveOptions.default
        options.audioQuality = SettingsStore.shared.audioQuality
        let signedIn = await CookieStore().isLoggedIn()
        let chain = ResonaStreamChain.playback.filter { signedIn || $0.client.clientName != "TVHTML5" }
        do {
            let result = try await StreamClientFallback.run(
                videoId: videoId,
                chain: chain,
                isBlocked: { await StreamClientBlocklist.shared.isBlocked(videoId: videoId, client: $0) },
                resolve: { entry in
                    let request = StreamResolveRequest(
                        videoId: videoId,
                        chain: [FallbackClient(client: entry.client, skipValidation: true)],
                        options: options,
                        policy: FallbackPolicy(useCache: false, storeInCache: false, validateStreams: false,
                                               expiredCacheFallback: false, preferAAC: false)
                    )
                    return try await StreamFallback.resolveFirstValid(
                        request, using: InnerTubeClient.tropShared, providers: .tropLive
                    )
                },
                probe: { url in
                    let status = await StreamClientFallback.probeStatus(url)
                    if status == 403 { await StreamResolveProviders.tropLive.onStreamRejection?() }
                    return status
                },
                log: { await PlaybackErrorLog.shared.record($0) },
                block: { await StreamClientBlocklist.shared.block(videoId: videoId, client: $0) }
            )
            await StreamCache.shared.set(videoId: videoId, result: result)
            streamClient[videoId] = (ResonaStreamChain.key(for: result.clientName), Date())
            return result
        } catch let failure as StreamClientFallback.Failure {
            if let expired = await StreamCache.shared.getExpired(videoId: videoId) {
                await PlaybackErrorLog.shared.record(PlaybackLogEntry(
                    time: Date(), videoId: videoId, client: expired.clientName, stage: .success,
                    httpStatus: nil, message: "all clients failed, trying the expired cached stream"))
                streamClient[videoId] = (ResonaStreamChain.key(for: expired.clientName), Date())
                return expired
            }
            throw failure.lastError ?? failure
        }
    }

    /// The player could not load or lost the stream. Early (≤ 15 s) or with an
    /// HTTP error the client is skipped for this song; the next resolve moves on.
    /// Returns false when the same song failed late without an HTTP error
    /// less than 30 s ago (caller stops instead of looping).
    func playerFailed(videoId: String, httpStatus: Int?, detail: String) async -> Bool {
        let current = streamClient[videoId]
        let client = current?.client ?? "unknown"
        let early = current.map { Date().timeIntervalSince($0.started) <= 15 } ?? true
        let rejected = httpStatus.map { [403, 404, 410, 416].contains($0) } ?? false
        await PlaybackErrorLog.shared.record(PlaybackLogEntry(
            time: Date(), videoId: videoId, client: client, stage: .player, httpStatus: httpStatus, message: detail))
        await StreamCache.shared.remove(videoId: videoId)
        if early || rejected {
            await StreamClientBlocklist.shared.block(videoId: videoId, client: client)
            return true
        }
        if let last = lateFailureAt[videoId], Date().timeIntervalSince(last) < 30 { return false }
        lateFailureAt[videoId] = Date()
        return true
    }

    private var lateFailureAt: [String: Date] = [:]

    /// "Retry" in the error banner: every client again, fresh resolve.
    func resetFailures(videoId: String) async {
        await StreamClientBlocklist.shared.reset(videoId: videoId)
        await StreamCache.shared.remove(videoId: videoId)
        lateFailureAt.removeValue(forKey: videoId)
    }

    private func playNetworkResult(_ result: PlaybackResult, videoId: String) async {
        let queueSong = await queueSong(for: videoId)
        await PlayerController.shared.play(
            url: result.streamUrl,
            title: result.title,
            artist: result.author,
            videoId: videoId,
            duration: result.duration.flatMap { $0 > 0 ? TimeInterval($0) : nil },
            artists: queueSong?.artists ?? [],
            loudnessDb: result.loudnessDb,
            thumbnailUrl: queueSong?.thumbnailUrl
        )
        await publishVideoAvailability(result: result, videoId: videoId, rowType: queueSong?.musicVideoType)
    }

    private func clearInflight(key: String) {
        inflightResolutions.removeValue(forKey: key)
    }

    /// Queue song for resolve-time metadata (artists, artwork, video type).
    /// One MainActor hop instead of one per field, so the snapshot is
    /// consistent even if the queue changes mid-resolve.
    private func queueSong(for videoId: String) async -> SongItem? {
        await MainActor.run {
            NowPlaying.shared.queueSongs.first { $0.videoId == videoId }
        }
    }

    /// Publishes video availability for a resolve result. The row type wins
    /// (resolve responses often omit it); unknown rows fall back to an
    /// authoritative lookup inside the shared availability check.
    private func publishVideoAvailability(result: PlaybackResult, videoId: String, rowType: String?) async {
        let type = result.musicVideoType ?? rowType
        let hasVideo = await VideoAvailability.shared.hasVideo(
            videoId: videoId, rowType: rowType, result: result, using: InnerTubeClient.tropShared
        )
        await MainActor.run {
            NowPlaying.shared.updateVideoAvailability(musicVideoType: type, hasVideo: hasVideo)
        }
    }

    /// Resolves a playable video stream URL for video mode. Prefers a muxed
    /// (audio+video) stream; when the video offers none, falls back to an EDL
    /// that combines a DASH video-only stream with a separate audio stream.
    func resolveVideoStream(videoId: String) async throws -> String {
        var request = StreamResolveRequest(videoId: videoId)
        request.options.audioQuality = SettingsStore.shared.audioQuality
        switch try await StreamFallback.resolveVideo(
            request,
            using: InnerTubeClient.tropShared,
            providers: .tropLive
        ) {
        case .muxed(let url):
            return url
        case .split(let videoURL, let audioURL, let duration):
            return StreamFallback.combineVideoAndAudio(
                videoURL: videoURL,
                audioURL: audioURL,
                duration: duration
            )
        case .hls(let url):
            return url
        }
    }

    /// Returns the muxed/video stream URL for video mode, preferring the cached one.
    func resolveMuxedURL(videoId: String) async throws -> String {
        if let cached = await StreamCache.shared.get(videoId: videoId),
           let muxed = cached.muxedStreamUrl {
            return muxed
        }
        return try await resolveVideoStream(videoId: videoId)
    }

    func resolveVideoOnlyURL(videoId: String) async throws -> String {
        let request = StreamResolveRequest(videoId: videoId)
        switch try await StreamFallback.resolveVideo(
            request,
            using: InnerTubeClient.tropShared,
            providers: .tropLive
        ) {
        case .muxed(let url):
            return url
        case .split(let videoURL, _, _):
            return videoURL
        case .hls(let url):
            return url
        }
    }

    /// Stable per-launch session id for PoToken minting.
    static let sessionId: String = UUID().uuidString
    /// Resolve a video without playing. Useful for previews / testing.
    func resolve(videoId: String, preferredFormat: Format? = nil, forDownload: Bool = false) async throws -> PlaybackResult {
        if !forDownload, let cached = await StreamCache.shared.get(videoId: videoId) {
            return cached
        }

        let key = resolutionKey(videoId: videoId, forDownload: forDownload)
        if let existing = inflightResolutions[key] {
            return try await existing.value
        }

        let task = Task { [self] in
            try await resolveFromNetwork(videoId: videoId, preferredFormat: preferredFormat, forDownload: forDownload)
        }
        inflightResolutions[key] = task
        defer { clearInflight(key: key) }
        return try await task.value
    }

    private func resolveFromNetwork(videoId: String, preferredFormat: Format?, forDownload: Bool) async throws -> PlaybackResult {
        if forDownload { await PlaybackPriorityGate.shared.waitForPlayback() }
        var request = forDownload ? StreamResolveRequest.download(videoId: videoId) : .playback(videoId: videoId)
        request.options.preferredFormat = preferredFormat
        request.options.audioQuality = SettingsStore.shared.audioQuality
        request.options.downloadQuality = SettingsStore.shared.downloadQuality
        return try await StreamFallback.resolveFirstValid(
            request,
            using: InnerTubeClient.tropShared,
            providers: .tropLive
        )
    }
}
