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
