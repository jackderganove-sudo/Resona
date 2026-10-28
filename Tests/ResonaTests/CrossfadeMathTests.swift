//
//  CrossfadeMathTests.swift
//  ResonaTests
//
//  mpv applies its software volume cubically; the crossfade must pass the
//  cube roots so the audible amplitudes follow sin/cos (equal power).
//

import XCTest
@testable import Trop

final class CrossfadeMathTests: XCTestCase {
    func testVolumeFactorInvertsMpvsCubicCurve() {
        for amplitude in stride(from: 0.0, through: 1.0, by: 0.05) {
            let factor = CrossfadeEngine.volumeFactor(forAmplitude: amplitude)
            XCTAssertEqual(pow(factor, 3), amplitude, accuracy: 1e-9)
        }
        XCTAssertEqual(CrossfadeEngine.volumeFactor(forAmplitude: -0.2), 0)
        XCTAssertEqual(CrossfadeEngine.volumeFactor(forAmplitude: 1.7), 1)
    }

    func testEqualPowerThroughTheWholeFade() {
        for step in 0...100 {
            let t = Double(step) / 100
            let new = pow(CrossfadeEngine.volumeFactor(forAmplitude: sin(t * .pi / 2)), 3)
            let old = pow(CrossfadeEngine.volumeFactor(forAmplitude: cos(t * .pi / 2)), 3)
            XCTAssertEqual(new * new + old * old, 1, accuracy: 1e-9, "power sum at t=\(t)")
        }
    }
}
