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
    /// Translation supplied by the provider (TTML x-translation).
    var translation: String? = nil

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

    /// "Fake synced" lyrics (every line at the same time, typically
    /// [00:00.00]) are plain text: timestamps removed.
    static func normalizedTiming(_ lines: [LyricLine]) -> [LyricLine] {
        let times = lines.compactMap(\.startTime)
        guard times.count >= 3, let first = times.first,
              times.allSatisfy({ abs($0 - first) < 0.01 }) else { return lines }
        return lines.map { LyricLine(text: $0.text, startTime: nil, backgroundText: $0.backgroundText, translation: $0.translation) }
    }

    /// Line and word times never go backwards (a line starting before the
    /// previous one made the highlight jump back and forth): such times are
    /// pulled up to the previous one + a minimum length.
    static func monotonicTiming(_ lines: [LyricLine], minLine: Double = 0.2, minWord: Double = 0.05) -> [LyricLine] {
        var lastLine: Double?
        var lastWord: Double?
        return lines.map { line in
            guard var start = line.startTime else { return line }
            if let lastLine, start < lastLine + minLine { start = lastLine + minLine }
            lastLine = start
            var words = line.words
            if let original = line.words {
                var fixed: [LyricWord] = []
                for (index, word) in original.enumerated() {
                    var wordStart = max(word.start, index == 0 ? start : word.start)
                    if let lastWord, wordStart < lastWord + minWord { wordStart = lastWord + minWord }
                    if index == 0 { wordStart = max(wordStart, start) }
                    lastWord = wordStart
                    fixed.append(LyricWord(text: word.text, start: wordStart, end: max(word.end, wordStart + minWord)))
                }
                words = fixed
            }
            guard start != line.startTime || words != line.words else { return line }
            var copy = LyricLine(text: line.text, startTime: start, words: words,
                                 backgroundText: line.backgroundText, translation: line.translation)
            copy.id = line.id
            return copy
        }
    }

    /// Same lines with every timestamp multiplied (slowed/sped-up variants).
    static func scaled(_ lines: [LyricLine], by factor: Double) -> [LyricLine] {
        lines.map { line in
            var copy = LyricLine(
                text: line.text,
                startTime: line.startTime.map { $0 * factor },
                words: line.words?.map { LyricWord(text: $0.text, start: $0.start * factor, end: $0.end * factor) },
                backgroundText: line.backgroundText,
                translation: line.translation
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

/// Result of the slowed / sped-up check of one song's lyrics (logged and
/// shown under "Lyrics from …").
struct LyricsTempoInfo: Codable, Sendable, Equatable {
    enum Outcome: String, Codable, Sendable {
        /// Not a variant and timing fits the length: nothing to do.
        case notNeeded
        /// Timestamps scaled by `factor`.
        case applied
        /// Variant title, but the same length as the original (< 2 %).
        case sameLength
        /// No original length found (variant or timing past the end).
        case noOriginal
        /// Lengths too different for a speed change (outside 0.6–1.5×).
        case implausible
        /// The song's own length wasn't known yet.
        case unknownLength
    }

    var outcome: Outcome
    var isVariant: Bool
    var played: Double
    var original: Double?
    /// How the original length was found.
    var source: String?
    var factor: Double?

    /// Worth showing under the provider label.
    var isRelevant: Bool { isVariant || outcome != .notNeeded }
}

/// Persistent per-song lyrics cache (Caches/lyrics/<videoId>.json).
enum LyricsDiskCache {
    private struct Entry: Codable {
        let provider: String?
        let lines: [LyricLine]
        var tempo: Double?
        var tempoInfo: LyricsTempoInfo?
    }

    private static var directory: URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        // v3: tempo check with diagnosis and title+lyrics original lookup;
        // older, possibly unscaled entries are discarded.
        let dir = base.appendingPathComponent("lyrics-v3", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func file(_ videoId: String) -> URL? {
        let safe = videoId.replacingOccurrences(of: "/", with: "_")
        return directory?.appendingPathComponent("\(safe).json")
    }

    static func load(_ videoId: String) -> (lines: [LyricLine], provider: String?, tempoInfo: LyricsTempoInfo?)? {
        guard let url = file(videoId),
              let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              !entry.lines.isEmpty else { return nil }
        return (entry.lines, entry.provider, entry.tempoInfo)
    }

    static func save(_ lines: [LyricLine], provider: String?, tempoInfo: LyricsTempoInfo?, for videoId: String) {
        let entry = Entry(provider: provider, lines: lines, tempo: tempoInfo?.factor, tempoInfo: tempoInfo)
        guard let url = file(videoId), let data = try? JSONEncoder().encode(entry) else { return }
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
    /// Outcome of the tempo check per video id (shown under the label).
    var tempoInfo: [String: LyricsTempoInfo] = [:]

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
        let tempoInfo: LyricsTempoInfo?
    }

    func fetchLyrics(videoId: String) async throws -> [LyricLine] {
        if var custom = customEntry(for: videoId) {
            var info = Self.storedCustomTempoInfo(videoId)
            // Provider lyrics picked by hand or re-fetched before the tempo
            // check existed: check them once, scale and remember.
            if info == nil, !Self.userMadeProviders.contains(custom.providerName),
               let query = await resolveQuery(videoId: videoId) {
                let checked = await Self.checkTempo(custom.lines, query: query, knownOriginal: nil, source: nil)
                info = checked.info
                if checked.lines != custom.lines {
                    custom = (checked.lines, custom.providerName)
                    customs[videoId] = custom
                    UserDefaults.standard.set(LyricsParsing.serializeLines(checked.lines), forKey: Self.customKey(videoId))
                }
                Self.storeCustomTempoInfo(checked.info, videoId)
                Self.logTempo(checked.info, videoId: videoId, lines: checked.lines.count, origin: "custom (\(custom.providerName))")
            }
            await publishTempo(info, for: videoId)
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
            await publishTempo(stored.tempoInfo, for: videoId)
            Self.logTempo(stored.tempoInfo, videoId: videoId, lines: stored.lines.count, origin: "disk cache")
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
            let (lines, providerName, info) = try await Self.fetchFromProviders(query)
            Self.logTempo(info, videoId: videoId, lines: lines.count, origin: providerName ?? "provider")
            return FetchResult(lines: lines, providerName: providerName, tempoInfo: info)
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
                LyricsDiskCache.save(result.lines, provider: result.providerName, tempoInfo: result.tempoInfo, for: videoId)
            }
            await publishTempo(result.tempoInfo, for: videoId)
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

    /// Settings → Storage → clear lyrics cache.
    func clearMemoryCache() {
        cache.removeAll()
        providerNames.removeAll()
    }

    // MARK: - Manual Manipulations (edit / refetch / search selection / copy)

    /// Raw text of the active lyrics for the editor.
    func editableText(videoId: String) -> String {
        if let custom = customEntry(for: videoId) {
            return LyricsParsing.serializeLines(LyricLine.normalizedTiming(custom.lines))
        }
        if let cached = cache[videoId] {
            return LyricsParsing.serializeLines(LyricLine.normalizedTiming(cached))
        }
        return ""
    }

    /// Current lines (custom, cached or fetched) with fake timing removed.
    func currentLines(videoId: String) async -> [LyricLine] {
        let lines = (try? await fetchLyrics(videoId: videoId)) ?? []
        return LyricLine.normalizedTiming(lines)
    }

    /// Drops self-synced / edited lyrics and loads the providers' again.
    func removeCustom(videoId: String) async {
        customs.removeValue(forKey: videoId)
        cache.removeValue(forKey: videoId)
        LyricsDiskCache.remove(videoId)
        UserDefaults.standard.removeObject(forKey: Self.customKey(videoId))
        UserDefaults.standard.removeObject(forKey: Self.customProviderKey(videoId))
        await MainActor.run { LyricsState.shared.refreshToken += 1 }
    }

    /// Provider name of the stored custom lyrics (e.g. "Self-synced").
    func customProvider(videoId: String) -> String? {
        customEntry(for: videoId)?.providerName
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
        // Edits / own syncs are timed to this recording; provider picks get
        // the tempo check on the next load.
        if Self.userMadeProviders.contains(provider) || providerName == nil {
            Self.storeCustomTempoInfo(LyricsTempoInfo(outcome: .notNeeded, isVariant: false, played: 0), videoId)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.customTempoKey(videoId))
        }
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
              let (fetchedLines, fetchedProvider, fetchedInfo) = try? await Self.fetchFromProviders(query),
              !fetchedLines.isEmpty else {
            await updateAvailability(videoId: videoId, available: false)
            signalReload()
            return
        }
        cache[videoId] = fetchedLines
        await publishTempo(fetchedInfo, for: videoId)
        Self.logTempo(fetchedInfo, videoId: videoId, lines: fetchedLines.count, origin: "refetch")
        let raw = LyricsParsing.serializeLines(fetchedLines)
        let provider = fetchedProvider ?? "Manual"
        customs[videoId] = (fetchedLines, provider)
        UserDefaults.standard.set(raw, forKey: Self.customKey(videoId))
        UserDefaults.standard.set(provider, forKey: Self.customProviderKey(videoId))
        Self.storeCustomTempoInfo(fetchedInfo, videoId)
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

    private func publishTempo(_ info: LyricsTempoInfo?, for videoId: String) async {
        await MainActor.run {
            LyricsState.shared.autoTempo[videoId] = info?.factor
            LyricsState.shared.tempoInfo[videoId] = info
        }
    }

    // MARK: Tempo bookkeeping

    /// Lyrics timed to this very recording: never scaled.
    /// (= "Manual", AILyricsSync.providerName, LyricsSyncSheet.providerName,
    /// AILyricsSync.transcribedProviderName;
    /// literals because those types are main-actor isolated.)
    static let userMadeProviders: Set<String> = ["Manual", "AI-synced", "Self-synced", "AI-transcribed"]

    private static func customTempoKey(_ videoId: String) -> String { "lyrics.customTempoInfo.\(videoId)" }

    private static func storedCustomTempoInfo(_ videoId: String) -> LyricsTempoInfo? {
        guard let data = UserDefaults.standard.data(forKey: customTempoKey(videoId)) else { return nil }
        return try? JSONDecoder().decode(LyricsTempoInfo.self, from: data)
    }

    private static func storeCustomTempoInfo(_ info: LyricsTempoInfo?, _ videoId: String) {
        guard let info, let data = try? JSONEncoder().encode(info) else { return }
        UserDefaults.standard.set(data, forKey: customTempoKey(videoId))
    }

    /// Diagnosis only — never the lyrics themselves.
    static func logTempo(_ info: LyricsTempoInfo?, videoId: String, lines: Int, origin: String) {
        guard let info else {
            Log.player.info("LYRICS tempo id=\(videoId) origin=\(origin) lines=\(lines) info=none")
            return
        }
        func f(_ value: Double?) -> String { value.map { String(format: "%.2f", $0) } ?? "-" }
        Log.player.info("LYRICS tempo id=\(videoId) origin=\(origin) lines=\(lines) variant=\(info.isVariant) played=\(f(info.played)) original=\(f(info.original)) source=\(info.source ?? "-") factor=\(f(info.factor)) outcome=\(info.outcome.rawValue)")
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
    private static func fetchFromProviders(_ query: LyricsQuery) async throws -> ([LyricLine], providerName: String?, tempoInfo: LyricsTempoInfo) {
        let played = query.duration
        var original: TimeInterval?
        var source: String?
        var lookup = query
        if query.isSpeedVariant, played > 0 {
            (original, source) = await originalDuration(title: query.title, artist: query.artist, lines: nil)
            // Search with the original's length (or none) so length-checked
            // providers match the original recording.
            lookup = LyricsQuery(title: query.title, artist: query.artist, album: nil, duration: original ?? 0, videoId: query.videoId)
        }
        var (lines, provider) = try await LyricsManager.shared.fetchLyricsReturningProvider(query: lookup)
        // Before settling for plain text: once more without length/album
        // constraints (cleaned title, e.g. without "Slowed") for a synced
        // version — it is scaled below if its timing belongs to the original.
        if LyricsQuality.of(lines) == .plain, lookup.duration > 0 || lookup.album != nil {
            let open = LyricsQuery(title: query.title, artist: query.artist, album: nil, duration: 0, videoId: query.videoId)
            if let retry = try? await LyricsManager.shared.fetchLyricsReturningProvider(query: open),
               LyricsQuality.of(retry.0) != .plain {
                (lines, provider) = retry
            }
        }
        let checked = await checkTempo(lines, query: query, knownOriginal: original, source: source)
        return (checked.lines, provider, checked.info)
    }

    /// Tempo check of a result (also used for hand-picked provider lyrics).
    static func checkTempo(_ lines: [LyricLine], query: LyricsQuery, knownOriginal: TimeInterval?,
                           source knownSource: String?) async -> (lines: [LyricLine], info: LyricsTempoInfo) {
        let played = query.duration
        var info = LyricsTempoInfo(outcome: .notNeeded, isVariant: query.isSpeedVariant, played: played)
        guard played > 0 else {
            info.outcome = lines.contains(where: { $0.startTime != nil }) ? .unknownLength : .notNeeded
            return (lines, info)
        }
        guard needsOriginalDuration(lines, played: played, isSpeedVariant: query.isSpeedVariant) else { return (lines, info) }
        var original = knownOriginal
        var source = knownSource
        if original == nil {
            (original, source) = await originalDuration(title: query.title, artist: query.artist, lines: lines)
        }
        info.original = original
        info.source = source
        let adjusted = tempoAdjusted(lines, played: played, original: original, isSpeedVariant: query.isSpeedVariant)
        info.factor = adjusted.tempo
        if adjusted.tempo != nil {
            info.outcome = .applied
        } else if let original, original > 0 {
            info.outcome = abs(played / original - 1) <= 0.02 ? .sameLength : .implausible
        } else {
            info.outcome = .noOriginal
        }
        return (adjusted.lines, info)
    }

    /// True when the result has to be checked against the original length.
    static func needsOriginalDuration(_ lines: [LyricLine], played: TimeInterval, isSpeedVariant: Bool) -> Bool {
        guard played > 0, let last = lines.compactMap(\.startTime).max() else { return false }
        return isSpeedVariant || last > played + 3
    }

    /// Pure tempo decision (unit-tested): scale by played / original when
    /// that is a plausible speed change (0.6-1.5×, more than 2 % off);
    /// timestamps that run past the song with no usable original length
    /// are dropped (plain text) rather than shown wrongly.
    static func tempoAdjusted(_ lines: [LyricLine], played: TimeInterval, original: TimeInterval?,
                              isSpeedVariant: Bool) -> (lines: [LyricLine], tempo: Double?) {
        guard played > 0, let last = lines.compactMap(\.startTime).max() else { return (lines, nil) }
        let mismatch = last > played + 3
        guard isSpeedVariant || mismatch else { return (lines, nil) }
        if let original, original > 0 {
            let factor = played / original
            if (0.6...1.5).contains(factor), abs(factor - 1) > 0.02 {
                return (LyricLine.scaled(lines, by: factor), factor)
            }
            if abs(factor - 1) <= 0.02 { return (lines, nil) }
        }
        // Can't tell how to scale: show the text without wrong timing.
        if mismatch {
            return (lines.map { LyricLine(text: $0.text, startTime: nil, backgroundText: $0.backgroundText) }, nil)
        }
        return (lines, nil)
    }

    /// Length of the ORIGINAL recording via LRCLIB search: entries whose
    /// title equals the cleaned title and that are not themselves slowed /
    /// sped-up uploads; synced ones preferred.
    /// 1. same main artist;
    /// 2. (slowed re-uploads are credited to the uploading channel, not the
    ///    artist) title only, accepted when the entry's text contains the
    ///    lyrics we got — compared in memory only, never logged.
    private static func originalDuration(title: String, artist: String, lines: [LyricLine]?) async -> (TimeInterval?, String?) {
        func norm(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
        func search(_ items: [URLQueryItem]) async -> [[String: Any]] {
            var components = URLComponents(string: "https://lrclib.net/api/search")
            components?.queryItems = items
            guard let url = components?.url,
                  let data = await LyricsRequest.get(url, timeout: 4),
                  let found = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
            return found
        }
        func duration(of item: [String: Any]?) -> TimeInterval? {
            guard let seconds = (item?["duration"] as? NSNumber)?.doubleValue, seconds > 0 else { return nil }
            return seconds
        }
        let wantedTitle = norm(title)
        let wantedArtist = norm(artist)
        func sameTitle(_ item: [String: Any]) -> Bool {
            let name = item["trackName"] as? String ?? ""
            return norm(name) == wantedTitle && !isSpeedVariant(name)
        }

        var found: (seconds: TimeInterval, source: String, artist: String)?
        let byArtist = await search([URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)])
        let candidates = byArtist.filter { item in
            let by = norm(item["artistName"] as? String ?? "")
            return sameTitle(item) && (wantedArtist.isEmpty || by.contains(wantedArtist) || wantedArtist.contains(by))
        }
        let pick = candidates.first { ($0["syncedLyrics"] as? String)?.isEmpty == false } ?? candidates.first
        if let seconds = duration(of: pick) {
            found = (seconds, "LRCLIB title+artist", pick?["artistName"] as? String ?? artist)
        } else if let lines, !lines.isEmpty {
            let byTitle = await search([URLQueryItem(name: "track_name", value: title)])
            let matching = byTitle.filter(sameTitle).compactMap { item -> (item: [String: Any], overlap: Double)? in
                let text = (item["syncedLyrics"] as? String) ?? (item["plainLyrics"] as? String) ?? ""
                let overlap = lyricsOverlap(lines, candidateText: text)
                return overlap >= 0.6 ? (item, overlap) : nil
            }
            .sorted { $0.overlap > $1.overlap }
            if let best = matching.first, let seconds = duration(of: best.item) {
                found = (seconds, String(format: "LRCLIB title+lyrics (%.0f %%)", best.overlap * 100),
                         best.item["artistName"] as? String ?? artist)
            }
        }
        guard let found else { return (nil, nil) }

        // Cross-check with the original's AUDIO track on YouTube Music (the
        // slowed upload is usually made from that master; LRCLIB lengths
        // come from other releases). Used when the two agree within 6 %.
        if let audio = await youTubeMusicAudioLength(title: title, artist: found.artist) {
            Log.player.info("LYRICS tempo original length: LRCLIB \(Int(found.seconds)) s, YouTube Music audio \(Int(audio)) s")
            if abs(audio - found.seconds) <= found.seconds * 0.06 {
                return (audio, "YouTube Music audio (\(found.source) \(Int(found.seconds)) s)")
            }
        }
        return (found.seconds, found.source)
    }

    /// Length of the original song's audio track ("Topic" / ATV) on
    /// YouTube Music — not a video version, not a slowed upload.
    private static func youTubeMusicAudioLength(title: String, artist: String) async -> TimeInterval? {
        func norm(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
        guard let json = try? await InnerTubeClient.tropShared.search(query: "\(title) \(artist)", params: nil, client: .webRemix) else { return nil }
        let wantedTitle = norm(title), wantedArtist = norm(artist)
        let songs = SearchParser.parseSearchResults(from: json).flatMap(\.items).compactMap { item -> SongItem? in
            if case .song(let song) = item { return song }
            return nil
        }
        let match = songs.first { song in
            norm(song.title) == wantedTitle && !isSpeedVariant(song.title) && song.duration > 0
                && song.musicVideoType == "MUSIC_VIDEO_TYPE_ATV"
                && song.artists.contains { norm($0.name).contains(wantedArtist) || wantedArtist.contains(norm($0.name)) }
        }
        return match.map { TimeInterval($0.duration) }
    }

    /// Share (0…1) of the first lyric lines that appear in `candidateText`
    /// (letters/digits only, case- and diacritic-insensitive).
    static func lyricsOverlap(_ lines: [LyricLine], candidateText: String) -> Double {
        func norm(_ s: String) -> String {
            s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .lowercased().filter { $0.isLetter || $0.isNumber }
        }
        let probes = lines.map { norm($0.text) }.filter { $0.count >= 6 }.prefix(8)
        guard !probes.isEmpty else { return 0 }
        let haystack = norm(candidateText)
        guard !haystack.isEmpty else { return 0 }
        return Double(probes.filter { haystack.contains($0) }.count) / Double(probes.count)
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
