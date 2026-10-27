//
//  ExtraLyricsProviders.swift
//  Resona
//
//  Additional sources as in ArchiveTune (GPL-3.0, rukamori/lyrics):
//  BetterLyrics and YouLyPlus (word-synced TTML incl. background vocals),
//  Paxsenix (needs the user's own API key) and YouTube Music's own lyrics
//  tab (plain text, fallback).
//

import Foundation
import SwiftyTube

// MARK: - Shared helpers

enum LyricsRequest {
    static func url(_ base: String, _ items: [String: String?]) -> URL? {
        var components = URLComponents(string: base)
        components?.queryItems = items.compactMap { key, value in
            guard let value, !value.isEmpty else { return nil }
            return URLQueryItem(name: key, value: value)
        }
        return components?.url
    }

    /// Body of a 2xx response, nil otherwise (errors are never thrown).
    static func get(_ url: URL, headers: [String: String] = [:], timeout: TimeInterval = 8) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("Resona", forHTTPHeaderField: "User-Agent")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode,
              (200..<300).contains(status) else { return nil }
        return data
    }

    /// Raw TTML, or TTML wrapped in JSON ({"ttml": …}, {"lyrics": …}, …).
    static func ttml(from data: Data) -> String? {
        guard var text = String(data: data, encoding: .utf8) else { return nil }
        text = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}")))
        if text.hasPrefix("<") { return text }
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return findTTML(in: json, depth: 0)
    }

    private static func findTTML(in value: Any, depth: Int) -> String? {
        guard depth < 4 else { return nil }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("<"), trimmed.range(of: "<tt", options: .caseInsensitive) != nil { return trimmed }
            return nil
        }
        if let dict = value as? [String: Any] {
            for key in ["ttml", "lyrics", "data", "result", "response"] {
                if let nested = dict[key], let found = findTTML(in: nested, depth: depth + 1) { return found }
            }
        }
        return nil
    }

    /// Lyrics text from an arbitrary JSON payload (LRC or plain).
    static func lyricsText(in value: Any, depth: Int = 0) -> String? {
        guard depth < 4 else { return nil }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let dict = value as? [String: Any] {
            if dict["error"] != nil, dict["lyrics"] == nil { return nil }
            for key in ["syncedLyrics", "lrc", "lyrics", "content", "plainLyrics", "text", "lyric"] {
                if let nested = dict[key], let found = lyricsText(in: nested, depth: depth + 1) { return found }
            }
        }
        if let array = value as? [Any] {
            let parts = array.compactMap { lyricsText(in: $0, depth: depth + 1) }
            return parts.isEmpty ? nil : parts.joined(separator: "\n")
        }
        return nil
    }

    /// LRC/enhanced LRC when timestamps are present, plain lines otherwise.
    static func lines(fromText text: String) -> [LyricLine] {
        let synced = LyricsParsing.parseLrc(text)
        if synced.contains(where: { $0.startTime != nil }) { return synced }
        return LyricsText.plainLines(text)
    }
}

// MARK: - BetterLyrics

struct BetterLyricsProvider: LyricsProvider {
    let id = "betterlyrics"
    let name = "Better Lyrics"

    private let base = "https://lyrics-api.boidu.dev/"

    func fetch(query: LyricsQuery) async throws -> [LyricLine] {
        for path in ["getLyrics", "kugou/getLyrics"] {
            guard let url = LyricsRequest.url(base + path, [
                "s": query.title,
                "a": query.artist,
                "al": query.album,
                "d": query.durationSeconds > 0 ? String(query.durationSeconds) : nil
            ]) else { continue }
            guard let data = await LyricsRequest.get(url),
                  let ttml = LyricsRequest.ttml(from: data) else { continue }
            let lines = TTMLLyricsParser.parse(ttml)
            if !lines.isEmpty { return lines }
        }
        throw LyricsError.notFound
    }
}

// MARK: - YouLyPlus (lyricsplus mirrors)

