//
//  SpotifySavedTracks.swift
//  Resona
//
//  "Saved tracks" (round 10, after ArchiveTune 15's Spotify liked songs):
//  the user's own Spotify "Liked Songs", read with the Spotify login Resona
//  already has for Canvas (own sp_dc cookie → web token), via Spotify's
//  GraphQL `fetchLibraryTracks` (persisted-query hash as used by
//  ArchiveTune). Each song is matched to YouTube Music by search when it
//  is played; matches are cached.
//

import Foundation
import SwiftUI
import SwiftyTube

struct SpotifySavedTrack: Identifiable, Hashable, Sendable {
    var id: String          // spotify:track:…
    var title: String
    var artists: [String]
    var album: String?
    var coverURL: String?
    var durationMs: Int

    var artistLine: String { artists.joined(separator: ", ") }
}

enum SpotifyLibraryAPI {
    static let endpoint = "https://api-partner.spotify.com/pathfinder/v2/query"
    static let fetchLibraryTracksHash = "087278b20b743578a6262c2b0b4bcd20d879c503cc359a2285baf083ef944240"

    struct Page: Sendable {
        var tracks: [SpotifySavedTrack]
        var total: Int
    }

    enum Failure: LocalizedError {
        case notConnected, http(Int), badResponse

        var errorDescription: String? {
            switch self {
            case .notConnected: return String(localized: "Connect Spotify first (Settings → Canvas).")
            case .http(let code): return String(format: String(localized: "Spotify answered with HTTP %d."), code)
            case .badResponse: return String(localized: "Spotify sent an unexpected answer.")
            }
        }
    }

