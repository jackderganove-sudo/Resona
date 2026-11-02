//
//  VersionLyricsProviders.swift
//  Resona
//
//  More lyrics sources (as in ArchiveTune), all usable without an account:
//  • SimpMusic — community lyrics per YouTube video id: exactly this
//    upload, so remixes / edits get their own lyrics.
//  • Unison — lyrics database with search, per video id and its variants.
//  • Megalobiz — LRC files (search page → LRC page).
//  • QQ Music — public search + LRC endpoint.
//  Every provider can return several candidates with title / artist /
//  duration, used by the manual search list and the version ranking.
//

import Foundation

enum ProviderLyricsFormat {
    /// LRC (also enhanced word tags), TTML, otherwise plain lines.
    static func lines(from raw: String) -> [LyricLine] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if trimmed.hasPrefix("<") && trimmed.contains("<tt") {
            let ttml = TTMLLyricsParser.parse(trimmed)
            if !ttml.isEmpty { return ttml }
        }
        let lrc = LyricsParsing.parseLrc(trimmed)
        if !lrc.isEmpty { return lrc }
        return LyricsText.plainLines(trimmed)
    }

    /// Basic HTML entity decoding (&amp; &lt; &gt; &quot; &#39; &#NN;).
    static func decodeEntities(_ s: String) -> String {
        var out = s.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
        let regex = try? NSRegularExpression(pattern: "&#(x?[0-9a-fA-F]+);")
        let ns = out as NSString
        for match in (regex?.matches(in: out, range: NSRange(location: 0, length: ns.length)) ?? []).reversed() {
            let code = ns.substring(with: match.range(at: 1))
            let value = code.hasPrefix("x") ? UInt32(code.dropFirst(), radix: 16) : UInt32(code)
            if let value, let scalar = Unicode.Scalar(value) {
                out = (out as NSString).replacingCharacters(in: match.range, with: String(Character(scalar)))
            }
        }
        return out.replacingOccurrences(of: "&amp;", with: "&")
    }
}

// MARK: - SimpMusic

struct SimpMusicLyricsProvider: LyricsProvider {
    let id = "simpmusic"
    let name = "SimpMusic"

    func fetch(query: LyricsQuery) async throws -> [LyricLine] {
        guard let best = try await search(query: query).first else { throw LyricsError.notFound }
        return best.lines
    }

    func search(query: LyricsQuery) async throws -> [LyricsCandidate] {
        guard let videoId = query.videoId, let url = URL(string: "https://api-lyrics.simpmusic.org/v1/\(videoId)") else {
            throw LyricsError.notFound
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("SimpMusicLyrics/1.0", forHTTPHeaderField: "User-Agent")
        let candidates = Self.parse(try await LyricsHTTP.getJSON(request), queryDuration: query.duration)
        guard !candidates.isEmpty else { throw LyricsError.notFound }
        return candidates
    }

    /// `{"type":"success","data":[{songTitle, artistName, durationSeconds,
    /// syncedLyrics, plainLyric}]}` — closest duration first.
    static func parse(_ json: [String: Any], queryDuration: Double) -> [LyricsCandidate] {
        guard (json["type"] as? String) == "success", let data = json["data"] as? [[String: Any]] else { return [] }
        let candidates: [LyricsCandidate] = data.compactMap { item in
            let duration = (item["durationSeconds"] as? NSNumber)?.doubleValue
            var lines: [LyricLine] = []
            if let synced = item["syncedLyrics"] as? String { lines = LyricsParsing.parseLrc(synced) }
            if lines.isEmpty, let plain = item["plainLyric"] as? String { lines = LyricsText.plainLines(plain) }
            guard !lines.isEmpty else { return nil }
            return LyricsCandidate(lines: lines, title: item["songTitle"] as? String, artist: item["artistName"] as? String,
                                   duration: duration, exactVersion: true)
        }
        guard queryDuration > 0 else { return candidates }
        return candidates.sorted { abs(($0.duration ?? 0) - queryDuration) < abs(($1.duration ?? 0) - queryDuration) }
    }
}

// MARK: - Unison

struct UnisonLyricsProvider: LyricsProvider {
    let id = "unison"
    let name = "Unison"
    private let base = "https://unison.boidu.dev/"

    func fetch(query: LyricsQuery) async throws -> [LyricLine] {
        guard let best = try await search(query: query).first else { throw LyricsError.notFound }
        return best.lines
    }

