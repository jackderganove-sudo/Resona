//
//  LyricsAccounts.swift
//  Resona
//
//  Lyrics sources with a free account of the user's own:
//  • Deezer — the `arl` session cookie (from the login web view, or pasted).
//    It gives full access to the Deezer account: kept in the Keychain only,
//    never logged, removed with "Sign out".
//  • Musixmatch — the user's own desktop user token (better hit rate and
//    limits than the anonymous guest token). Keychain only.
//  Without a login both sources are skipped silently. When a stored
//  credential stops working the account is flagged "Please sign in again".
//

import Foundation
import Observation

enum LyricsAccount: String, CaseIterable, Sendable {
    case deezer
    case musixmatch
}

/// Keychain + status. Secrets are read from any thread by the providers.
final class LyricsAccountSecrets: @unchecked Sendable {
    static let shared = LyricsAccountSecrets()
    private let store = SecureStore(service: "dev.jackderganove.resona.lyrics-accounts")
    private let lock = NSLock()
    private var cache: [LyricsAccount: String] = [:]

    func secret(_ account: LyricsAccount) -> String? {
        lock.withLock {
            if let cached = cache[account] { return cached.isEmpty ? nil : cached }
            let value = (try? store.load(for: account.rawValue)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
            cache[account] = value
            return value.isEmpty ? nil : value
        }
    }

    func save(_ value: String, for account: LyricsAccount) {
        lock.withLock {
            if let data = value.data(using: .utf8) { try? store.save(data, for: account.rawValue) }
            cache[account] = value
        }
    }

    func delete(_ account: LyricsAccount) {
        lock.withLock {
            try? store.delete(for: account.rawValue)
            cache[account] = ""
        }
    }
}

/// UI state per account (name shown, expired flag) — no secrets here.
@MainActor
@Observable
final class LyricsAccountStatus {
    static let shared = LyricsAccountStatus()

    private(set) var userNames: [LyricsAccount: String] = [:]
    private(set) var expired: Set<LyricsAccount> = []

    private init() {
        for account in LyricsAccount.allCases {
            userNames[account] = UserDefaults.standard.string(forKey: Self.nameKey(account))
            if UserDefaults.standard.bool(forKey: Self.expiredKey(account)) { expired.insert(account) }
        }
    }

    private static func nameKey(_ account: LyricsAccount) -> String { "resona.lyricsAccount.\(account.rawValue).name" }
    private static func expiredKey(_ account: LyricsAccount) -> String { "resona.lyricsAccount.\(account.rawValue).expired" }

    func isSignedIn(_ account: LyricsAccount) -> Bool { LyricsAccountSecrets.shared.secret(account) != nil }

    func signedIn(_ account: LyricsAccount, secret: String, userName: String) {
        LyricsAccountSecrets.shared.save(secret, for: account)
        userNames[account] = userName
        expired.remove(account)
        UserDefaults.standard.set(userName, forKey: Self.nameKey(account))
        UserDefaults.standard.set(false, forKey: Self.expiredKey(account))
        Log.player.info("LYRICS account \(account.rawValue): signed in")
    }

    func signOut(_ account: LyricsAccount) {
        LyricsAccountSecrets.shared.delete(account)
        userNames[account] = nil
        expired.remove(account)
        UserDefaults.standard.removeObject(forKey: Self.nameKey(account))
        UserDefaults.standard.set(false, forKey: Self.expiredKey(account))
        Log.player.info("LYRICS account \(account.rawValue): signed out")
    }

    /// Called by a provider when the stored credential is rejected.
    nonisolated static func markExpired(_ account: LyricsAccount) {
        Task { @MainActor in
            guard !shared.expired.contains(account) else { return }
            shared.expired.insert(account)
            UserDefaults.standard.set(true, forKey: expiredKey(account))
            Log.player.error("LYRICS account \(account.rawValue): credential rejected — sign in again")
        }
    }
}

// MARK: - Deezer

enum DeezerSession {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cachedJWT: (token: String, until: Date)?

