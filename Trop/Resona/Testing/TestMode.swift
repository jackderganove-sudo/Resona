//
//  TestMode.swift
//  Resona
//
//  Launch-argument switches for automated simulator runs (GitHub Actions):
//  • -ResonaUITest            mpv uses ao=null (CI simulators have no
//                             reliable audio device); playback still runs
//                             in real time.
//                             DEBUG: songs play a local test tone instead
//                             of the YouTube stream (CI IPs get a bot check).
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

    /// 5-minute quiet test tone played instead of YouTube streams in UI
    /// tests (created once per launch).
    nonisolated static let uiTestToneURL: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ui-test-tone.wav")
        writeSine(to: url, frequency: 330, seconds: 300, rate: 8_000, amplitude: 0.2)
        return url
    }()

    /// 16-bit mono sine WAV.
    nonisolated static func writeSine(to url: URL, frequency: Double, seconds: Double,
                                      rate: Int = 44_100, amplitude: Double = 0.5) {
        let count = Int(Double(rate) * seconds)
        var data = Data()
        func append<T>(_ value: T) { withUnsafeBytes(of: value) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + count * 2).littleEndian)
        data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16).littleEndian)
        append(UInt16(1).littleEndian); append(UInt16(1).littleEndian)
        append(UInt32(rate).littleEndian); append(UInt32(rate * 2).littleEndian)
        append(UInt16(2).littleEndian); append(UInt16(16).littleEndian)
        data.append(contentsOf: Array("data".utf8)); append(UInt32(count * 2).littleEndian)
        var samples = [Int16](repeating: 0, count: count)
        for i in 0..<count {
            samples[i] = Int16(amplitude * 32767 * sin(2 * Double.pi * frequency * Double(i) / Double(rate)))
        }
        samples.withUnsafeBytes { data.append(contentsOf: $0) }
        try? data.write(to: url)
    }
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
