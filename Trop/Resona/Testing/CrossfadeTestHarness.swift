//
//  CrossfadeTestHarness.swift
//  Resona
//
//  DEBUG-only measurement of the real crossfade engine in the simulator.
//  Launched with `-ResonaCrossfadeTest <case>`:
//    fade3 / fade10   crossfade 3 s / 10 s between two songs
//    skip             manual "next" in the middle of a 3 s fade
//    pause            pause for 2 s in the middle of a 3 s fade
//    off              crossfade off (normal song change)
//  Three 60 s sine tones (440 / 660 / 880 Hz) are generated as WAV files
//  and played through the normal queue/playback path (mpv ao=null, real
//  time). Every 10 ms position, volume, pause/idle and file of BOTH mpv
//  instances are logged to Documents/crossfade-<case>.csv; the CI script
//  reconstructs the audible mix from that (RMS, Goertzel, gaps, jumps).
//

#if DEBUG
import Foundation
import QuartzCore

@MainActor
enum CrossfadeTestHarness {
    static func runIfRequested() {
        guard let testCase = TestMode.crossfadeCase else { return }
        Task { await run(testCase) }
    }

    private static func run(_ testCase: String) async {
        let log = Log.player
        log.info("XFTEST start case=\(testCase)")
        // Give mpv a moment to come up.
        try? await Task.sleep(for: .seconds(3))

        let tmp = FileManager.default.temporaryDirectory
        // 60 s: the engine needs duration > 2 × fade + 20 (10 s fade → 40).
        let length = 60.0
        let tones: [(id: String, freq: Double)] = [("xf-a", 440), ("xf-b", 660), ("xf-c", 880)]
        for tone in tones {
            let url = tmp.appendingPathComponent("\(tone.id).wav")
            TestMode.writeSine(to: url, frequency: tone.freq, seconds: length)
            TestMode.localOverride[tone.id] = url
        }

        let settings = SettingsStore.shared
        let fade: Double
        switch testCase {
        case "fade10": fade = 10
        case "off": fade = 0
        default: fade = 3
        }
        settings.crossfadeSeconds = fade
        settings.gaplessPlayback = false
        settings.audioNormalization = false
        settings.playerVolume = 1
        settings.sleepFadeSeconds = 0

        let songs = tones.map { tone in
            SongItem(videoId: tone.id, title: "Test \(Int(tone.freq)) Hz", artists: [YTArtist(name: "Resona Test", id: nil)],
                     duration: Int(length), thumbnailUrl: nil, isExplicit: false, musicVideoType: nil)
        }
        PlaybackQueue.play(songs, startIndex: 0, log: log, context: "XFTEST")

        // Wait for the first song, then jump close to the crossfade point.
        let np = NowPlaying.shared
        let player = PlayerController.shared
        for _ in 0..<200 where !(np.videoId == "xf-a" && player.currentTime > 0.2) {
            try? await Task.sleep(for: .milliseconds(50))
        }
        let swapAt = length - fade - 2.5
        let startAt = max(0, (fade > 0 ? swapAt : length) - 6)
        player.seek(to: startAt)
        try? await Task.sleep(for: .milliseconds(300))

        // Sample both instances every 10 ms.
        var rows: [String] = ["t,slot,active,file,pos,volume,paused,idle,videoId"]
        var events: [String] = []
        let start = CACurrentMediaTime()
        var actionDone = false
        var pausedAt: Double?
        let duration: Double = fade > 0 ? (6 + fade + 2.5 + 10) : 18
        while CACurrentMediaTime() - start < duration {
            let t = CACurrentMediaTime() - start
            for probe in player.probeInstances() {
                let file = URL(fileURLWithPath: probe.path).lastPathComponent
                rows.append(String(format: "%.3f,%@,%d,%@,%.4f,%.2f,%d,%d,%@",
                                   t, probe.slot, probe.active ? 1 : 0, file, probe.position, probe.volume,
                                   probe.paused ? 1 : 0, probe.idle ? 1 : 0, np.videoId ?? ""))
            }
            // Actions in the middle of the fade (it starts as soon as the new
            // song runs, ~0.1 s after the swap).
            if !actionDone, np.videoId == "xf-b", player.currentTime > 1.5 {
                if testCase == "skip" {
                    events.append(String(format: "%.3f,skip", t))
                    np.playNext()
                    actionDone = true
                } else if testCase == "pause" {
                    events.append(String(format: "%.3f,pause", t))
                    player.setPaused(true)
                    actionDone = true
                    pausedAt = t
                }
            }
            if let since = pausedAt, t - since >= 2 {
                events.append(String(format: "%.3f,resume", t))
                player.setPaused(false)
                pausedAt = nil
            }
            try? await Task.sleep(for: .milliseconds(10))
        }

        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let csv = documents.appendingPathComponent("crossfade-\(testCase).csv")
        let meta = documents.appendingPathComponent("crossfade-\(testCase).events")
        try? rows.joined(separator: "\n").write(to: csv, atomically: true, encoding: .utf8)
        try? (["case=\(testCase)", "fade=\(fade)", "start=\(startAt)", "length=\(length)"] + events).joined(separator: "\n")
            .write(to: meta, atomically: true, encoding: .utf8)
        log.info("XFTEST done case=\(testCase) rows=\(rows.count) file=\(csv.path)")
        try? "done".write(to: documents.appendingPathComponent("crossfade-\(testCase).done"), atomically: true, encoding: .utf8)
    }
}
#endif
