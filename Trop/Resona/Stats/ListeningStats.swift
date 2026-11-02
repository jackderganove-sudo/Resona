//
//  ListeningStats.swift
//  Resona
//
//  Listening statistics from the play events (round 10, after ArchiveTune
//  15's stats and Year in Music): minutes, plays, top songs / artists /
//  albums, hours of the day, weekdays and the longest streak. "Reset"
//  does not delete anything: it only moves the start date, so history and
//  recommendations keep working.
//

import Foundation
import GRDB

enum StatsPeriod: String, CaseIterable, Identifiable, Sendable {
    case week, month, year, allTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: return String(localized: "7 days")
        case .month: return String(localized: "30 days")
        case .year: return String(localized: "This year")
        case .allTime: return String(localized: "All time")
        }
    }

    func start(now: Date = Date(), calendar: Calendar = .current) -> Date {
        switch self {
        case .week: return calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .month: return calendar.date(byAdding: .day, value: -30, to: now) ?? now
        case .year: return calendar.dateInterval(of: .year, for: now)?.start ?? now
        case .allTime: return .distantPast
        }
    }
}

struct StatsPlay: Sendable, Hashable {
    var songId: String
    var title: String
    var artist: String
    var album: String?
    var thumbnailUrl: String?
    var timestamp: Date
    /// Milliseconds actually listened.
    var playTime: Int64
}

struct RankedEntry: Identifiable, Sendable, Hashable {
    var id: String
    var title: String
    var subtitle: String?
    var thumbnailUrl: String?
    var plays: Int
    var minutes: Int
}

struct ListeningStats: Sendable, Equatable {
    var totalMinutes = 0
    var plays = 0
    var distinctSongs = 0
    var distinctArtists = 0
    var topSongs: [RankedEntry] = []
    var topArtists: [RankedEntry] = []
    var topAlbums: [RankedEntry] = []
    /// Minutes per hour of the day (0…23).
    var hours: [Int] = Array(repeating: 0, count: 24)
    /// Minutes per weekday, Monday first.
    var weekdays: [Int] = Array(repeating: 0, count: 7)
    var longestStreakDays = 0
    var firstPlay: Date?

    var isEmpty: Bool { plays == 0 }

    var peakHour: Int? {
        guard let max = hours.max(), max > 0 else { return nil }
        return hours.firstIndex(of: max)
    }

    /// Short listening type from the peak hour.
    var listenerType: String? {
        guard let hour = peakHour else { return nil }
        switch hour {
        case 5..<11: return String(localized: "Early bird")
        case 11..<17: return String(localized: "Daytime listener")
        case 17..<22: return String(localized: "Evening listener")
        default: return String(localized: "Night owl")
        }
    }

    /// Plays shorter than 30 s count neither as play nor in the rankings
    /// (skips), only in the minutes.
    static let minimumPlayMs: Int64 = 30_000