struct YouLyPlusProvider: LyricsProvider {
    let id = "youlyplus"
    let name = "YouLyPlus"

    private let mirrors = [
        "https://lyricsplus.binimum.org/",
        "https://lyricsplus.prjktla.my.id/",
        "https://lyricsplus.prjktla.workers.dev/",
        "https://lyricsplus.atomix.one/",
        "https://lyricsplus-seven.vercel.app/"
    ]

    func fetch(query: LyricsQuery) async throws -> [LyricLine] {
        let params: [String: String?] = [
            "title": query.title,
            "artist": query.artist,
            "album": query.album,
            "duration": query.durationSeconds > 0 ? String(query.durationSeconds) : nil
        ]
        for mirror in mirrors {
            try Task.checkCancellation()
            // 1) TTML (word-synced)
            if let url = LyricsRequest.url(mirror + "v1/ttml/get", params),
               let data = await LyricsRequest.get(url, headers: ["Accept": "application/json"], timeout: 5),
               let ttml = LyricsRequest.ttml(from: data) {
                let lines = TTMLLyricsParser.parse(ttml)
                if !lines.isEmpty { return lines }
            }
            // 2) JSON lines with syllables
            if let url = LyricsRequest.url(mirror + "v2/lyrics/get", params),
               let data = await LyricsRequest.get(url, headers: ["Accept": "application/json"], timeout: 5),
               let lines = Self.parseJSONLines(data), !lines.isEmpty {
                return lines
            }
        }
        throw LyricsError.notFound
    }

    /// {"type":"Word"|"Line","lyrics":[{"time":ms,"text":…,"syllabus":[{"time":ms,"duration":ms,"text":…,"isBackground":…}]}]}
    static func parseJSONLines(_ data: Data) -> [LyricLine]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["lyrics"] as? [[String: Any]], !items.isEmpty else { return nil }
        let wordSynced = (json["type"] as? String)?.lowercased() == "word"
        func seconds(_ any: Any?) -> TimeInterval? { (any as? NSNumber).map { $0.doubleValue / 1000 } }
        return items.compactMap { item in
            let start = seconds(item["time"])
            let syllables = (item["syllabus"] as? [[String: Any]]) ?? []
            let main = syllables.filter { ($0["isBackground"] as? Bool) != true }
            let background = syllables.filter { ($0["isBackground"] as? Bool) == true }
                .compactMap { $0["text"] as? String }.joined()
                .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "()")))
            var words: [LyricWord]?
            if wordSynced, main.count > 1 {
                words = main.compactMap { s in
                    guard let text = s["text"] as? String, let t = seconds(s["time"]) else { return nil }
                    return LyricWord(text: text, start: t, end: t + (seconds(s["duration"]) ?? 0))
                }
            }
            let text = (words?.map(\.text).joined() ?? (item["text"] as? String) ?? "")
                .trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return nil }
            return LyricLine(text: text, startTime: start, words: words, backgroundText: background.isEmpty ? nil : background)
        }
    }
}

// MARK: - Paxsenix

/// Needs the user's own Paxsenix API key (Songtext settings); without one
/// the provider is skipped silently.
struct PaxsenixProvider: LyricsProvider {
    let id = "paxsenix"
    let name = "Paxsenix"

    static let apiKeyDefaultsKey = "resona.paxsenixApiKey"
    private let base = "https://api.paxsenix.org/"

