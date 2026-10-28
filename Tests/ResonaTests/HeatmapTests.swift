//
//  HeatmapTests.swift
//  ResonaTests
//
//  "Most replayed" parsing (saved `next` response excerpts in Fixtures/)
//  and drop detection.
//

import XCTest
@testable import Trop

final class HeatmapTests: XCTestCase {
    private func fixture(_ name: String) throws -> Any {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"), "missing fixture \(name)")
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    }

    func testCurrentFormat() throws {
        let heatmap = try XCTUnwrap(MostReplayedService.parse(try fixture("heatmap-current")))
        XCTAssertEqual(heatmap.values.count, 100)
        XCTAssertEqual(heatmap.duration, 200, accuracy: 0.001)
        // Peak in segment 60 (2 s each) → 120 s, minus 3 s lead.
        XCTAssertEqual(heatmap.dropTime ?? -1, 117, accuracy: 0.001)
    }

    func testLegacyFormat() throws {
        let heatmap = try XCTUnwrap(MostReplayedService.parse(try fixture("heatmap-legacy")))
        XCTAssertEqual(heatmap.values.count, 50)
        XCTAssertEqual(heatmap.duration, 75, accuracy: 0.001)
        // Peak in segment 30 (1.5 s each) → 45 s, minus 3 s.
        XCTAssertEqual(heatmap.dropTime ?? -1, 42, accuracy: 0.001)
    }

    func testResponseWithoutHeatmap() throws {
        XCTAssertNil(MostReplayedService.parse(try fixture("heatmap-none")))
        XCTAssertNil(MostReplayedService.parse([String: Any]()))
        XCTAssertNil(MostReplayedService.parse("garbage"))
    }

    func testStartAndEndPeaksAreIgnored() {
        // Highest at the very start and in the last 3 %: both ignored.
        var values = [Double](repeating: 0.1, count: 100)
        values[0] = 1; values[1] = 1; values[99] = 1; values[98] = 1
        values[40] = 0.6
        let heatmap = Heatmap(values: values, duration: 100)
        XCTAssertEqual(heatmap.dropTime ?? -1, 37, accuracy: 0.001)
    }

    func testDropNeverNegative() {
        var values = [Double](repeating: 0.1, count: 100)
        values[6] = 1   // first segment after the ignored 6 %
        XCTAssertEqual(Heatmap(values: values, duration: 30).dropTime ?? -1, 0, accuracy: 0.001)
    }

    func testTooFewSegmentsHaveNoDrop() {
        XCTAssertNil(Heatmap(values: [0.1, 0.9, 0.2], duration: 180).dropTime)
        XCTAssertNil(Heatmap(values: [Double](repeating: 0.5, count: 20), duration: 0).dropTime)
    }
}
