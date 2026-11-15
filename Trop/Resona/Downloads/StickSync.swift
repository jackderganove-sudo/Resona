//
//  StickSync.swift
//  Resona
//
//  PS5 stick on the iPad (round 12, prepared, behind a switch until the PS5
//  cover test): the same layout and manifest as Resona-Android — chosen
//  playlists as Music/<Playlist>/<Nr> - <Artist> - <Title>.m4a, manifest
//  Music/.resona-sync.json with a format version, FAT32-safe names, only
//  files the manifest knows are moved or deleted. The stick is picked with
//  the document picker (security-scoped bookmark), sync is manual.
//

import Foundation
import GRDB

enum StickFileNames {
    private static let forbidden = CharacterSet(charactersIn: "\\/:*?\"<>|").union(.controlCharacters)
    private static let reserved = ["CON", "PRN", "AUX", "NUL"] + (1...9).flatMap { ["COM\($0)", "LPT\($0)"] }

    /// Same rules as Android's ResonaFileNames.safe.
    static func safe(_ name: String, maxLength: Int = 80) -> String {
        var out = name.precomposedStringWithCanonicalMapping
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        out = String(out.unicodeScalars.map { forbidden.contains($0) ? "_" : Character($0) })
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        if out.utf16.count > maxLength {
            var cut = ""
            for ch in out where (cut + String(ch)).utf16.count <= maxLength { cut.append(ch) }
            out = cut.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        }
        if out.isEmpty { out = "_" }
        if reserved.contains(out.uppercased()) { out += "_" }
        return out
    }

    static func song(number: Int?, artist: String, title: String, ext: String = "m4a") -> String {
        var parts: [String] = []
        if let number { parts.append(String(format: "%02d", number)) }
        if !artist.trimmingCharacters(in: .whitespaces).isEmpty { parts.append(safe(artist, maxLength: 60)) }
        parts.append(safe(title, maxLength: 90))
        return safe(parts.joined(separator: " - "), maxLength: 160) + "." + ext
    }

    /// Case-insensitive, as FAT32 compares names.
    static func unique(_ name: String, taken: Set<String>) -> String {
        let lower = Set(taken.map { $0.lowercased() })
        guard lower.contains(name.lowercased()) else { return name }
        let dot = name.lastIndex(of: ".") ?? name.endIndex
        let stem = String(name[..<dot]), ext = String(name[dot...])
        var n = 2
        while lower.contains("\(stem) (\(n))\(ext)".lowercased()) { n += 1 }
        return "\(stem) (\(n))\(ext)"
    }
}

/// Manifest in the same JSON format as Android (version, songs, folders, playlists).
struct StickManifest: Codable, Equatable {
    struct Song: Codable, Equatable {
        var path: String
        var size: Int64 = 0
        var title: String = ""
        var artist: String = ""
        var format: Int = 0

        init(path: String, size: Int64 = 0, title: String = "", artist: String = "", format: Int = 0) {
            self.path = path; self.size = size; self.title = title; self.artist = artist; self.format = format
        }

        // Android (kotlinx) leaves default values out of the JSON.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            path = try c.decode(String.self, forKey: .path)
            size = try c.decodeIfPresent(Int64.self, forKey: .size) ?? 0
            title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
            artist = try c.decodeIfPresent(String.self, forKey: .artist) ?? ""
            format = try c.decodeIfPresent(Int.self, forKey: .format) ?? 0
        }
    }

    init(version: Int = 1, songs: [String: Song] = [:], folders: [String: String] = [:], playlists: [String: [String]] = [:]) {
        self.version = version; self.songs = songs; self.folders = folders; self.playlists = playlists
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        songs = try c.decodeIfPresent([String: Song].self, forKey: .songs) ?? [:]
        folders = try c.decodeIfPresent([String: String].self, forKey: .folders) ?? [:]
        playlists = try c.decodeIfPresent([String: [String]].self, forKey: .playlists) ?? [:]
    }

    var version = 1
    var songs: [String: Song] = [:]
    var folders: [String: String] = [:]
    var playlists: [String: [String]] = [:]

    /// iPad files (ffmpeg, "M4A " brand, stco, JPEG cover) already have Android's format 2.
    static let currentFormat = 2

    static func decode(_ data: Data?) -> StickManifest {
        guard let data, let m = try? JSONDecoder().decode(StickManifest.self, from: data) else { return StickManifest() }
        return m
    }

    func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }
}

