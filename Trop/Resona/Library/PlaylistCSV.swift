//
//  PlaylistCSV.swift
//  Resona
//
//  "Export as CSV" from the playlist menu (round 10, after ArchiveTune 15):
//  title, artists, album, duration, video id and link — RFC 4180 quoting,
//  UTF-8 with BOM so Numbers and Excel open umlauts correctly.
//

import Foundation

enum PlaylistCSV {
    static let header = ["Title", "Artists", "Album", "Duration", "Video ID", "URL"]

    static func csv(for songs: [SongItem]) -> String {
        var lines = [header.map(field).joined(separator: ",")]
        for song in songs {
            let row = [
                song.title,
                song.artists.map(\.name).joined(separator: ", "),
                song.album ?? "",
                duration(song.duration),
                song.videoId,
                "https://music.youtube.com/watch?v=\(song.videoId)"
            ]
            lines.append(row.map(field).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// 245 → "4:05", 3725 → "1:02:05", 0 → "".
    static func duration(_ seconds: Int) -> String {
        guard seconds > 0 else { return "" }
        let h = seconds / 3600, m = seconds % 3600 / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// Quotes a field when it contains a comma, quote or line break.
    static func field(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Writes "<title>.csv" into a temporary folder for the share sheet.
    static func writeFile(title: String, songs: [SongItem]) throws -> URL {
        let safe = title.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("csv-export", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent((safe.isEmpty ? "Playlist" : safe) + ".csv")
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(csv(for: songs).utf8))
        try data.write(to: url, options: .atomic)
        return url
    }
}