    static func compute(_ plays: [StatsPlay], calendar: Calendar = .current, top: Int = 10) -> ListeningStats {
        var stats = ListeningStats()
        guard !plays.isEmpty else { return stats }
        var songAgg: [String: (entry: StatsPlay, plays: Int, ms: Int64)] = [:]
        var artistAgg: [String: (name: String, art: String?, plays: Int, ms: Int64)] = [:]
        var albumAgg: [String: (name: String, artist: String, art: String?, plays: Int, ms: Int64)] = [:]
        var hourMs = Array(repeating: Int64(0), count: 24)
        var weekdayMs = Array(repeating: Int64(0), count: 7)
        var days = Set<Date>()
        var totalMs: Int64 = 0

        for play in plays {
            let ms = max(0, play.playTime)
            totalMs += ms
            let hour = calendar.component(.hour, from: play.timestamp)
            hourMs[hour] += ms
            // Calendar weekday: 1 = Sunday → index 6; 2 = Monday → 0.
            let weekday = (calendar.component(.weekday, from: play.timestamp) + 5) % 7
            weekdayMs[weekday] += ms
            days.insert(calendar.startOfDay(for: play.timestamp))
            stats.firstPlay = min(stats.firstPlay ?? play.timestamp, play.timestamp)
            guard ms >= minimumPlayMs else { continue }
            stats.plays += 1

            let song = songAgg[play.songId]
            songAgg[play.songId] = (song?.entry ?? play, (song?.plays ?? 0) + 1, (song?.ms ?? 0) + ms)

            let artistName = play.artist.trimmingCharacters(in: .whitespaces)
            if !artistName.isEmpty {
                let key = artistName.lowercased()
                let artist = artistAgg[key]
                artistAgg[key] = (artist?.name ?? artistName, artist?.art ?? play.thumbnailUrl, (artist?.plays ?? 0) + 1, (artist?.ms ?? 0) + ms)
            }
            if let albumName = play.album?.trimmingCharacters(in: .whitespaces), !albumName.isEmpty {
                let key = albumName.lowercased() + "|" + artistName.lowercased()
                let album = albumAgg[key]
                albumAgg[key] = (album?.name ?? albumName, album?.artist ?? artistName, album?.art ?? play.thumbnailUrl,
                                 (album?.plays ?? 0) + 1, (album?.ms ?? 0) + ms)
            }
        }

        func minutes(_ ms: Int64) -> Int { Int((Double(ms) / 60_000).rounded()) }
        stats.totalMinutes = minutes(totalMs)
        stats.hours = hourMs.map(minutes)
        stats.weekdays = weekdayMs.map(minutes)
        stats.distinctSongs = songAgg.count
        stats.distinctArtists = artistAgg.count
        stats.topSongs = songAgg
            .sorted { ($0.value.plays, $0.value.ms) > ($1.value.plays, $1.value.ms) }
            .prefix(top)
            .map { RankedEntry(id: $0.key, title: $0.value.entry.title, subtitle: $0.value.entry.artist,
                               thumbnailUrl: $0.value.entry.thumbnailUrl, plays: $0.value.plays, minutes: minutes($0.value.ms)) }
        stats.topArtists = artistAgg
            .sorted { ($0.value.ms, $0.value.plays) > ($1.value.ms, $1.value.plays) }
            .prefix(top)
            .map { RankedEntry(id: $0.key, title: $0.value.name, subtitle: nil, thumbnailUrl: $0.value.art,
                               plays: $0.value.plays, minutes: minutes($0.value.ms)) }
        stats.topAlbums = albumAgg
            .sorted { ($0.value.ms, $0.value.plays) > ($1.value.ms, $1.value.plays) }
            .prefix(top)
            .map { RankedEntry(id: $0.key, title: $0.value.name, subtitle: $0.value.artist, thumbnailUrl: $0.value.art,
                               plays: $0.value.plays, minutes: minutes($0.value.ms)) }
        stats.longestStreakDays = longestStreak(days, calendar: calendar)
        return stats
    }

    static func longestStreak(_ days: Set<Date>, calendar: Calendar = .current) -> Int {
        let sorted = days.sorted()
        var best = 0, current = 0
        var previous: Date?
        for day in sorted {
            if let previous, let next = calendar.date(byAdding: .day, value: 1, to: previous),
               calendar.isDate(next, inSameDayAs: day) {
                current += 1
            } else {
                current = 1
            }
            best = max(best, current)
            previous = day
        }
        return best
    }
}

// MARK: - Store

@MainActor
@Observable
final class ListeningStatsStore {
    static let shared = ListeningStatsStore()
    static let resetKey = "resona.stats.resetDate"

    private(set) var stats = ListeningStats()
    private(set) var isLoading = false
    var period: StatsPeriod = .month

    private init() {}

    /// Stats only count plays after this date ("Reset statistics").
    var resetDate: Date? {
        get {
            let value = UserDefaults.standard.double(forKey: Self.resetKey)
            return value > 0 ? Date(timeIntervalSince1970: value) : nil
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: Self.resetKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.resetKey)
            }
        }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        stats = await Self.compute(period: period, reset: resetDate)
    }

    func reset() async {
        resetDate = Date()
        await load()
    }

    func undoReset() async {
        resetDate = nil
        await load()
    }

    nonisolated static func compute(period: StatsPeriod, reset: Date?) async -> ListeningStats {
        var since = period.start()
        if let reset, reset > since { since = reset }
        let plays = (try? await DatabaseService.shared.fetchStatsPlays(since: since)) ?? []
        return ListeningStats.compute(plays)
    }
}

extension DatabaseService {
    /// Every play since `since`, joined with its song (title, artist, album).
    func fetchStatsPlays(since: Date) async throws -> [StatsPlay] {
        try await dbPool.read { db in
            let events = try Event
                .filter(Column("timestamp") >= since)
                .order(Column("timestamp").asc)
                .fetchAll(db)
            guard !events.isEmpty else { return [] }
            let songs = try Self.fetchSongMapByIds(Array(Set(events.map(\.songId))), db: db)
            return events.compactMap { event in
                guard let song = songs[event.songId], !song.isEpisode else { return nil }
                return StatsPlay(songId: event.songId, title: song.title, artist: song.artistName ?? "",
                                 album: song.albumName, thumbnailUrl: song.thumbnailUrl,
                                 timestamp: event.timestamp, playTime: event.playTime)
            }
        }
    }
}
