//
//  LyricsService.swift
//  Trop
//
//  Created by 686udjie on 16/07/2026.
//

import Foundation

/// One timed word (or syllable) of a word-synced line.
struct LyricWord: Equatable, Sendable, Codable {
    let text: String
    let start: TimeInterval
    var end: TimeInterval
}

struct LyricLine: Identifiable, Equatable, Sendable, Codable {
    /// Replaced by `LyricLine.stable(_:)` before display: a UUID per
    /// construction made every reload look like brand-new rows to SwiftUI.
    var id: String = UUID().uuidString
    let text: String
    let startTime: TimeInterval?
    /// Real word timings when the provider supplies them (enhanced LRC);
    /// nil for line-synced lyrics.
    var words: [LyricWord]? = nil
    /// Background vocals (TTML x-bg spans), shown small under the line.
    var backgroundText: String? = nil

    static let placeholder = LyricLine(text: "♪", startTime: nil)

    /// Deterministic IDs from position + timestamp — unique even for
    /// identical refrain lines, identical across reloads of the same lyrics.
    static func stable(_ lines: [LyricLine]) -> [LyricLine] {
        lines.enumerated().map { index, line in
            var copy = line
            let time = line.startTime.map { String(format: "%.3f", $0) } ?? "-"
            copy.id = "\(index)@\(time)"
            return copy
        }
    }

    /// Same text, timing and words (ignores the id).
    func sameContent(as other: LyricLine) -> Bool {
        text == other.text && startTime == other.startTime && words == other.words
    }

    /// Same lines with every timestamp multiplied (slowed/sped-up variants).
    static func scaled(_ lines: [LyricLine], by factor: Double) -> [LyricLine] {
        lines.map { line in
            var copy = LyricLine(
                text: line.text,
                startTime: line.startTime.map { $0 * factor },
                words: line.words?.map { LyricWord(text: $0.text, start: $0.start * factor, end: $0.end * factor) },
                backgroundText: line.backgroundText
            )
            copy.id = line.id
            return copy
        }
    }
}

/// How good a lyrics result is: word-synced > line-synced > plain text.
enum LyricsQuality: Int, Comparable, Sendable {
    case plain = 0
    case lineSynced = 1
    case wordSynced = 2

    static func of(_ lines: [LyricLine]) -> LyricsQuality {
        guard lines.contains(where: { $0.startTime != nil }) else { return .plain }
        let wordLines = lines.filter { ($0.words?.count ?? 0) > 1 }.count
        return wordLines * 2 >= lines.filter { $0.startTime != nil }.count ? .wordSynced : .lineSynced
    }

    static func < (a: LyricsQuality, b: LyricsQuality) -> Bool { a.rawValue < b.rawValue }
}

/// Persistent per-song lyrics cache (Caches/lyrics/<videoId>.json).
enum LyricsDiskCache {
    private struct Entry: Codable {
        let provider: String?
        let lines: [LyricLine]
        var tempo: Double?
    }

