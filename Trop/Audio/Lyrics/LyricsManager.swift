//
//  LyricsManager.swift
//  Trop
//
//  Created by 686udjie on 16/07/2026.
//

import Foundation

@Observable
@MainActor
final class LyricsSettings {
    static let shared = LyricsSettings()

    private let orderKey = "lyricsProviderOrder"

    /// Ordered provider ids. Defaults to a sensible fallback chain.
    var providerOrder: [String] = LyricsProviderRegistry.defaultOrder

    private init() {
        if let data = UserDefaults.standard.data(forKey: orderKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data),
           !decoded.isEmpty {
            providerOrder = decoded + LyricsProviderRegistry.defaultOrder.filter { !decoded.contains($0) }
        }
    }

    func saveProviderOrder(_ order: [String]) {
        providerOrder = order
        let data = (try? JSONEncoder().encode(order)) ?? Data()
        UserDefaults.standard.set(data, forKey: orderKey)
    }
}

/// Registry of all available providers.
enum LyricsProviderRegistry {
    static let all: [LyricsProvider] = [
        BetterLyricsProvider(),
        YouLyPlusProvider(),
        LRCLIBProvider(),
        MusixmatchProvider(),
        SpotifyLyricsProvider(),
        PaxsenixProvider(),
        NeteaseProvider(),
        KugouProvider(),
        GeniusProvider(),
        SimpMusicLyricsProvider(),
        UnisonLyricsProvider(),
        QQMusicLyricsProvider(),
        MegalobizLyricsProvider(),
        DeezerLyricsProvider(),
        YouTubeMusicLyricsProvider()
    ]

    /// Word-synced sources first, YouTube Music's plain text last.
    static let defaultOrder: [String] = [
        "betterlyrics",
        "youlyplus",
        "simpmusic",
        "unison",
        "lrclib",
        "deezer",
        "musixmatch",
        "spotify",
        "paxsenix",
        "netease",
        "kugou",
        "qqmusic",
        "megalobiz",
        "genius",
        "youtube"
    ]

    static func provider(for id: String) -> LyricsProvider? {
        all.first { $0.id == id }
    }
}