enum StickStep: Equatable {
    case add(songId: String, path: String)
    case move(songId: String, from: String, to: String)
    case delete(songId: String, path: String)
    case renameFolder(playlistId: String, from: String, to: String)
    case deleteFolder(playlistId: String, folder: String)
}

/// Port of Android's ResonaFilePlan for the stick (one copy per playlist).
enum StickPlan {
    struct Playlist { let id: String; let name: String; let songIds: [String] }
    struct SongInfo { let title: String; let artist: String }

    static func plan(old: StickManifest, playlists: [Playlist], info: (String) -> SongInfo?) -> ([StickStep], StickManifest) {
        var steps: [StickStep] = []
        var folders: [String: String] = [:]
        var takenFolders = Set<String>()
        for p in playlists {
            let name = StickFileNames.unique(StickFileNames.safe(p.name), taken: takenFolders)
            takenFolders.insert(name)
            folders[p.id] = name
        }
        var deleted = Set<String>()
        var renamed: [String: String] = [:]
        for (id, oldName) in old.folders {
            if let newName = folders[id] {
                if newName != oldName { steps.append(.renameFolder(playlistId: id, from: oldName, to: newName)); renamed[oldName] = newName }
            } else {
                steps.append(.deleteFolder(playlistId: id, folder: oldName)); deleted.insert(oldName)
            }
        }
        var wanted: [(key: String, path: String)] = []
        var takenNames: [String: Set<String>] = [:]
        for p in playlists {
            let folder = folders[p.id]!
            var seen = Set<String>()
            for (index, songId) in p.songIds.enumerated() where !seen.contains(songId) {
                seen.insert(songId)
                guard let song = info(songId) else { continue }
                let name = StickFileNames.unique(StickFileNames.song(number: index + 1, artist: song.artist, title: song.title),
                                                 taken: takenNames[folder, default: []])
                takenNames[folder, default: []].insert(name)
                wanted.append(("\(p.id)/\(songId)", "\(folder)/\(name)"))
            }
        }
        let wantedPaths = Dictionary(wanted.map { ($0.key, $0.path) }, uniquingKeysWith: { a, _ in a })
        func afterRename(_ path: String) -> String {
            guard let slash = path.firstIndex(of: "/") else { return path }
            let folder = String(path[..<slash])
            return renamed[folder].map { $0 + path[slash...] } ?? path
        }
        var songs: [String: StickManifest.Song] = [:]
        var deletes: [StickStep] = [], moves: [StickStep] = [], adds: [StickStep] = []
        for (key, song) in old.songs {
            let path = afterRename(song.path)
            let songId = String(key.split(separator: "/").last ?? "")
            if let target = wantedPaths[key] {
                var moved = song
                moved.path = target
                if target != path { moves.append(.move(songId: songId, from: path, to: target)) }
                if song.format < StickManifest.currentFormat, target == path { adds.append(.add(songId: songId, path: target)) }
                songs[key] = moved
            } else if !deleted.contains(String(song.path.split(separator: "/").first ?? "")) {
                deletes.append(.delete(songId: songId, path: path))
            }
        }
        for (key, path) in wanted where songs[key] == nil {
            let songId = String(key.split(separator: "/").last ?? "")
            adds.append(.add(songId: songId, path: path))
            let song = info(songId)
            songs[key] = StickManifest.Song(path: path, title: song?.title ?? "", artist: song?.artist ?? "")
        }
        let renames = steps.filter { if case .renameFolder = $0 { return true } else { return false } }
        let dropFolders = steps.filter { if case .deleteFolder = $0 { return true } else { return false } }
        let manifest = StickManifest(songs: songs, folders: folders,
                                     playlists: Dictionary(uniqueKeysWithValues: playlists.map { ($0.id, $0.songIds) }))
        return (renames + deletes + moves + dropFolders + adds, manifest)
    }
}

/// Manual sync with a stick picked in the document picker (bookmark kept).
@MainActor
final class StickSync {
    static let shared = StickSync()
    static let enabledKey = "resona.ps5Stick.enabled"
    private let bookmarkKey = "resona.ps5Stick.bookmark"
    private let playlistsKey = "resona.ps5Stick.playlists"