    private static var directory: URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        // v2: results are tempo-checked; older, possibly unscaled entries
        // for slowed / sped-up uploads are discarded.
        let dir = base.appendingPathComponent("lyrics-v2", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func file(_ videoId: String) -> URL? {
        let safe = videoId.replacingOccurrences(of: "/", with: "_")
        return directory?.appendingPathComponent("\(safe).json")
    }

    static func load(_ videoId: String) -> (lines: [LyricLine], provider: String?, tempo: Double?)? {
        guard let url = file(videoId),
              let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              !entry.lines.isEmpty else { return nil }
        return (entry.lines, entry.provider, entry.tempo)
    }

    static func save(_ lines: [LyricLine], provider: String?, tempo: Double?, for videoId: String) {
        guard let url = file(videoId),
              let data = try? JSONEncoder().encode(Entry(provider: provider, lines: lines, tempo: tempo)) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func remove(_ videoId: String) {
        guard let url = file(videoId) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

@MainActor
@Observable
final class LyricsState {
    static let shared = LyricsState()

    /// Songs with confirmed lyrics. Populated by preload/fetch.
    var availableVideoIds: Set<String> = []
    var providerName: String?
    var refreshToken: Int = 0
    /// Factor the lyrics timestamps were scaled by automatically
    /// (slowed / sped-up versions), per video id.
    var autoTempo: [String: Double] = [:]

    private init() {}
}

actor LyricsService {
    static let shared = LyricsService()

    private var cache: [String: [LyricLine]] = [:]
    private var providerNames: [String: String] = [:]
    private var customs: [String: (lines: [LyricLine], providerName: String)] = [:]
    private var inFlight: [String: Task<FetchResult, Error>] = [:]

    private init() {}

    private static func customKey(_ videoId: String) -> String { "lyrics.custom.\(videoId)" }
    private static func customProviderKey(_ videoId: String) -> String { "lyrics.customProvider.\(videoId)" }

    private struct FetchResult: Sendable {
        let lines: [LyricLine]
        let providerName: String?
        let tempo: Double?
    }

    func fetchLyrics(videoId: String) async throws -> [LyricLine] {
        if let custom = customEntry(for: videoId) {
            await updateAvailability(videoId: videoId, available: true, providerName: custom.providerName)
            return custom.lines
        }
        if let cached = cache[videoId] {
            await updateAvailability(videoId: videoId, available: !cached.isEmpty, providerName: providerNames[videoId])
            return cached
        }
        if let stored = LyricsDiskCache.load(videoId) {
            cache[videoId] = stored.lines
            providerNames[videoId] = stored.provider
            await publishTempo(stored.tempo, for: videoId)
            await updateAvailability(videoId: videoId, available: true, providerName: stored.provider)
            return stored.lines
        }
        if let flight = inFlight[videoId] {
            return try await flight.value.lines
        }
        guard let query = await resolveQuery(videoId: videoId) else {
            await updateAvailability(videoId: videoId, available: false)
            throw LyricsError.notFound
        }
        let flight = Task<FetchResult, Error> {
            let (lines, providerName, tempo) = try await Self.fetchFromProviders(query)
            return FetchResult(lines: lines, providerName: providerName, tempo: tempo)
        }
        inFlight[videoId] = flight
        do {
            let result = try await flight.value
            inFlight.removeValue(forKey: videoId)
            // Only cache successful lookups — empty results should be retried later
            // since lyrics can be matched/published after playback starts.
            if !result.lines.isEmpty {
                cache[videoId] = result.lines
                providerNames[videoId] = result.providerName
                LyricsDiskCache.save(result.lines, provider: result.providerName, tempo: result.tempo, for: videoId)
            }
            await publishTempo(result.tempo, for: videoId)
            await updateAvailability(videoId: videoId, available: !result.lines.isEmpty, providerName: result.providerName)
            return result.lines
        } catch {
            inFlight.removeValue(forKey: videoId)
            if !(error is CancellationError) {
                await updateAvailability(videoId: videoId, available: false)
            }
            throw error
        }
    }

    // MARK: - Manual Manipulations (edit / refetch / search selection / copy)

    /// Raw text of the active lyrics for the editor.
    func editableText(videoId: String) -> String {
        if let custom = customEntry(for: videoId) {
            return LyricsParsing.serializeLines(custom.lines)
        }
        if let cached = cache[videoId] {
            return LyricsParsing.serializeLines(cached)
        }
        return ""
    }

    /// Plain text without timestamps for the clipboard.
    func plainTextForCopy(videoId: String) -> String? {
        if let custom = customEntry(for: videoId) {
            return LyricsParsing.plainText(custom.lines)
        }
        if let cached = cache[videoId] {
            return LyricsParsing.plainText(cached)
        }
        return nil
    }

    /// Stores edited or search-selected lyrics and signals the view to reload.
    func saveCustom(videoId: String, rawText: String, providerName: String?) {
        let lines = LyricsParsing.parseStoredText(rawText)
        guard !lines.isEmpty else { return }
        // Edits keep the existing provider; fresh selections pass their own.
        let provider = providerName
            ?? customs[videoId]?.providerName
            ?? UserDefaults.standard.string(forKey: Self.customProviderKey(videoId))
            ?? "Manual"
        customs[videoId] = (lines, provider)
        UserDefaults.standard.set(rawText, forKey: Self.customKey(videoId))
        UserDefaults.standard.set(provider, forKey: Self.customProviderKey(videoId))
        cache.removeValue(forKey: videoId)
        Task {
            await MainActor.run {
                LyricsState.shared.availableVideoIds.insert(videoId)
                LyricsState.shared.providerName = provider
                LyricsState.shared.refreshToken += 1
            }
        }
    }

    /// Re-fetches from providers; replaces any manual override with the fresh
    /// result (explicit user intent), like Metrolist's refetchLyrics.
    func refetch(videoId: String) async {
        cache.removeValue(forKey: videoId)
        LyricsDiskCache.remove(videoId)
        func signalReload() {
            Task { await MainActor.run { LyricsState.shared.refreshToken += 1 } }
        }
        guard let query = await resolveQuery(videoId: videoId),
              let (fetchedLines, fetchedProvider, fetchedTempo) = try? await Self.fetchFromProviders(query),
              !fetchedLines.isEmpty else {
            await updateAvailability(videoId: videoId, available: false)
            signalReload()
            return
        }
        cache[videoId] = fetchedLines
        await publishTempo(fetchedTempo, for: videoId)
        let raw = LyricsParsing.serializeLines(fetchedLines)
        let provider = fetchedProvider ?? "Manual"
        customs[videoId] = (fetchedLines, provider)
        UserDefaults.standard.set(raw, forKey: Self.customKey(videoId))
        UserDefaults.standard.set(provider, forKey: Self.customProviderKey(videoId))
        await updateAvailability(videoId: videoId, available: true, providerName: provider)
        signalReload()
    }

    private func customEntry(for videoId: String) -> (lines: [LyricLine], providerName: String)? {
        if let entry = customs[videoId] { return entry }
        guard let raw = UserDefaults.standard.string(forKey: Self.customKey(videoId)) else { return nil }
        let lines = LyricsParsing.parseStoredText(raw)
        guard !lines.isEmpty else { return nil }
        let provider = UserDefaults.standard.string(forKey: Self.customProviderKey(videoId)) ?? "Manual"
        let entry = (lines, provider)
        customs[videoId] = entry
        return entry
    }

    func preload(videoId: String, upcoming: [String] = []) async {
        _ = try? await fetchLyrics(videoId: videoId)
        for id in upcoming where cache[id] == nil && customEntry(for: id) == nil {
            _ = try? await fetchLyrics(videoId: id)
        }
    }

    private func publishTempo(_ tempo: Double?, for videoId: String) async {
        await MainActor.run { LyricsState.shared.autoTempo[videoId] = tempo }
    }

    private func updateAvailability(videoId: String, available: Bool, providerName: String? = nil) async {
        await MainActor.run {
            if available {
                LyricsState.shared.availableVideoIds.insert(videoId)
            } else {
                LyricsState.shared.availableVideoIds.remove(videoId)
            }
        }
        let currentId = await MainActor.run { NowPlaying.shared.videoId }
        guard currentId == videoId else { return }
        await MainActor.run {
            if available { LyricsState.shared.providerName = providerName }
        }
    }

    private func resolveQuery(videoId: String) async -> LyricsQuery? {
        let info = await MainActor.run {
            let np = NowPlaying.shared
            return (
                title: np.title,
                artist: np.displayArtist,
                album: np.albumTitle.isEmpty ? nil : np.albumTitle,
                duration: np.duration,
                currentId: np.videoId,
                queue: np.queueSongs
            )
        }

        let (npTitle, npArtist, npAlbum, npDuration, currentId, queue) = info

        let title: String
        let artist: String
        let album: String?
        let duration: TimeInterval

        if currentId == videoId, !npTitle.isEmpty, !npArtist.isEmpty {
            title = npTitle
            artist = npArtist
            album = npAlbum
            duration = npDuration
        } else if let song = queue.first(where: { $0.videoId == videoId }) {
            title = song.title
            artist = song.artists.map(\.name).joined(separator: ", ")
            album = song.album?.isEmpty == false ? song.album : nil
            let dur = song.duration > 0 ? song.duration : (DurationCache.get(videoId) ?? 0)
            duration = TimeInterval(dur)
        } else {
            return nil
        }

        guard !title.isEmpty, !artist.isEmpty else { return nil }
        let cleaned = cleanQuery(title: title, artist: artist, album: album)
        return LyricsQuery(
            title: cleaned.title,
            artist: cleaned.artist,
            album: cleaned.album,
            duration: duration > 0 ? duration : 0,
            videoId: videoId,
            isSpeedVariant: Self.isSpeedVariant(title)
        )
    }

    // MARK: Slowed / sped-up variants

    static func isSpeedVariant(_ title: String) -> Bool {
        title.range(of: #"\b((super|ultra)\s+)?(slowed|sped\s*up|speed\s*up|nightcore|daycore|reverb)\b"#,
                    options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Lookup plus tempo check of EVERY result: some providers return lyrics
    /// for a "(Slowed)" title directly, but with the ORIGINAL's timestamps.
    /// When the title is a variant or the last timestamp doesn't fit this
    /// song's length, the original's length is determined and all line and
    /// word times are scaled by variant / original (only 0.6-1.5×).
    /// Returns the factor applied (nil = untouched).
    private static func fetchFromProviders(_ query: LyricsQuery) async throws -> ([LyricLine], providerName: String?, tempo: Double?) {
        let played = query.duration
        var original: TimeInterval?
        var lookup = query
        if query.isSpeedVariant, played > 0 {
            original = await originalDuration(title: query.title, artist: query.artist)
            // Search with the original's length (or none) so length-checked
            // providers match the original recording.
            lookup = LyricsQuery(title: query.title, artist: query.artist, album: nil, duration: original ?? 0, videoId: query.videoId)
        }
        let (lines, provider) = try await LyricsManager.shared.fetchLyricsReturningProvider(query: lookup)
        guard played > 0, let last = lines.compactMap(\.startTime).max() else { return (lines, provider, nil) }

        let mismatch = last > played + 3
        guard query.isSpeedVariant || mismatch else { return (lines, provider, nil) }
        if original == nil {
            original = await originalDuration(title: query.title, artist: query.artist)
        }
        if let original, original > 0 {
            let factor = played / original
            if (0.6...1.5).contains(factor), abs(factor - 1) > 0.02 {
                return (LyricLine.scaled(lines, by: factor), provider, factor)
            }
            if abs(factor - 1) <= 0.02 { return (lines, provider, nil) }
        }
        // Can't tell how to scale: show the text without wrong timing.
        if mismatch {
            return (lines.map { LyricLine(text: $0.text, startTime: nil, backgroundText: $0.backgroundText) }, provider, nil)
        }
        return (lines, provider, nil)
    }

    /// Length of the ORIGINAL recording via LRCLIB search: entries whose
    /// title equals the cleaned title, by the same main artist, and that are
    /// not themselves slowed/sped-up uploads; synced ones preferred.
    private static func originalDuration(title: String, artist: String) async -> TimeInterval? {
        var components = URLComponents(string: "https://lrclib.net/api/search")
        components?.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist)
        ]
        guard let url = components?.url,
              let data = await LyricsRequest.get(url, timeout: 4),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        func norm(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
        let wantedTitle = norm(title)
        let wantedArtist = norm(artist)
        let candidates = items.filter { item in
            let name = item["trackName"] as? String ?? ""
            let by = norm(item["artistName"] as? String ?? "")
            return norm(name) == wantedTitle
                && !isSpeedVariant(name)
                && (wantedArtist.isEmpty || by.contains(wantedArtist) || wantedArtist.contains(by))
        }
        let pick = candidates.first { ($0["syncedLyrics"] as? String)?.isEmpty == false } ?? candidates.first
        guard let seconds = (pick?["duration"] as? NSNumber)?.doubleValue, seconds > 0 else { return nil }
        return seconds
    }

    private struct CleanedQuery {
        let title: String
        let artist: String
        let album: String?
    }

    private func cleanQuery(title: String, artist: String, album: String?) -> CleanedQuery {
        let (extractedTitle, extractedArtist) = Self.extractArtistTitle(from: title, channelArtist: artist)
        let cleanedTitle = Self.cleanTitle(extractedTitle)
        let cleanedArtist = Self.cleanArtist(extractedArtist ?? artist)
        let cleanedAlbum = album.map { Self.cleanAlbum($0) }
        return CleanedQuery(title: cleanedTitle, artist: cleanedArtist, album: cleanedAlbum)
    }

    private static func extractArtistTitle(from rawTitle: String, channelArtist: String) -> (title: String, artist: String?) {
        guard isChannelLike(channelArtist) else { return (rawTitle, nil) }
        let separators = [" - ", " – ", " — "]
        for sep in separators {
            if let range = rawTitle.range(of: sep) {
                let left = String(rawTitle[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let right = String(rawTitle[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !left.isEmpty, !right.isEmpty else { break }
                // left = real artist, right = real title
                return (right, left)
            }
        }
        return (rawTitle, nil)
    }

    private static func isChannelLike(_ name: String) -> Bool {
        let lower = name.lowercased()
        guard !lower.isEmpty else { return false }
        let channelWords = ["music", "channel", "official", "records", "record",
                           "tv", "studio", "entertainment", "4k", "中文", "古风",
                           "chinese", "ort", "ehp", "vip", "lyrics", "mv",
                           "topic", "vevo", "remix", "dj", "radio"]
        return channelWords.contains(where: { lower.contains($0) })
    }

    private static func cleanTitle(_ raw: String) -> String {
        var s = raw
        s = s.replacingOccurrences(of: #"【[^】]*】"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"「[^」]*」"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"『[^』]*』"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
        // "feat./ft." credits outside brackets, "- Slowed + Reverb",
        // "| Official Video" style suffixes and video/audio labels.
        s = s.replacingOccurrences(of: #"\s+(feat\.?|ft\.?|featuring)\s+.*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(
            of: #"\s*[-–—|]\s*(((super|ultra)\s+)?slowed|sped\s*up|speed\s*up|nightcore|daycore|reverb|8d|official|lyrics?|audio|video|visuali[sz]er|remaster(ed)?)\b.*$"#,
            with: "", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(
            of: #"\b(official\s+(music\s+)?(video|audio|lyric\s+video|visuali[sz]er)|lyric\s+video|music\s+video|(super\s+)?slowed(\s*\+\s*reverb)?|sped\s*up)\b"#,
            with: "", options: [.regularExpression, .caseInsensitive])
        for marker in ["|", "♪", "mv", "lyrics", "歌词", "動態", "动态", "official", "官方"] {
            if let r = s.range(of: marker, options: .caseInsensitive) {
                s = String(s[..<r.lowerBound])
                break
            }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanArtist(_ raw: String) -> String {
        let parts = raw
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { part -> String in
                var p = part
                if let range = p.range(of: " - ") {
                    p = String(p[..<range.lowerBound])
                }
                p = p.replacingOccurrences(of: " - Topic", with: "")
                p = p.replacingOccurrences(of: "-Topic", with: "")
                p = p.replacingOccurrences(of: "Topic", with: "")
                return p.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
        // Main artist only: "A, B", "A & B", "A x B", "A feat. B" → "A".
        guard let first = parts.first else { return raw }
        let main = first.replacingOccurrences(
            of: #"\s+(&|x|×|and|with|feat\.?|ft\.?|featuring|vs\.?)\s+.*$|\s*/.*$"#,
            with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return main.isEmpty ? first : main
    }

    private static func cleanAlbum(_ raw: String) -> String {
        var s = raw
        s = s.replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