    static func fetchPage(offset: Int, limit: Int) async throws -> Page {
        guard let token = await CanvasSpotifyToken.shared.accessToken() else { throw Failure.notConnected }
        let clientToken = await CanvasSpotifyToken.shared.clientToken()
        guard let url = URL(string: endpoint) else { throw Failure.badResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let clientToken { request.setValue(clientToken, forHTTPHeaderField: "Client-Token") }
        request.setValue("WebPlayer", forHTTPHeaderField: "App-Platform")
        request.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue(CanvasEndpoints.webUserAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "variables": ["offset": offset, "limit": limit],
            "operationName": "fetchLibraryTracks",
            "extensions": ["persistedQuery": ["version": 1, "sha256Hash": fetchLibraryTracksHash]]
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { await CanvasSpotifyToken.shared.invalidate() }
        guard (200...299).contains(status) else { throw Failure.http(status) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let page = parse(json) else { throw Failure.badResponse }
        return page
    }

    /// data.me.library.tracks { totalCount, items[].track { _uri, data { name,
    /// artists.items[].profile.name, albumOfTrack { name, coverArt.sources },
    /// duration.totalMilliseconds } } }. Local files are skipped.
    static func parse(_ json: [String: Any]) -> Page? {
        guard let tracks = (((json["data"] as? [String: Any])?["me"] as? [String: Any])?["library"] as? [String: Any])?["tracks"] as? [String: Any]
        else { return nil }
        let items = tracks["items"] as? [[String: Any]] ?? []
        let parsed: [SpotifySavedTrack] = items.compactMap { item in
            guard let wrapper = item["track"] as? [String: Any], let data = wrapper["data"] as? [String: Any] else { return nil }
            let uri = (wrapper["_uri"] as? String) ?? (wrapper["uri"] as? String) ?? (data["uri"] as? String) ?? ""
            guard !uri.isEmpty, !uri.hasPrefix("spotify:local:"), let name = data["name"] as? String, !name.isEmpty else { return nil }
            let artists = ((data["artists"] as? [String: Any])?["items"] as? [[String: Any]] ?? [])
                .compactMap { ($0["profile"] as? [String: Any])?["name"] as? String }
            let album = data["albumOfTrack"] as? [String: Any]
            let sources = ((album?["coverArt"] as? [String: Any])?["sources"] as? [[String: Any]]) ?? []
            // Largest cover up to 640 px.
            let cover = sources
                .sorted { ($0["width"] as? Int ?? 0) < ($1["width"] as? Int ?? 0) }
                .last { ($0["width"] as? Int ?? 0) <= 640 }?["url"] as? String ?? sources.first?["url"] as? String
            let duration = ((data["duration"] as? [String: Any])?["totalMilliseconds"] as? Int) ?? 0
            return SpotifySavedTrack(id: uri, title: name, artists: artists, album: album?["name"] as? String,
                                     coverURL: cover, durationMs: duration)
        }
        return Page(tracks: parsed, total: tracks["totalCount"] as? Int ?? parsed.count)
    }
}

/// Spotify track → YouTube Music song (search, cached for the session).
actor SpotifyMatcher {
    static let shared = SpotifyMatcher()
    private var cache: [String: SongItem] = [:]
    /// YouTube Music search filter "Songs".
    static let songsFilter = "EgWKAQIIAWoMEA4QChADEAQQCRAF"

    func match(_ track: SpotifySavedTrack) async -> SongItem? {
        if let cached = cache[track.id] { return cached }
        let query = "\(track.artists.first ?? "") \(track.title)"
        for params in [Self.songsFilter, nil] as [String?] {
            guard let json = try? await InnerTubeClient.tropShared.search(query: query, params: params, client: .webRemix) else { continue }
            let songs = SearchParser.parseSearchResults(from: json).flatMap(\.items).compactMap { item -> SongItem? in
                if case .song(let song) = item { return song }
                return nil
            }
            if let best = Self.best(songs, for: track) {
                cache[track.id] = best
                return best
            }
        }
        return nil
    }

    /// First result whose duration is within 15 s (when both are known),
    /// else the first result.
    static func best(_ songs: [SongItem], for track: SpotifySavedTrack) -> SongItem? {
        let seconds = track.durationMs / 1000
        if seconds > 0, let close = songs.first(where: { $0.duration > 0 && abs($0.duration - seconds) <= 15 }) {
            return close
        }
        return songs.first
    }
}

@MainActor
@Observable
final class SpotifySavedTracksStore {
    static let shared = SpotifySavedTracksStore()
    private(set) var tracks: [SpotifySavedTrack] = []
    private(set) var total = 0
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var resolvingId: String?

    var isConnected: Bool { !(SpotifyAccountStore.shared.cookie() ?? "").isEmpty }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        var collected: [SpotifySavedTrack] = []
        do {
            var offset = 0
            repeat {
                let page = try await SpotifyLibraryAPI.fetchPage(offset: offset, limit: 50)
                collected += page.tracks
                total = page.total
                offset += 50
                if page.tracks.isEmpty { break }
            } while offset < total && offset < 3000
            tracks = collected
            Log.explore.info("Spotify saved tracks: \(collected.count)/\(self.total)")
        } catch {
            if !collected.isEmpty { tracks = collected }
            self.error = error.localizedDescription
        }
    }

    /// Plays from `index`: matches the tapped song first, then the next ones
    /// in the background and appends them to the queue.
    func play(from index: Int, shuffled: Bool = false) {
        guard tracks.indices.contains(index) else { return }
        var order = Array(tracks[index...]) + Array(tracks[..<index])
        if shuffled { order.shuffle() }
        let first = order[0]
        resolvingId = first.id
        Task {
            defer { resolvingId = nil }
            guard let song = await SpotifyMatcher.shared.match(first) else {
                error = String(format: String(localized: "“%@” wasn't found on YouTube Music."), first.title)
                return
            }
            PlaybackQueue.play([song], log: Log.explore, context: "Spotify saved tracks")
            let videoId = song.videoId
            for track in order.dropFirst().prefix(40) {
                guard NowPlaying.shared.queueSongs.first?.videoId == videoId else { return }  // user played something else
                if let next = await SpotifyMatcher.shared.match(track),
                   !NowPlaying.shared.queueSongs.contains(where: { $0.videoId == next.videoId }) {
                    NowPlaying.shared.queueSongs.append(next)
                    NowPlaying.shared.persistQueueState()
                }
            }
        }
    }
}

struct SpotifySavedTracksView: View {
    @Environment(\.m3) private var m3
    private let store = SpotifySavedTracksStore.shared

    var body: some View {
        List {
            if !store.isConnected {
                message(icon: "link", title: "Spotify isn't connected",
                        text: "Sign in to Spotify under Settings → Canvas. Resona reads your liked songs with that login and plays them from YouTube Music.")
            } else if store.tracks.isEmpty && !store.isLoading {
                message(icon: "heart", title: "No saved tracks", text: store.error ?? "Your Spotify “Liked Songs” appear here.")
            } else {
                HStack(spacing: 12) {
                    Button { store.play(from: 0) } label: { Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.m3Filled)
                    Button { store.play(from: 0, shuffled: true) } label: { Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity) }
                        .buttonStyle(.m3Tonal)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                if let error = store.error {
                    Text(error).font(.m3(.bodySmall)).foregroundStyle(m3.error).listRowBackground(Color.clear)
                }
                ForEach(Array(store.tracks.enumerated()), id: \.element.id) { index, track in
                    Button { store.play(from: index) } label: {
                        HStack(spacing: 12) {
                            AsyncImageView(url: track.coverURL)
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title).font(.m3(.bodyLarge)).foregroundStyle(m3.onSurface).lineLimit(1)
                                Text(track.artistLine).font(.m3(.bodySmall)).foregroundStyle(m3.onSurfaceVariant).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            if store.resolvingId == track.id {
                                ProgressView()
                            } else {
                                Text(PlaylistCSV.duration(track.durationMs / 1000))
                                    .font(.m3(.bodySmall).monospacedDigit())
                                    .foregroundStyle(m3.onSurfaceVariant)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay { if store.isLoading && store.tracks.isEmpty { ProgressView() } }
        .refreshable { await store.load() }
        .task { if store.tracks.isEmpty, store.isConnected { await store.load() } }
        .miniPlayerTracksScroll()
        .navigationTitle("Saved tracks")
        .accessibilityIdentifier("spotifySavedTracks")
    }

    private func message(icon: String, title: LocalizedStringKey, text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 40, weight: .light)).foregroundStyle(m3.primary)
            Text(title).font(.m3(.titleMedium))
            Text(LocalizedStringKey(text)).font(.m3(.bodyMedium)).foregroundStyle(m3.onSurfaceVariant).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}
