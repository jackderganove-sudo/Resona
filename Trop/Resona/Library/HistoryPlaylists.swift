//
//  HistoryPlaylists.swift
//  Resona
//
//  Automatic playlists from the local play history (event table): most
//  played this month / of all time, forgotten favourites (often played,
//  not in the last 30 days) and new discoveries (first played in the last
//  14 days). Shown in the library and opened on the regular playlist page
//  (play, shuffle, download, save to YouTube Music).
//

import Foundation
import GRDB

enum HistoryPlaylistKind: String, Hashable, CaseIterable, Identifiable {
    case topMonth
    case topAllTime
    case forgotten
    case newDiscoveries

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topMonth: return "Most played this month"
        case .topAllTime: return "Most played of all time"
        case .forgotten: return "Not heard in a while"
        case .newDiscoveries: return "New discoveries"
        }
    }

    var icon: String {
        switch self {
        case .topMonth: return "calendar"
        case .topAllTime: return "crown"
        case .forgotten: return "clock.arrow.circlepath"
        case .newDiscoveries: return "sparkles"
        }
    }

    var subtitle: String {
        switch self {
        case .topMonth: return "Last 30 days"
        case .topAllTime: return "Your all-time favourites"
        case .forgotten: return "Often played, not in 30 days"
        case .newDiscoveries: return "First played in the last 14 days"
        }
    }

    /// Songs for this playlist (max. 50).
    func songs() async throws -> [SongEntity] {
        let day: TimeInterval = 24 * 3600
        let now = Date()
        let stats = """
            SELECT song_id, SUM(play_time) AS total, COUNT(*) AS plays,
                   MAX(timestamp) AS last_played, MIN(timestamp) AS first_played
            FROM event %@ GROUP BY song_id
            """
        let sql: String
        let arguments: StatementArguments
        switch self {
        case .topMonth:
            sql = "SELECT song.* FROM song JOIN (\(String(format: stats, "WHERE timestamp >= ?"))) e ON e.song_id = song.id ORDER BY e.total DESC LIMIT 50"
            arguments = [now.addingTimeInterval(-30 * day)]
        case .topAllTime:
            sql = "SELECT song.* FROM song JOIN (\(String(format: stats, ""))) e ON e.song_id = song.id ORDER BY e.total DESC LIMIT 50"
            arguments = []
        case .forgotten:
            sql = "SELECT song.* FROM song JOIN (\(String(format: stats, ""))) e ON e.song_id = song.id WHERE e.plays >= 3 AND e.last_played < ? ORDER BY e.plays DESC LIMIT 50"
            arguments = [now.addingTimeInterval(-30 * day)]
        case .newDiscoveries:
            sql = "SELECT song.* FROM song JOIN (\(String(format: stats, ""))) e ON e.song_id = song.id WHERE e.first_played >= ? ORDER BY e.total DESC LIMIT 50"
            arguments = [now.addingTimeInterval(-14 * day)]
        }
        return try await DatabaseService.shared.fetchAll(SongEntity.self, sql: sql, arguments: arguments)
    }
}
