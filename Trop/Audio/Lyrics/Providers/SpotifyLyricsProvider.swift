//
//  SpotifyLyricsProvider.swift
//  Resona
//
//  Spotify lyrics through the Spotify login that already exists for Canvas
//  (SpotifyAccountStore cookie → CanvasSpotifyToken web-player token).
//  Finds the track by title + artist + duration (±3 s), then loads its
//  color-lyrics (line-synced when Spotify has timing).
//
//  Never throws anything but "not found": without a connected account, on
//  expired tokens (one refresh + retry), rate limits (cool-down honouring
//  Retry-After) or any network error the manager simply uses other sources.
//

import Foundation

struct SpotifyLyricsProvider: LyricsProvider {
    let id = "spotify"
    let name = "Spotify"

    private static let search = "https://api.spotify.com/v1/search"
    private static let lyrics = "https://spclient.wg.spotify.com/color-lyrics/v2/track/"

    func fetch(query: LyricsQuery) async throws -> [LyricLine] {
        guard SpotifyAccountStore.shared.isLoggedIn,
              await SpotifyRateLimit.shared.isAllowed(),
              var token = await CanvasSpotifyToken.shared.accessToken() else { throw LyricsError.notFound }

        var trackId: String?
        switch await Self.findTrack(query: query, token: token) {
        case .ok(let id): trackId = id
        case .unauthorized:
            await CanvasSpotifyToken.shared.invalidate()
            guard let fresh = await CanvasSpotifyToken.shared.accessToken() else { throw LyricsError.notFound }
            token = fresh
            if case .ok(let id) = await Self.findTrack(query: query, token: token) { trackId = id }
        case .failed:
            break
        }
        guard let trackId else { throw LyricsError.notFound }

        var answer = await Self.loadLyrics(trackId: trackId, token: token)
        if case .unauthorized = answer {
            await CanvasSpotifyToken.shared.invalidate()
            if let fresh = await CanvasSpotifyToken.shared.accessToken() {
                answer = await Self.loadLyrics(trackId: trackId, token: fresh)
            }
        }
        guard case .ok(let lines) = answer, !lines.isEmpty else { throw LyricsError.notFound }
        return lines
    }

    // MARK: Requests

    private enum Answer<T> {
        case ok(T)
        case unauthorized
        case failed
    }

    private static func request(_ url: URL, token: String) async -> Answer<Any> {
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("WebPlayer", forHTTPHeaderField: "App-Platform")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(CanvasEndpoints.webUserAgent, forHTTPHeaderField: "User-Agent")
        if let clientToken = await CanvasSpotifyToken.shared.clientToken() {
            request.setValue(clientToken, forHTTPHeaderField: "Client-Token")
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return .failed }
        switch http.statusCode {
        case 200:
            guard let json = try? JSONSerialization.jsonObject(with: data) else { return .failed }
            return .ok(json)
        case 401:
            return .unauthorized
        case 429:
            let retryAfter = (http.value(forHTTPHeaderField: "Retry-After")).flatMap(Double.init) ?? 60
            await SpotifyRateLimit.shared.pause(for: retryAfter)
            return .failed
        default:
            return .failed
        }
    }

    /// Best track by title, main artist and duration (±3 s when known).
    private static func findTrack(query: LyricsQuery, token: String) async -> Answer<String> {
        var components = URLComponents(string: search)
        components?.queryItems = [
            URLQueryItem(name: "q", value: "track:\(query.title) artist:\(query.artist)"),
            URLQueryItem(name: "type", value: "track"),
            URLQueryItem(name: "limit", value: "10")
        ]
        guard let url = components?.url else { return .failed }
        switch await request(url, token: token) {
        case .unauthorized:
            return .unauthorized
        case .failed:
            return .failed
        case .ok(let json):
            guard let items = ((json as? [String: Any])?["tracks"] as? [String: Any])?["items"] as? [[String: Any]] else {
                return .failed
            }
            let wantTitle = CanvasText.normalized(query.title)
            let wantArtist = CanvasText.normalized(CanvasText.splitArtists(query.artist).first ?? query.artist)
            var best: (id: String, score: Int)?
            for item in items {
                guard let id = item["id"] as? String, let name = item["name"] as? String else { continue }
                let artists = ((item["artists"] as? [[String: Any]]) ?? []).compactMap { ($0["name"] as? String).map(CanvasText.normalized) }
                let title = CanvasText.normalized(name)
                var score = 0
                if title == wantTitle { score += 3 } else if title.contains(wantTitle) || wantTitle.contains(title) { score += 1 } else { continue }
                if artists.contains(wantArtist) { score += 3 } else if artists.contains(where: { $0.contains(wantArtist) || wantArtist.contains($0) }) { score += 1 } else { continue }
                if query.duration > 0, let ms = item["duration_ms"] as? Double {
                    guard abs(ms / 1000 - query.duration) <= 3 else { continue }
                    score += 2
                }
                if best == nil || score > best!.score { best = (id, score) }
            }
            return best.map { .ok($0.id) } ?? .failed
        }
    }

    /// {"lyrics":{"syncType":"LINE_SYNCED","lines":[{"startTimeMs":"1230","words":"…"}]}}
    private static func loadLyrics(trackId: String, token: String) async -> Answer<[LyricLine]> {
        var components = URLComponents(string: lyrics + trackId)
        components?.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "vocalRemoval", value: "false"),
            URLQueryItem(name: "market", value: "from_token")
        ]
        guard let url = components?.url else { return .failed }
        switch await request(url, token: token) {
        case .unauthorized:
            return .unauthorized
        case .failed:
            return .failed
        case .ok(let json):
            guard let body = (json as? [String: Any])?["lyrics"] as? [String: Any],
                  let rawLines = body["lines"] as? [[String: Any]] else { return .failed }
            let synced = (body["syncType"] as? String) == "LINE_SYNCED"
            let lines = rawLines.compactMap { raw -> LyricLine? in
                guard let text = (raw["words"] as? String)?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
                let ms = (raw["startTimeMs"] as? String).flatMap(Double.init) ?? (raw["startTimeMs"] as? Double)
                return LyricLine(text: text, startTime: synced ? ms.map { $0 / 1000 } : nil)
            }
            return .ok(lines)
        }
    }
}

/// Cool-down after HTTP 429 so Spotify isn't hammered while rate-limited.
actor SpotifyRateLimit {
    static let shared = SpotifyRateLimit()
    private var until = Date.distantPast

    func isAllowed() -> Bool { Date() >= until }

    func pause(for seconds: TimeInterval) {
        until = Date().addingTimeInterval(min(max(seconds, 5), 600))
    }
}
