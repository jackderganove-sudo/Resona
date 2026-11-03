//
//  CanvasColorTests.swift
//  ResonaTests
//
//  Round 11: canvas colours for the gradient background (synthetic frames).
//

import XCTest
@testable import Trop

final class CanvasColorTests: XCTestCase {
    /// BGRA frame: left half red, right half blue, a black stripe.
    private func frame(width: Int = 24, height: Int = 24) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                if y < 2 { continue } // black stripe
                if x < width / 2 { bytes[i + 2] = 220; bytes[i + 1] = 30; bytes[i] = 30 } else { bytes[i] = 200; bytes[i + 1] = 40; bytes[i + 2] = 20 }
                bytes[i + 3] = 255
            }
        }
        return bytes
    }

    func testFindsTheMainColours() {
        let colors = CanvasColorQuantizer.dominant(bgra: frame(), width: 24, height: 24, bytesPerRow: 96)
        XCTAssertEqual(colors.count, 4)
        XCTAssertTrue(colors.contains { $0.r > 0.7 && $0.b < 0.3 }, "red found")
        XCTAssertTrue(colors.contains { $0.b > 0.6 && $0.r < 0.3 }, "blue found")
    }

    func testReadableLimitsBrightnessAndSaturation() {
        let out = CanvasColorQuantizer.readable([RGB(r: 1, g: 1, b: 0), RGB(r: 0, g: 0, b: 0)])
        XCTAssertLessThanOrEqual(out[0].hsv.v, 0.62 + 0.001)
        XCTAssertLessThanOrEqual(out[0].hsv.s, 0.85 + 0.001)
        XCTAssertGreaterThanOrEqual(out[1].hsv.v, 0.12 - 0.001)
    }

    func testSmoothingMovesPartWay() {
        let a = [RGB](repeating: RGB(r: 0, g: 0, b: 0), count: 4)
        let b = [RGB](repeating: RGB(r: 1, g: 1, b: 1), count: 4)
        let s = CanvasColorQuantizer.smoothed(b, previous: a, factor: 0.5)
        XCTAssertEqual(s[0].r, 0.5, accuracy: 0.001)
        XCTAssertEqual(CanvasColorQuantizer.smoothed(b, previous: nil), b)
    }

    func testLegacyBackgroundStylesBecomeTheCoverGradient() {
        XCTAssertEqual(PlayerBackgroundStyle.solid.effective, .dynamic)
        XCTAssertEqual(PlayerBackgroundStyle.blurredCover.effective, .dynamic)
        XCTAssertEqual(PlayerBackgroundStyle.allCases, [.canvasGradient, .dynamic, .staticGradient])
    }
}
