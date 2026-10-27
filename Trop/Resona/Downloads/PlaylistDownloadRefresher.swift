//
//  PlaylistDownloadRefresher.swift
//  Resona
//
//  Keeps playlists the user downloaded up to date: songs added on YouTube
//  Music are downloaded automatically, and — only with the global switch —
//  songs removed from the playlist are deleted locally.
//
//  Runs when the app opens or comes back to the foreground, at most every
//  4 hours (background refresh is unreliable on iOS and ffmpeg downloads
//  don't continue in the background anyway). Respects "Wi-Fi only".
//  Never downloads playlists the user didn't download themselves.
//

import Foundation
import Observation

/// Playlists downloaded via the header download button.
@MainActor
@Observable
final class DownloadedPlaylistStore {
    static let shared = DownloadedPlaylistStore()

    struct Entry: Codable, Equatable {
        let id: String
        var title: String
        /// Song ids at the last refresh (to find removals).
        var songIds: [String]
    }

    private(set) var entries: [String: Entry]
    private static let key = "resona.downloadedPlaylists"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded
        } else {
            entries = [:]
        }
    }

    func register(id: String, title: String, songIds: [String]) {
        entries[id] = Entry(id: id, title: title, songIds: songIds)
        save()
    }

    func unregister(id: String) {
        entries.removeValue(forKey: id)
        save()
    }

    func update(_ entry: Entry) {
        entries[entry.id] = entry
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

@MainActor
final class PlaylistDownloadRefresher {
    static let shared = PlaylistDownloadRefresher()

    private static let lastRunKey = "resona.downloadedPlaylists.lastRefresh"
    private static let interval: TimeInterval = 4 * 3600
    private var running = false

    /// Foreground / launch: at most every 4 h.
    func refreshIfDue() {
        let last = UserDefaults.standard.double(forKey: Self.lastRunKey)
        guard Date().timeIntervalSince1970 - last > Self.interval else { return }
        Task { await refresh() }
    }

    func refresh() async {
        let store = DownloadedPlaylistStore.shared
        let manager = DownloadManager.shared
        guard !running, !store.entries.isEmpty, manager.isOnline else { return }
        guard !SettingsStore.shared.wifiOnlyDownloads || manager.isOnWiFi else { return }
        running = true
        defer { running = false }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastRunKey)

        var current: [String: [SongItem]] = [:]
        for entry in store.entries.values {
            guard let songs = await Self.fetchSongs(playlistId: entry.id) else { continue }
            current[entry.id] = songs
        }

        for (id, songs) in current {
            guard var entry = store.entries[id] else { continue }
            // New songs → existing download queue (the playlist's download
            // button shows the ring while they load, then the check mark).
            let missing = songs.filter { !manager.isDownloaded(videoId: $0.videoId) }
            if !missing.isEmpty {
                Log.downloadManager.info("Playlist refresh \(entry.title): \(missing.count) new song(s)")
                manager.enqueue(missing)
            }
            // Removed songs: only with the switch, and only if no other
            // downloaded playlist still contains them.
            let nowIds = Set(songs.map(\.videoId))
            let removed = entry.songIds.filter { !nowIds.contains($0) }
            if SettingsStore.shared.removeDeletedPlaylistSongs, !removed.isEmpty {
                let elsewhere = Set(current.filter { $0.key != id }.values.flatMap { $0.map(\.videoId) })
                let deletable = removed.filter { !elsewhere.contains($0) }
                if !deletable.isEmpty { await manager.delete(videoIds: deletable) }
            }
            entry.songIds = songs.map(\.videoId)
            store.update(entry)
        }
    }

    private static func fetchSongs(playlistId: String) async -> [SongItem]? {
        guard let (firstPage, rows) = try? await SyncBridge.playlistDetail.fetchPlaylistRows(playlistId: playlistId) else { return nil }
        let info = PlaylistDetailViewModel.parsePlaylistDetail(firstPage: firstPage, rows: rows, playlistId: playlistId)
        return info.songs.isEmpty ? nil : info.songs
    }
}
