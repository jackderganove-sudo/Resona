//
//  PlaybackExtrasTests.swift
//  ResonaTests
//
//  Round 10 playback additions: error hints, playback-before-downloads gate.
//

import XCTest
import SwiftyTube
@testable import Trop

final class PlaybackExtrasTests: XCTestCase {
    func testErrorHints() {
        let bot = PlaybackErrorCenter.describe(StreamError.unplayable(reason: "Sign in to confirm you're not a bot"), videoId: "v1", title: "Platzhalter")
        XCTAssertTrue(bot.hint.contains("YouTube") || bot.hint.contains("bot"))
        XCTAssertTrue(bot.details.contains("v1"))
        XCTAssertTrue(bot.details.contains("Resona"), "app version for reports")
        let gone = PlaybackErrorCenter.describe(StreamError.unplayable(reason: "Video unavailable"), videoId: "v2", title: nil)
        XCTAssertNotEqual(gone.hint, bot.hint)
        let offline = PlaybackErrorCenter.describe(URLError(.notConnectedToInternet), videoId: "v3", title: nil)
        XCTAssertNotEqual(offline.hint, gone.hint)
        let other = PlaybackErrorCenter.describe(StreamError.allClientsFailed, videoId: "v4", title: nil)
        XCTAssertNotEqual(other.hint, offline.hint)
    }

    func testDownloadsWaitForPlaybackResolution() async {
        let gate = PlaybackPriorityGate()
        await gate.begin()
        let started = Date()
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            await gate.end()
        }
        await gate.waitForPlayback(maxSeconds: 3)
        let waited = Date().timeIntervalSince(started)
        XCTAssertGreaterThan(waited, 0.3, "download waited for the playback resolution")
        XCTAssertLessThan(waited, 2)
        // Nothing running: no wait.
        let quick = Date()
        await gate.waitForPlayback(maxSeconds: 3)
        XCTAssertLessThan(Date().timeIntervalSince(quick), 0.2)
    }

    func testGateNeverBlocksForever() async {
        let gate = PlaybackPriorityGate()
        await gate.begin()   // never ended
        let started = Date()
        await gate.waitForPlayback(maxSeconds: 0.5)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5)
    }
}
