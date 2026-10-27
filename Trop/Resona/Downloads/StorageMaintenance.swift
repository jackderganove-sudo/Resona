//
//  StorageMaintenance.swift
//  Resona
//
//  Sizes and clearing of the app's caches (Settings → Storage) and
//  "delete all downloads".
//

import Foundation
import Nuke

enum StorageMaintenance {
    enum Area: CaseIterable, Identifiable {
        case images, lyrics, streams
        var id: Self { self }
    }

    private static var caches: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    }

    /// Bytes on disk for an area (streams live in memory → nil).
    static func size(of area: Area) async -> Int64? {
        await Task.detached(priority: .utility) { () -> Int64? in
            guard let caches else { return nil }
            switch area {
            case .images: return directorySize(caches.appendingPathComponent("com.trop.nuke"))
            case .lyrics: return directorySize(caches.appendingPathComponent("lyrics-v2"))
            case .streams: return nil
            }
        }.value
    }

    static func clear(_ area: Area) async {
        switch area {
        case .images:
            ImagePipeline.shared.cache.removeAll()
            if let dir = caches?.appendingPathComponent("com.trop.nuke") { removeContents(of: dir) }
            await MainActor.run { BlurredImageCache.shared.removeAll() }
        case .lyrics:
            if let dir = caches?.appendingPathComponent("lyrics-v2") { removeContents(of: dir) }
            await LyricsService.shared.clearMemoryCache()
        case .streams:
            await StreamCache.shared.clear()
            await CanvasRepository.shared.clear()
        }
    }

    @MainActor
    static func deleteAllDownloads() async {
        let manager = DownloadManager.shared
        await manager.delete(videoIds: manager.tracks.map(\.id))
        for id in DownloadedPlaylistStore.shared.entries.keys {
            DownloadedPlaylistStore.shared.unregister(id: id)
        }
    }

    private static func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
        return total
    }

    private static func removeContents(of url: URL) {
        guard let items = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else { return }
        for item in items { try? FileManager.default.removeItem(at: item) }
    }
}