    static var apiKey: String {
        (UserDefaults.standard.string(forKey: apiKeyDefaultsKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func fetch(query: LyricsQuery) async throws -> [LyricLine] {
        let key = Self.apiKey
        guard !key.isEmpty else { throw LyricsError.notFound }
        let headers = ["Authorization": "Bearer \(key)", "Accept": "application/json, text/plain, */*"]
        let requests: [(String, [String: String?])] = [
            ("lyrics/musixmatch", ["t": query.title, "a": query.artist, "d": String(query.durationSeconds)]),
            ("lyrics/lrcget", ["q": "\(query.title) \(query.artist)"])
        ]
        for (path, params) in requests {
            guard let url = LyricsRequest.url(base + path, params),
                  let data = await LyricsRequest.get(url, headers: headers) else { continue }
            if let lines = Self.parse(data), !lines.isEmpty { return lines }
        }
        throw LyricsError.notFound
    }

    /// Apple-Music style {"content":[{"timestamp":ms,"text":[{"text":…}]}]}
    /// or any JSON/plain payload containing LRC or plain lyrics.
    static func parse(_ data: Data) -> [LyricLine]? {
        let json = try? JSONSerialization.jsonObject(with: data)
        if let dict = json as? [String: Any], let content = dict["content"] as? [[String: Any]], !content.isEmpty {
            let lines = content.compactMap { item -> LyricLine? in
                let start = (item["timestamp"] as? NSNumber).map { $0.doubleValue / 1000 }
                let parts = (item["text"] as? [[String: Any]])?.compactMap { $0["text"] as? String } ?? []
                let text = parts.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
                return text.isEmpty ? nil : LyricLine(text: text, startTime: start)
            }
            if !lines.isEmpty { return lines }
        }
        let text = json.flatMap { LyricsRequest.lyricsText(in: $0) } ?? String(data: data, encoding: .utf8)
        guard let text, !text.isEmpty else { return nil }
        return LyricsRequest.lines(fromText: text)
    }
}

// MARK: - YouTube Music

/// The lyrics tab of YouTube Music itself (usually plain text) — fallback.
struct YouTubeMusicLyricsProvider: LyricsProvider {
    let id = "youtube"
    let name = "YouTube Music"

    func fetch(query: LyricsQuery) async throws -> [LyricLine] {
        guard let videoId = query.videoId else { throw LyricsError.notFound }
        let next = try await InnerTubeClient.tropShared.next(videoId: videoId)
        guard let browseId = Self.lyricsBrowseId(in: next) else { throw LyricsError.notFound }
        let page = try await InnerTubeClient.tropShared.browse(browseId: browseId)
        guard let text = Self.descriptionText(in: page), !text.isEmpty else { throw LyricsError.notFound }
        let lines = LyricsText.plainLines(text)
        guard !lines.isEmpty else { throw LyricsError.notFound }
        return lines
    }

    /// Tab whose browse endpoint has pageType MUSIC_PAGE_TYPE_TRACK_LYRICS.
    static func lyricsBrowseId(in value: Any) -> String? {
        if let dict = value as? [String: Any] {
            if let browse = dict["browseEndpoint"] as? [String: Any],
               let id = browse["browseId"] as? String,
               let config = (browse["browseEndpointContextSupportedConfigs"] as? [String: Any])?["browseEndpointContextMusicConfig"] as? [String: Any],
               (config["pageType"] as? String) == "MUSIC_PAGE_TYPE_TRACK_LYRICS" {
                return id
            }
            for nested in dict.values {
                if let found = lyricsBrowseId(in: nested) { return found }
            }
        } else if let array = value as? [Any] {
            for nested in array {
                if let found = lyricsBrowseId(in: nested) { return found }
            }
        }
        return nil
    }

    /// musicDescriptionShelfRenderer.description.runs[].text
    static func descriptionText(in value: Any) -> String? {
        if let dict = value as? [String: Any] {
            if let shelf = dict["musicDescriptionShelfRenderer"] as? [String: Any],
               let runs = (shelf["description"] as? [String: Any])?["runs"] as? [[String: Any]] {
                return runs.compactMap { $0["text"] as? String }.joined()
            }
            for nested in dict.values {
                if let found = descriptionText(in: nested) { return found }
            }
        } else if let array = value as? [Any] {
            for nested in array {
                if let found = descriptionText(in: nested) { return found }
            }
        }
        return nil
    }
}
