//
//  PlayerStylesTests.swift
//  ResonaTests
//
//  Round 10 player styles: die-cut shape, artwork placeholder, codec line.
//

import XCTest
@testable import Trop

final class PlayerStylesTests: XCTestCase {
    func testDieCutStaysInsideItsFrame() {
        for morph in stride(from: 0.0, through: 1.0, by: 0.25) {
            for step in 0..<360 {
                let theta = Double(step) / 360 * 2 * .pi
                let r = DieCutShape.radiusFactor(theta: theta, morph: morph, lobes: 12)
                XCTAssertGreaterThan(r, 0.8, "morph \(morph) θ \(theta)")
                XCTAssertLessThanOrEqual(r, 1.0001, "morph \(morph) θ \(theta)")
            }
        }
        // Squircle corners touch the frame, the scallop peaks at θ = 0.
        XCTAssertEqual(DieCutShape.radiusFactor(theta: .pi / 4, morph: 0, lobes: 12), 1, accuracy: 0.0001)
        XCTAssertEqual(DieCutShape.radiusFactor(theta: 0, morph: 1, lobes: 12), 1, accuracy: 0.0001)
    }

    func testDieCutPathIsClosed() {
        let path = DieCutShape(morph: 0.5).path(in: CGRect(x: 0, y: 0, width: 200, height: 200))
        XCTAssertFalse(path.isEmpty)
        let box = path.boundingRect
        XCTAssertLessThanOrEqual(box.maxX, 200.5)
        XCTAssertGreaterThanOrEqual(box.minX, -0.5)
    }

    func testPlaceholderInitial() {
        XCTAssertEqual(ArtworkPlaceholder.initial(of: "  (platzhalter) Lied"), "P")
        XCTAssertEqual(ArtworkPlaceholder.initial(of: "99 Testtöne"), "9")
        XCTAssertNil(ArtworkPlaceholder.initial(of: "…"))
    }

    func testCodecLine() {
        XCTAssertEqual(StreamInfoLine.codecName(codecs: nil, mime: "audio/webm; codecs=\"opus\""), "Opus")
        XCTAssertEqual(StreamInfoLine.codecName(codecs: "mp4a.40.2", mime: "audio/mp4"), "AAC")
        XCTAssertEqual(StreamInfoLine.codecName(codecs: "mp4a.40.5", mime: "audio/mp4"), "HE-AAC")
        XCTAssertNil(StreamInfoLine.codecName(codecs: "", mime: "audio/mp4"))
        XCTAssertEqual(
            StreamInfoLine.describe(mime: "audio/webm; codecs=\"opus\"", codecs: "opus", bitrate: 132_000,
                                    sampleRate: 48_000, contentLength: 3_565_158),
            "Opus · WEBM • 132 kbps • 48 kHz • 3.4 MB")
        XCTAssertEqual(StreamInfoLine.describe(mime: "audio/mp4", codecs: nil, bitrate: 0, sampleRate: 44_100, contentLength: 0),
                       "MP4 • 44.1 kHz")
        XCTAssertEqual(StreamInfoLine.describe(mime: nil, codecs: nil, bitrate: 0, sampleRate: 0, contentLength: 0), "")
    }

    func testEditorialHeadlineShrinksWithLength() {
        XCTAssertGreaterThan(EditorialType.headlineSize(for: "Kurz", compact: false),
                             EditorialType.headlineSize(for: "Ein deutlich längerer Platzhaltertitel", compact: false))
    }
}