actor LyricsManager {
    static let shared = LyricsManager()

    private init() {}

    struct LyricSearchResult: Identifiable {
        let id = UUID()
        let lines: [LyricLine]
        let providerName: String
        let sortOrder: Int
        var title: String? = nil
        var artist: String? = nil
        var duration: Double? = nil
        var exactVersion = false
        var score: Double = 0

        var quality: LyricsQuality { LyricsQuality.of(lines) }

        var previewText: String {
            lines.prefix(2).map(\.text).joined(separator: "\n")
        }

        var isSynced: Bool {
            lines.contains { $0.startTime != nil }
        }
    }

    func fetchLyrics(query: LyricsQuery) async throws -> [LyricLine] {
        let (lines, _) = try await fetchLyricsReturningProvider(query: query)
        return lines
    }

    /// Queries every enabled provider concurrently and returns all matches.
    func searchAll(query: LyricsQuery) async -> [LyricSearchResult] {
        let order = await LyricsSettings.shared.providerOrder
        let disabled = SettingsStore.shared.disabledLyricsProviders
        let providers = order
            .compactMap { LyricsProviderRegistry.provider(for: $0) }
            .filter { !disabled.contains($0.id) }
            .enumerated().map { ($1, $0) }

        // Every candidate of every provider (several per source), best first.
        return await withTaskGroup(of: [LyricSearchResult].self) { group in
            for (provider, index) in providers {
                group.addTask {
                    guard let candidates = try? await Self.withTimeout(seconds: 8, work: { try await provider.search(query: query) }) else { return [] }
                    return candidates.filter { !$0.lines.isEmpty }.map { candidate in
                        let lines = LyricLine.normalizedTiming(candidate.lines)
                        return LyricSearchResult(lines: lines, providerName: provider.name, sortOrder: index,
                                                 title: candidate.title, artist: candidate.artist, duration: candidate.duration,
                                                 exactVersion: candidate.exactVersion,
                                                 score: Self.score(quality: LyricsQuality.of(lines), order: index, candidate: candidate, query: query))
                    }
                }
            }
            var results: [LyricSearchResult] = []
            for await batch in group { results += batch }
            return results.sorted { $0.score > $1.score }
        }
    }

    /// Ranking: quality (word > line > text) first; a synced result for
    /// exactly this upload (video id) beats the original's lyrics of the
    /// same quality — and for remixes / edits / slowed even word-synced
    /// ones; title naming the version, matching duration and artist add a
    /// little; the user's order breaks ties.
    static func score(quality: LyricsQuality, order: Int, candidate: LyricsCandidate, query: LyricsQuery) -> Double {
        var score = Double(quality.rawValue) * 10 - Double(order) * 0.01
        if candidate.exactVersion {
            // Remix / edit / slowed: the original's lyrics are likely wrong.
            let variant = query.versionHint != nil || query.isSpeedVariant
            score += quality == .plain ? 2 : (variant ? 12 : 6)
        }
        func norm(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " } }
        if let hint = query.versionHint, let title = candidate.title {
            let words = norm(hint).split(separator: " ").filter { $0.count >= 3 && !["remix", "edit", "mix", "version"].contains($0) }
            let candidateTitle = norm(title)
            if !words.isEmpty, words.allSatisfy({ candidateTitle.contains($0) }) {
                score += 8   // e.g. "… (NovaX Remix)"
            } else if candidateTitle.contains("remix") || candidateTitle.contains("edit") {
                score += 2
            }
        }
        if let duration = candidate.duration, duration > 0, query.duration > 0 {
            let difference = abs(duration - query.duration)
            if difference <= 3 { score += 2 } else if difference > 15 { score -= 6 }
        }
        if let artist = candidate.artist, !query.artist.isEmpty,
           norm(artist).contains(norm(query.artist)) || norm(query.artist).contains(norm(artist)) {
            score += 2
        }
        return score
    }

    private struct ProviderHit: Sendable {
        let order: Int
        let lines: [LyricLine]
        let providerName: String
        let quality: LyricsQuality
        let score: Double
    }

    /// Per-provider time budget; slower providers are simply skipped.
    static let providerTimeout: Double = 4

    /// Asks every enabled provider in parallel (4 s budget each) and picks
    /// the best result by quality — word-synced > line-synced > plain —
    /// and, within the same quality, by the user's provider order. Synced
    /// results whose timestamps run past the song (wrong version/match)
    /// are dropped.
    func fetchLyricsReturningProvider(query: LyricsQuery) async throws -> ([LyricLine], providerName: String?) {
        let order = await LyricsSettings.shared.providerOrder
        let disabled = SettingsStore.shared.disabledLyricsProviders
        let candidates: [(index: Int, provider: LyricsProvider)] = order.enumerated().compactMap { index, id in
            guard !disabled.contains(id), let provider = LyricsProviderRegistry.provider(for: id) else { return nil }
            return (index, provider)
        }
        guard !candidates.isEmpty else { throw LyricsError.notFound }

        let results = await withTaskGroup(of: ProviderHit?.self) { group in
            for (index, provider) in candidates {
                group.addTask {
                    do {
                        let candidates = try await Self.withTimeout(seconds: Self.providerTimeout) {
                            try await provider.search(query: query)
                        }
                        // Best plausible candidate of this provider.
                        let hits: [ProviderHit] = candidates.compactMap { candidate in
                            let lines = LyricLine.normalizedTiming(candidate.lines)
                            guard !lines.isEmpty, Self.plausible(lines, duration: query.duration) else { return nil }
                            let quality = LyricsQuality.of(lines)
                            return ProviderHit(order: index, lines: lines, providerName: provider.name, quality: quality,
                                               score: Self.score(quality: quality, order: index, candidate: candidate, query: query))
                        }
                        return hits.max { $0.score < $1.score }
                    } catch {
                        return nil
                    }
                }
            }
            var collected: [ProviderHit] = []
            for await item in group {
                guard let item else { continue }
                collected.append(item)
                // Unbeatable: word-synced lyrics for exactly this upload.
                if item.quality == .wordSynced, item.score >= 26 {
                    group.cancelAll()
                    break
                }
            }
            return collected
        }
        guard let best = results.max(by: { $0.score < $1.score }) else {
            throw LyricsError.notFound
        }
        return (best.lines, best.providerName)
    }

    /// Synced lyrics must fit the song: the last timestamp may not lie
    /// beyond its end (±3 s tolerance).
    static func plausible(_ lines: [LyricLine], duration: TimeInterval) -> Bool {
        guard duration > 0, let last = lines.compactMap(\.startTime).max() else { return true }
        return last <= duration + 3
    }

    private static func withTimeout<T: Sendable>(seconds: Double, work: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw LyricsError.notFound
            }
            guard let first = try await group.next() else {
                group.cancelAll()
                throw LyricsError.notFound
            }
            group.cancelAll()
            return first
        }
    }
}