    var selectedPlaylists: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: playlistsKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: playlistsKey) }
    }

    func remember(stick url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        if let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        }
    }

    var stickURL: URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        return try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    /// Copies the chosen playlists' downloaded files; missing downloads are skipped (counted).
    func sync(allowDrop: Bool, progress: @escaping (Int, Int) -> Void) async throws -> (copied: Int, missing: Int) {
        guard let root = stickURL else { throw CocoaError(.fileNoSuchFile) }
        guard root.startAccessingSecurityScopedResource() else { throw CocoaError(.fileReadNoPermission) }
        defer { root.stopAccessingSecurityScopedResource() }
        let fm = FileManager.default
        let music = root.appendingPathComponent("Music", isDirectory: true)
        try fm.createDirectory(at: music, withIntermediateDirectories: true)
        let manifestURL = music.appendingPathComponent(".resona-sync.json")
        let old = StickManifest.decode(try? Data(contentsOf: manifestURL))

        let selected = selectedPlaylists
        let rows: [(String, String, String, String, String?)] = try await DatabaseService.shared.read { db in
            try Row.fetchAll(db, sql: """
                SELECT p.id AS pid, p.name AS pname, m.song_id AS sid, s.title AS title, s.artist_name AS artist
                FROM playlist p JOIN playlist_song_map m ON m.playlist_id = p.id JOIN song s ON s.id = m.song_id
                ORDER BY p.id, m.position
                """).map { row -> (String, String, String, String, String?) in
                    (row["pid"], row["pname"], row["sid"], row["title"], row["artist"])
                }
        }
        var order: [String] = []
        var byPlaylist: [String: (name: String, songs: [String])] = [:]
        var infos: [String: StickPlan.SongInfo] = [:]
        for (pid, name, sid, title, artist) in rows where selected.contains(pid) {
            if byPlaylist[pid] == nil { order.append(pid); byPlaylist[pid] = (name, []) }
            byPlaylist[pid]!.songs.append(sid)
            infos[sid] = StickPlan.SongInfo(title: title, artist: artist ?? "")
        }
        let playlists = order.map { StickPlan.Playlist(id: $0, name: byPlaylist[$0]!.name, songIds: byPlaylist[$0]!.songs) }
        var (steps, manifest) = StickPlan.plan(old: old, playlists: playlists, info: { infos[$0] })
        if !allowDrop {
            steps.removeAll { if case .deleteFolder = $0 { return true } else { return false } }
            for (key, song) in old.songs where manifest.songs[key] == nil && !playlists.contains(where: { key.hasPrefix($0.id + "/") }) {
                manifest.songs[key] = song
            }
            for (id, folder) in old.folders where manifest.folders[id] == nil { manifest.folders[id] = folder }
        }
        func finishMoves() {
            for case .move(_, let from, let to) in steps {
                let target = music.appendingPathComponent(to)
                try? fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fm.moveItem(at: music.appendingPathComponent(from + ".resona-move"), to: target)
            }
        }
        var movesFinished = false
        let total = steps.filter { if case .add = $0 { return true } else { return false } }.count
        var copied = 0, missing = 0, done = 0
        for step in steps {
            try Task.checkCancellation()
            switch step {
            case .renameFolder(_, let from, let to):
                try? fm.moveItem(at: music.appendingPathComponent(from), to: music.appendingPathComponent(to))
            case .deleteFolder(_, let folder):
                for song in old.songs.values where song.path.hasPrefix(folder + "/") {
                    try? fm.removeItem(at: music.appendingPathComponent(song.path))
                }
                let dir = music.appendingPathComponent(folder)
                if (try? fm.contentsOfDirectory(atPath: dir.path))?.isEmpty == true { try? fm.removeItem(at: dir) }
            case .delete(_, let path):
                try? fm.removeItem(at: music.appendingPathComponent(path))
            case .move(_, let from, _):
                // Two phases, so renumbering (01 ↔ 02) never hits a file that is still there.
                try? fm.moveItem(at: music.appendingPathComponent(from), to: music.appendingPathComponent(from + ".resona-move"))
            case .add(let songId, let path):
                if !movesFinished { finishMoves(); movesFinished = true }
                done += 1
                progress(done, total)
                guard let source = await DownloadManager.shared.localURL(for: songId) else {
                    missing += 1
                    manifest.songs = manifest.songs.filter { $0.value.path != path }
                    continue
                }
                let target = music.appendingPathComponent(path)
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fm.removeItem(at: target)
                try fm.copyItem(at: source, to: target)
                if let key = manifest.songs.first(where: { $0.value.path == path })?.key {
                    manifest.songs[key]?.format = StickManifest.currentFormat
                    manifest.songs[key]?.size = (try? fm.attributesOfItem(atPath: target.path)[.size] as? Int64) ?? 0
                }
                copied += 1
            }
        }
        if !movesFinished { finishMoves() }
        try manifest.encoded().write(to: manifestURL, options: .atomic)
        return (copied, missing)
    }
}
