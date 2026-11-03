//
//  ImmersiveLayoutTests.swift
//  ResonaTests
//
//  Round 11: Immersive player geometry on every iPad size (full screen,
//  side panel, Split View, Stage Manager) — the disc is always whole, the
//  block fits, nothing leaves the visible area. Sizes are the player's
//  content area (safe area already removed). Plus the queue reorder maths.
//

import SwiftUI
import XCTest
@testable import Trop

final class ImmersiveLayoutTests: XCTestCase {
    static let cases: [(String, CGSize)] = [
        ("13\" portrait", CGSize(width: 1032, height: 1332)),
        ("13\" landscape", CGSize(width: 1376, height: 988)),
        ("11\" portrait", CGSize(width: 834, height: 1150)),
        ("11\" landscape", CGSize(width: 1210, height: 790)),
        ("10.9\" portrait", CGSize(width: 820, height: 1136)),
        ("mini portrait", CGSize(width: 744, height: 1089)),
        ("mini landscape", CGSize(width: 1133, height: 700)),
        // Landscape with the queue side panel open (400 + 16 pt).
        ("13\" landscape + panel", CGSize(width: 960, height: 988)),
        ("11\" landscape + panel", CGSize(width: 794, height: 790)),
        ("split 1/3", CGSize(width: 320, height: 1000)),
        ("split 1/2", CGSize(width: 678, height: 988)),
        ("split 2/3", CGSize(width: 900, height: 988)),
        ("split 1/2 portrait", CGSize(width: 507, height: 1332)),
        ("stage small", CGSize(width: 500, height: 420)),
        ("stage short", CGSize(width: 700, height: 480)),
        ("stage wide", CGSize(width: 1000, height: 600)),
        ("stage tall", CGSize(width: 420, height: 900)),
    ]

    static let coreHeights: [CGFloat] = [ImmersiveLayoutMetrics.estimatedCoreHeight, 274, 340]

    func testEverySizeFits() {
        for (name, size) in Self.cases {
            for core in Self.coreHeights {
                let m = ImmersiveLayoutMetrics(size: size, coreControlsHeight: core)
                let label = "\(name) core \(core)"
                XCTAssertTrue(m.fits, "\(label): block \(m.blockHeight) > \(m.usableHeight)")
                XCTAssertLessThanOrEqual(m.disc, size.width - 2 * ImmersiveLayoutMetrics.side, label)
                XCTAssertLessThanOrEqual(m.controlsWidth, size.width - 2 * ImmersiveLayoutMetrics.side + 0.5, label)
                XCTAssertGreaterThanOrEqual(m.discTop, ImmersiveLayoutMetrics.margin, label)
                XCTAssertLessThanOrEqual(m.discTop + m.blockHeight, size.height - ImmersiveLayoutMetrics.margin + 0.5, label)
            }
        }
    }

    func testFullScreenUsesTheSpaceForTheDisc() {
        for (name, size) in Self.cases.prefix(7) {
            let m = ImmersiveLayoutMetrics(size: size, coreControlsHeight: 300)
            XCTAssertTrue(m.showsHeader && m.showsToggles, name)
            // Whatever height header and controls leave goes to the disc
            // (unless the width limits it) — no empty band.
            let limit = min(size.width - 2 * ImmersiveLayoutMetrics.side,
                            m.usableHeight - m.controlsHeight - ImmersiveLayoutMetrics.gap)
            XCTAssertEqual(m.disc, limit.rounded(.down), accuracy: 1, name)
            XCTAssertGreaterThanOrEqual(m.disc, 200, name)
        }
    }

    func testBlockCentredBelowHeader() {
        let m = ImmersiveLayoutMetrics(size: CGSize(width: 1032, height: 1332), coreControlsHeight: 300)
        let above = m.discTop - ImmersiveLayoutMetrics.margin - ImmersiveLayoutMetrics.headerHeight
        let below = m.size.height - ImmersiveLayoutMetrics.margin - (m.discTop + m.blockHeight)
        XCTAssertEqual(above, below, accuracy: 1)
    }

    func testShortWindowsDropTogglesThenHeader() {
        let small = ImmersiveLayoutMetrics(size: CGSize(width: 500, height: 420), coreControlsHeight: 300)
        XCTAssertFalse(small.showsToggles)
        XCTAssertTrue(small.fits)
        let tiny = ImmersiveLayoutMetrics(size: CGSize(width: 500, height: 360), coreControlsHeight: 300)
        XCTAssertFalse(tiny.showsHeader)
        XCTAssertEqual(tiny.disc, 0)
        XCTAssertTrue(tiny.fits)
    }

    func testControlVisibilityIsNoInput() {
        // Same size → same geometry: the disc can't move when controls fade.
        let a = ImmersiveLayoutMetrics(size: CGSize(width: 1376, height: 988), coreControlsHeight: 300)
        let b = ImmersiveLayoutMetrics(size: CGSize(width: 1376, height: 988), coreControlsHeight: 300)
        XCTAssertEqual(a, b)
    }

    // MARK: Queue reorder

    func testReorderTarget() {
        XCTAssertEqual(QueueReorder.target(from: 5, translation: 0, pitch: 76, count: 60), 5)
        XCTAssertEqual(QueueReorder.target(from: 5, translation: 37, pitch: 76, count: 60), 5)
        XCTAssertEqual(QueueReorder.target(from: 5, translation: 39, pitch: 76, count: 60), 6)
        XCTAssertEqual(QueueReorder.target(from: 5, translation: 3 * 76, pitch: 76, count: 60), 8)
        XCTAssertEqual(QueueReorder.target(from: 5, translation: -10 * 76, pitch: 76, count: 60), 0)
        XCTAssertEqual(QueueReorder.target(from: 58, translation: 10 * 76, pitch: 76, count: 60), 59)
    }

    func testReorderGapOpensAtTarget() {
        let down = (0..<12).map { QueueReorder.shift(index: $0, from: 5, to: 8, pitch: 76) }
        XCTAssertEqual(down, [0, 0, 0, 0, 0, 0, -76, -76, -76, 0, 0, 0])
        let up = (0..<12).map { QueueReorder.shift(index: $0, from: 8, to: 5, pitch: 76) }
        XCTAssertEqual(up, [0, 0, 0, 0, 0, 76, 76, 76, 0, 0, 0, 0])
    }

    func testReorderDropMatchesListMove() {
        var songs = Array(0..<10)
        songs.move(fromOffsets: IndexSet(integer: 5), toOffset: QueueReorder.moveDestination(from: 5, to: 8))
        XCTAssertEqual(songs, [0, 1, 2, 3, 4, 6, 7, 8, 5, 9])
        songs = Array(0..<10)
        songs.move(fromOffsets: IndexSet(integer: 8), toOffset: QueueReorder.moveDestination(from: 8, to: 5))
        XCTAssertEqual(songs, [0, 1, 2, 3, 4, 8, 5, 6, 7, 9])
    }

    func testReorderPreviewIsOpaque() {
        let color = QueueDragState.panelColor(m3: M3Scheme.fallbackDark, cover: Color(red: 0.6, green: 0.2, blue: 0.1))
        XCTAssertEqual(color.resolve(in: EnvironmentValues()).opacity, 1, accuracy: 0.001)
    }
}