    /// User name for an ARL (nil = not a valid login).
    static func userName(arl: String) async -> String? {
        guard let url = URL(string: "https://www.deezer.com/ajax/gw-light.php?method=deezer.getUserData&input=3&api_version=1.0&api_token=") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("arl=\(arl)", forHTTPHeaderField: "Cookie")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let user = (json["results"] as? [String: Any])?["USER"] as? [String: Any] else { return nil }
        let id = (user["USER_ID"] as? NSNumber)?.intValue ?? Int(user["USER_ID"] as? String ?? "") ?? 0
        guard id != 0 else { return nil }
        return (user["BLOG_NAME"] as? String) ?? String(id)
    }

    /// Bearer token for pipe.deezer.com (cached ~10 min).
    static func jwt(arl: String, forceNew: Bool = false) async throws -> String {
        if !forceNew, let cached = lock.withLock({ cachedJWT }), cached.until > Date() { return cached.token }
        guard let url = URL(string: "https://auth.deezer.com/login/arl?jo=p&rto=c&i=c") else { throw LyricsError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("arl=\(arl)", forHTTPHeaderField: "Cookie")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["jwt"] as? String, !token.isEmpty else {
            LyricsAccountStatus.markExpired(.deezer)
            throw LyricsError.notFound
        }
        lock.withLock { cachedJWT = (token, Date().addingTimeInterval(600)) }
        return token
    }

    static func resetJWT() { lock.withLock { cachedJWT = nil } }
}

struct DeezerLyricsProvider: LyricsProvider {
    let id = "deezer"
    let name = "Deezer"

    func fetch(query: LyricsQuery) async throws -> [LyricLine] {
        guard let best = try await search(query: query).first else { throw LyricsError.notFound }
        return best.lines
    }

    func search(query: LyricsQuery) async throws -> [LyricsCandidate] {
        // No login: skipped silently.
        guard let arl = LyricsAccountSecrets.shared.secret(.deezer) else { throw LyricsError.notFound }
        let tracks = try await Self.searchTracks(title: query.title, artist: query.artist)
        let ordered = query.duration > 0
            ? tracks.sorted { abs($0.duration - query.duration) < abs($1.duration - query.duration) }
            : tracks
        var results: [LyricsCandidate] = []
        for track in ordered.prefix(2) {
            guard let lines = try? await Self.lyrics(trackId: track.id, arl: arl), !lines.isEmpty else { continue }
            results.append(LyricsCandidate(lines: lines, title: track.title, artist: track.artist, duration: track.duration))
        }
        guard !results.isEmpty else { throw LyricsError.notFound }
        return results
    }

    struct Track: Equatable { let id: String; let title: String; let artist: String; let duration: Double }

    /// Public catalogue search (no login needed).
    static func searchTracks(title: String, artist: String) async throws -> [Track] {
        var components = URLComponents(string: "https://api.deezer.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: "artist:\"\(artist)\" track:\"\(title)\""),
                                  URLQueryItem(name: "limit", value: "5")]
        guard let url = components?.url else { throw LyricsError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        return parseSearch(try await LyricsHTTP.getJSON(request))
    }

    static func parseSearch(_ json: [String: Any]) -> [Track] {
        (json["data"] as? [[String: Any]] ?? []).compactMap { item in
            guard let id = (item["id"] as? NSNumber)?.stringValue, let title = item["title"] as? String else { return nil }
            return Track(id: id, title: title, artist: (item["artist"] as? [String: Any])?["name"] as? String ?? "",
                         duration: (item["duration"] as? NSNumber)?.doubleValue ?? 0)
        }
    }

    static let lyricsQuery = """
    query GetLyrics($trackId: String!) {
      track(trackId: $trackId) {
        lyrics {
          text
          synchronizedWordByWordLines { start end words { start end word } }
          synchronizedLines { lrcTimestamp line milliseconds duration }
        }
      }
    }
    """

