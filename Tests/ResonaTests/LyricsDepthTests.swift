//
//  LyricsDepthTests.swift
//  ResonaTests
//
//  Round 11: lyrics blur depends only on the distance to the active line —
//  monotonic, symmetric, no "sharp again" further away (iPad portrait bug).
//

import XCTest
@testable import Trop

final class LyricsDepthTests: XCTestCase {
    func testBlurGrowsMonotonicallyWithDistance() {
        var previous: CGFloat = -1
        for distance in 0...30 {
            let blur = LyricsDepth.blurRadius(distance: distance)
            XCTAssertGreaterThanOrEqual(blur, previous, "distance \(distance)")
            previous = blur
        }
        XCTAssertEqual(LyricsDepth.blurRadius(distance: 0), 0)
        XCTAssertEqual(LyricsDepth.blurRadius(distance: 4), LyricsDepth.blurRadius(distance: 20), "constant maximum from 4 on")
    }

    func testFarLinesInPortraitStayBlurred() {
        // iPad portrait shows ~16 lines below the active one.
        for distance in 5...16 {
            XCTAssertEqual(LyricsDepth.blurRadius(distance: distance), 6, "distance \(distance)")
        }
    }

    func testPlaceholderLyricsForUITestsAreInvented() {
        // Only for placeholder ids in UI test mode; unit tests run without it.
        XCTAssertNil(TestMode.placeholderLyrics(for: "dQw4w9WgXcQ"))
    }
}