    /// Exact video first (and its variants), then the metadata search.
    func search(query: LyricsQuery) async throws -> [LyricsCandidate] {
        var results: [LyricsCandidate] = []
        if let videoId = query.videoId {
            if let entry = try? await get("lyrics", ["v": videoId]), let single = entry["data"] as? [String: Any],
               let candidate = Self.candidate(single, videoId: videoId) {
                results.append(candidate)
            }
            if let variants = try? await get("lyrics/variants/\(videoId)", [:]), let list = variants["data"] as? [[String: Any]] {
                results += list.prefix(5).compactMap { Self.candidate($0, videoId: videoId) }
            }
        }
        var params = ["song": query.title, "artist": query.artist, "limit": "5"]
        if query.durationSeconds > 0 { params["duration"] = String(query.durationSeconds) }
        if let found = try? await get("lyrics/search", params), let list = found["data"] as? [[String: Any]] {
            results += list.prefix(5).compactMap { Self.candidate($0, videoId: query.videoId) }
        }
        guard !results.isEmpty else { throw LyricsError.notFound }
        return results
    }

    private func get(_ path: String, _ params: [String: String]) async throws -> [String: Any] {
        guard var components = URLComponents(string: base + path) else { throw LyricsError.invalidURL }
        if !params.isEmpty { components.queryItems = params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = components.url else { throw LyricsError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        let json = try await LyricsHTTP.getJSON(request)
        guard (json["success"] as? Bool) == true else { throw LyricsError.notFound }
        return json
    }

    /// `{id, videoId, song, artist, lyrics, format, syncType}`.
    static func candidate(_ item: [String: Any], videoId: String?) -> LyricsCandidate? {
        guard let raw = item["lyrics"] as? String else { return nil }
        let lines = ProviderLyricsFormat.lines(from: raw)
        guard !lines.isEmpty else { return nil }
        let entryVideo = item["videoId"] as? String
        return LyricsCandidate(lines: lines, title: item["song"] as? String, artist: item["artist"] as? String,
                               duration: nil, exactVersion: entryVideo != nil && entryVideo == videoId)
    }
}

// MARK: - Megalobiz

struct MegalobizLyricsProvider: LyricsProvider {
    let id = "megalobiz"
    let name = "Megalobiz"

    func fetch(query: LyricsQuery) async throws -> [LyricLine] {
        let term = "\(query.artist) \(query.title)".trimmingCharacters(in: .whitespaces)
        var components = URLComponents(string: "https://www.megalobiz.com/searchall")
        components?.queryItems = [URLQueryItem(name: "qry", value: term)]
        guard let searchURL = components?.url else { throw LyricsError.invalidURL }
        let searchHTML = try await html(searchURL)
        guard let path = Self.firstLrcPath(in: searchHTML), let lrcURL = URL(string: "https://www.megalobiz.com" + path) else {
            throw LyricsError.notFound
        }
        let lines = Self.lrcLines(fromDetailPage: try await html(lrcURL))
        guard lines.contains(where: { $0.startTime != nil }) else { throw LyricsError.notFound }
        return lines
    }

    private func html(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64)", forHTTPHeaderField: "User-Agent")
        return String(decoding: try await LyricsHTTP.get(request), as: UTF8.self)
    }

    static func firstLrcPath(in html: String) -> String? {
        let regex = try? NSRegularExpression(pattern: #"href=["'](/lrc/maker/download/[^"']+)["']"#)
        let ns = html as NSString
        guard let match = regex?.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    static func lrcLines(fromDetailPage html: String) -> [LyricLine] {
        let regex = try? NSRegularExpression(pattern: #"id=["']lrc_[^"']*_details["'][^>]*>(.*?)</span>"#, options: .dotMatchesLineSeparators)
        let ns = html as NSString
        guard let match = regex?.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)) else { return [] }
        var text = ns.substring(with: match.range(at: 1))
        text = text.replacingOccurrences(of: "<br />", with: "\n").replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br>", with: "\n")
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return LyricsParsing.parseLrc(ProviderLyricsFormat.decodeEntities(text))
    }
}

// MARK: - QQ Music

struct QQMusicLyricsProvider: LyricsProvider {
    let id = "qqmusic"
    let name = "QQ Music"

    func fetch(query: LyricsQuery) async throws -> [LyricLine] {
        guard let best = try await search(query: query).first else { throw LyricsError.notFound }
        return best.lines
    }

    func search(query: LyricsQuery) async throws -> [LyricsCandidate] {
        var components = URLComponents(string: "https://c.y.qq.com/soso/fcgi-bin/client_search_cp")
        components?.queryItems = [
            URLQueryItem(name: "format", value: "json"), URLQueryItem(name: "p", value: "1"),
            URLQueryItem(name: "n", value: "5"), URLQueryItem(name: "w", value: "\(query.title) \(query.artist)")
        ]
        guard let url = components?.url else { throw LyricsError.invalidURL }
        let songs = Self.parseSearch(try await json(url))
        var results: [LyricsCandidate] = []
        for song in songs.prefix(3) {
            var lyricComponents = URLComponents(string: "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg")
            lyricComponents?.queryItems = [
                URLQueryItem(name: "songmid", value: song.mid), URLQueryItem(name: "format", value: "json"),
                URLQueryItem(name: "nobase64", value: "1"), URLQueryItem(name: "g_tk", value: "5381")
            ]
            guard let lyricURL = lyricComponents?.url, let body = try? await json(lyricURL),
                  let raw = body["lyric"] as? String else { continue }
            let lines = LyricsParsing.parseLrc(ProviderLyricsFormat.decodeEntities(raw))
            guard lines.contains(where: { $0.startTime != nil }) else { continue }
            results.append(LyricsCandidate(lines: lines, title: song.title, artist: song.artist, duration: song.duration, exactVersion: false))
        }
        guard !results.isEmpty else { throw LyricsError.notFound }
        return results
    }

    private func json(_ url: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        let data = try await LyricsHTTP.get(request)
        return try Self.decodeJSONP(data)
    }

    /// Plain JSON or `callback({...})`.
    static func decodeJSONP(_ data: Data) throws -> [String: Any] {
        var text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if let open = text.firstIndex(of: "("), !text.hasPrefix("{"), text.hasSuffix(")") {
            text = String(text[text.index(after: open)..<text.index(before: text.endIndex)])
        }
        guard let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            throw LyricsError.decodingFailed
        }
        return json
    }

    struct Song: Equatable {
        let mid: String
        let title: String
        let artist: String
        let duration: Double?
    }

    static func parseSearch(_ json: [String: Any]) -> [Song] {
        let list = ((json["data"] as? [String: Any])?["song"] as? [String: Any])?["list"] as? [[String: Any]] ?? []
        return list.compactMap { item in
            guard let mid = item["songmid"] as? String, let title = item["songname"] as? String else { return nil }
            let singers = (item["singer"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
            return Song(mid: mid, title: ProviderLyricsFormat.decodeEntities(title), artist: singers.joined(separator: ", "),
                        duration: (item["interval"] as? NSNumber)?.doubleValue)
        }
    }
}

// MARK: - Binimum

/// Binimum Lyrics (as in ArchiveTune 15): lookup by track / artist /
/// album / duration, results point to TTML files — word-synced first, then
/// the closest duration.
struct BinimumLyricsProvider: LyricsProvider {
    let id = "binimum"
    let name = "Binimum"

    func fetch(query: LyricsQuery) async throws -> [LyricLine] {
        guard let best = try await search(query: query).first else { throw LyricsError.notFound }
        return best.lines
    }

    func search(query: LyricsQuery) async throws -> [LyricsCandidate] {
        var components = URLComponents(string: "https://lyrics-api.binimum.org/")
        var items = [URLQueryItem(name: "track", value: query.title), URLQueryItem(name: "artist", value: query.artist)]
        if let album = query.album, !album.isEmpty { items.append(URLQueryItem(name: "album", value: album)) }
        if query.durationSeconds > 0 { items.append(URLQueryItem(name: "duration", value: String(query.durationSeconds))) }
        components?.queryItems = items
        guard let url = components?.url else { throw LyricsError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let matches = Self.parseLookup(try await LyricsHTTP.getJSON(request), queryDuration: query.duration)
        var results: [LyricsCandidate] = []
        for match in matches.prefix(2) {
            guard let ttmlURL = URL(string: match.url), ttmlURL.scheme == "https" else { continue }
            var ttmlRequest = URLRequest(url: ttmlURL)
            ttmlRequest.timeoutInterval = 8
            ttmlRequest.setValue("application/ttml+xml, application/xml, text/xml", forHTTPHeaderField: "Accept")
            guard let data = try? await LyricsHTTP.get(ttmlRequest) else { continue }
            let lines = TTMLLyricsParser.parse(String(decoding: data, as: UTF8.self))
            guard !lines.isEmpty else { continue }
            results.append(LyricsCandidate(lines: lines, duration: match.duration))
        }
        guard !results.isEmpty else { throw LyricsError.notFound }
        return results
    }

    struct Match: Equatable { let url: String; let wordTimed: Bool; let duration: Double? }

    /// `{"results":[{"lyricsUrl", "timing_type", "duration"}]}`.
    static func parseLookup(_ json: [String: Any], queryDuration: Double) -> [Match] {
        var seen = Set<String>()
        let matches = (json["results"] as? [[String: Any]] ?? []).compactMap { item -> Match? in
            guard let url = item["lyricsUrl"] as? String, seen.insert(url).inserted else { return nil }
            return Match(url: url, wordTimed: (item["timing_type"] as? String) == "word",
                         duration: (item["duration"] as? NSNumber)?.doubleValue)
        }
        return matches.sorted { a, b in
            if a.wordTimed != b.wordTimed { return a.wordTimed }
            guard queryDuration > 0 else { return false }
            return abs((a.duration ?? .greatestFiniteMagnitude) - queryDuration) < abs((b.duration ?? .greatestFiniteMagnitude) - queryDuration)
        }
    }
}
