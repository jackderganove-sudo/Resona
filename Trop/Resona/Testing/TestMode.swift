//
//  TestMode.swift
//  Resona
//
//  Launch-argument switches for automated simulator runs (GitHub Actions):
//  • -ResonaUITest            mpv uses ao=null (CI simulators have no
//                             reliable audio device); playback still runs
//                             in real time.
//  • -ResonaCrossfadeTest X   DEBUG-only crossfade measurement (see
//                             CrossfadeTestHarness), implies ao=null.
//

import Foundation

enum TestMode {
    nonisolated static let arguments = ProcessInfo.processInfo.arguments

    nonisolated static var isUITest: Bool { arguments.contains("-ResonaUITest") }

    /// Crossfade measurement case ("fade3", "fade10", "skip", "pause", "off").
    nonisolated static var crossfadeCase: String? {
        guard let index = arguments.firstIndex(of: "-ResonaCrossfadeTest"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// mpv without a real audio device (still real-time).
    nonisolated static var useNullAudio: Bool { isUITest || crossfadeCase != nil }

    #if DEBUG
    /// Local files standing in for songs (crossfade test).
    nonisolated(unsafe) static var localOverride: [String: URL] = [:]
    #endif
}

#if DEBUG
import GRDB

extension DatabaseService {
    /// Removes rows the unit tests inserted (ids with `prefix`).
    func deleteTestRows(prefix: String) async {
        let pattern = prefix + "%"
        try? await dbPool.write { db in
            try db.execute(sql: "DELETE FROM event WHERE song_id LIKE ?", arguments: [pattern])
            try db.execute(sql: "DELETE FROM playlist_song_map WHERE playlist_id LIKE ? OR song_id LIKE ?", arguments: [pattern, pattern])
            try db.execute(sql: "DELETE FROM song WHERE id LIKE ?", arguments: [pattern])
        }
    }
}
#endif
