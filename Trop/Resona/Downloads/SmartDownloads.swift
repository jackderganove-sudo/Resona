//
//  SmartDownloads.swift
//  Resona
//
//  Optional (off by default): on Wi-Fi, keep the most played songs of the
//  last 30 days and the liked songs downloaded, up to a storage limit.
//  Smart downloads are tracked separately; older/lower-ranked ones are
//  removed when the limit is reached. Songs or playlists the user
//  downloaded themselves are never deleted automatically — a manual
//  download of a smart song turns it into a manual one.
//

import Foundation
import Observation

@MainActor
@Observable
final class SmartDownloadStore {
    static let shared = SmartDownloadStore()

    /// Video id → time it was smart-downloaded.
    private(set) var entries: [String: Date]
    private static let key = "resona.smartDownloads"

    private init() {
        entries = (UserDefaults.standard.dictionary(forKey: Self.key) as? [String: Date]) ?? [:]
    }

    func isSmart(_ videoId: String) -> Bool { entries[videoId] != nil }

    func mark(_ videoId: String) {
        entries[videoId] = Date()
        save()
    }

    /// Manual download (or deletion): no longer managed automatically.
    func unmark(_ videoIds: [String]) {
        var changed = false
        for id in videoIds where entries.removeValue(forKey: id) != nil { changed = true }
        if changed { save() }
    }

    private func save() {
        UserDefaults.standard.set(entries, forKey: Self.key)
    }
}

@MainActor
final class SmartDownloads {
    static let shared = SmartDownloads()

    private static let lastRunKey = "resona.smartDownloads.lastRun"
    private static let interval: TimeInterval = 4 * 3600
    /// Rough size of a song not downloaded yet (≈ 4 min at 160 kbit/s).
    private static let estimatedSongBytes: Int64 = 5 * 1024 * 1024
    private var running = false

    func refreshIfDue(force: Bool = false) {
        guard SettingsStore.shared.smartDownloadsEnabled else { return }
        let last = UserDefaults.standard.double(forKey: Self.lastRunKey)
        guard force || Date().timeIntervalSince1970 - last > Self.interval else { return }
        Task { await refresh() }
    }

    func refresh() async {
        let manager = DownloadManager.shared
        let store = SmartDownloadStore.shared
        // Wi-Fi only, always.
        guard SettingsStore.shared.smartDownloadsEnabled, !running, manager.isOnline, manager.isOnWiFi else { return }
        running = true
        defer { running = false }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastRunKey)

        let limit = Int64(SettingsStore.shared.smartDownloadsLimitGB * 1024 * 1024 * 1024)
        // Priority: most played (30 days) first, then liked (newest first).
        let top = ((try? await HistoryPlaylistKind.topMonth.songs()) ?? []).toSongItems()
        let liked = ((try? await DatabaseService.shared.fetchAllLikedSongs(sort: .recentlyAdded)) ?? []).toSongItems()
        var seen = Set<String>()
        let candidates = (top + liked).filter { seen.insert($0.videoId).inserted }

        // Sizes of existing smart downloads.
        var sizes: [String: Int64] = [:]
        for id in store.entries.keys {
            if let url = await manager.localURL(for: id),
               let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value {
                sizes[id] = size
            } else {
                store.unmark([id])   // file is gone
            }
        }

        // Walk candidates in priority order within the budget.
        var used: Int64 = 0
        var keep = Set<String>()
        var toDownload: [SongItem] = []
        for song in candidates {
            let id = song.videoId
            if manager.isDownloaded(videoId: id) {
                guard store.isSmart(id) else { continue }   // manual: not counted, never touched
                let size = sizes[id] ?? Self.estimatedSongBytes
                guard used + size <= limit else { continue }
                used += size
                keep.insert(id)
            } else {
                guard used + Self.estimatedSongBytes <= limit else { continue }
                used += Self.estimatedSongBytes
                toDownload.append(song)
            }
        }

        // Smart downloads outside the budget / no longer wanted: remove,
        // oldest first.
        let evict = store.entries.keys.filter { !keep.contains($0) }
            .sorted { (store.entries[$0] ?? .distantPast) < (store.entries[$1] ?? .distantPast) }
        if !evict.isEmpty {
            Log.downloadManager.info("Smart downloads: removing \(evict.count) song(s) over the limit")
            await manager.delete(videoIds: Array(evict))
            store.unmark(Array(evict))
        }
        if !toDownload.isEmpty {
            Log.downloadManager.info("Smart downloads: \(toDownload.count) new song(s)")
            manager.enqueue(toDownload, smart: true)
        }
    }
}