    static func lyrics(trackId: String, arl: String) async throws -> [LyricLine] {
        for attempt in 0..<2 {
            let token = try await DeezerSession.jwt(arl: arl, forceNew: attempt > 0)
            guard let url = URL(string: "https://pipe.deezer.com/api") else { throw LyricsError.invalidURL }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 10
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "operationName": "GetLyrics", "variables": ["trackId": trackId], "query": lyricsQuery
            ])
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw LyricsError.decodingFailed }
            // Expired bearer: renew once.
            let errors = (json["errors"] as? [[String: Any]] ?? []).compactMap { $0["type"] as? String ?? $0["message"] as? String }
            if status == 401 || errors.contains(where: { $0.localizedCaseInsensitiveContains("expired") || $0.localizedCaseInsensitiveContains("jwt") }) {
                DeezerSession.resetJWT()
                if attempt == 0 { continue }
                LyricsAccountStatus.markExpired(.deezer)
                throw LyricsError.notFound
            }
            return parseLyrics(json)
        }
        throw LyricsError.notFound
    }

    /// Word-by-word lines (ms) if present, otherwise synchronized lines,
    /// otherwise the plain text.
    static func parseLyrics(_ json: [String: Any]) -> [LyricLine] {
        guard let lyrics = ((json["data"] as? [String: Any])?["track"] as? [String: Any])?["lyrics"] as? [String: Any] else { return [] }
        func ms(_ any: Any?) -> Double? { (any as? NSNumber)?.doubleValue.map { $0 / 1000 } }
        if let wordLines = lyrics["synchronizedWordByWordLines"] as? [[String: Any]], !wordLines.isEmpty {
            let lines: [LyricLine] = wordLines.compactMap { line in
                let words = (line["words"] as? [[String: Any]] ?? []).compactMap { word -> LyricWord? in
                    guard let text = word["word"] as? String, let start = ms(word["start"]) else { return nil }
                    return LyricWord(text: text, start: start, end: ms(word["end"]) ?? start + 0.3)
                }
                guard let start = ms(line["start"]) ?? words.first?.start else { return nil }
                // Words come without separating spaces: add them between words.
                let spaced = words.enumerated().map { index, word in
                    let needsSpace = index < words.count - 1 && !word.text.hasSuffix(" ")
                    return LyricWord(text: word.text + (needsSpace ? " " : ""), start: word.start, end: word.end)
                }
                let text = spaced.map(\.text).joined().trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { return nil }
                return LyricLine(text: text, startTime: start, words: spaced.count > 1 ? spaced : nil)
            }
            if !lines.isEmpty { return lines }
        }
        if let synced = lyrics["synchronizedLines"] as? [[String: Any]], !synced.isEmpty {
            let lines: [LyricLine] = synced.compactMap { line in
                guard let text = line["line"] as? String, let start = ms(line["milliseconds"]) else { return nil }
                return LyricLine(text: text, startTime: start)
            }
            if !lines.isEmpty { return lines }
        }
        if let text = lyrics["text"] as? String { return LyricsText.plainLines(text) }
        return []
    }
}

// MARK: - Musixmatch (own user token)

enum MusixmatchAccount {
    static let appId = "web-desktop-app-v1.0"

    /// User name for a desktop user token (nil = token not valid / not
    /// logged in).
    static func userName(token: String) async -> String? {
        var components = URLComponents(string: "https://apic-desktop.musixmatch.com/ws/1.1/user.get")
        components?.queryItems = [URLQueryItem(name: "app_id", value: appId), URLQueryItem(name: "usertoken", value: token),
                                  URLQueryItem(name: "format", value: "json")]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("AWSELBCORS=0; AWSELB=0", forHTTPHeaderField: "Cookie")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              ((message["header"] as? [String: Any])?["status_code"] as? NSNumber)?.intValue == 200,
              let user = ((message["body"] as? [String: Any])?["user"] as? [String: Any]) else { return nil }
        let name = (user["user_name"] as? String) ?? (user["user_nickname"] as? String) ?? ""
        let isAnonymous = (user["is_anonymous"] as? Bool) ?? ((user["user_type"] as? String) == "anonymous")
        guard !isAnonymous else { return nil }
        return name.isEmpty ? "Musixmatch" : name
    }
}
