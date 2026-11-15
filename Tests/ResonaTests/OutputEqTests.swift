//
//  OutputEqTests.swift
//  ResonaTests
//
//  EQ per output device (round 12): mapping and switching. Same cases as
//  Resona-Android's OutputEqTest.
//

import XCTest
@testable import Trop

final class OutputEqTests: XCTestCase {
    private let flat = EqSnapshot(enabled: true, presetID: "flat", gains: Array(repeating: 0, count: 10))
    private let bass = EqSnapshot(enabled: true, presetID: "bassBoost", gains: [7, 6, 4, 2, 1, 0, 0, 0, 0, 0])
    private let off = EqSnapshot(enabled: false, presetID: "flat", gains: Array(repeating: 0, count: 10))

    private let headphones = AudioOutput(kind: .bluetooth, name: "Soundcore Space One")
    private let echo = AudioOutput(kind: .bluetooth, name: "Echo Dot")

    func testKeys() {
        XCTAssertEqual(OutputEqRules.key(for: .builtInSpeaker), "builtin")
        XCTAssertEqual(OutputEqRules.key(for: AudioOutput(kind: .builtIn, name: "iPad")), "builtin")
        XCTAssertEqual(OutputEqRules.key(for: headphones), "bluetooth:soundcore space one")
        XCTAssertEqual(OutputEqRules.key(for: AudioOutput(kind: .bluetooth, name: " Soundcore Space One ")),
                       OutputEqRules.key(for: headphones))
        XCTAssertNotEqual(OutputEqRules.key(for: AudioOutput(kind: .airPlay, name: "Echo Dot")), OutputEqRules.key(for: echo))
    }

    func testUnknownDeviceUsesTheDefault() {
        let state = OutputEqState(standard: flat)
        XCTAssertEqual(OutputEqRules.resolve(state, key: OutputEqRules.key(for: echo)), flat)
        XCTAssertFalse(OutputEqRules.hasOwn(state, key: OutputEqRules.key(for: echo)))
    }

    func testEditIsRememberedPerDeviceAndSwitchesBack() {
        var state = OutputEqState(standard: flat)
        let phones = OutputEqRules.key(for: headphones)
        state = OutputEqRules.record(state, key: phones, name: headphones.displayName, eq: bass)
        XCTAssertTrue(OutputEqRules.hasOwn(state, key: phones))
        XCTAssertEqual(state.devices[phones]?.name, "Soundcore Space One")
        XCTAssertEqual(state.standard, flat, "the default stays")

        // Headphones → iPad speaker: back to the default; → headphones: their own EQ.
        XCTAssertEqual(OutputEqRules.switchTo(state, key: "builtin", current: bass), flat)
        XCTAssertEqual(OutputEqRules.switchTo(state, key: phones, current: flat), bass)
        // Already right: nothing to switch, no hint.
        XCTAssertNil(OutputEqRules.switchTo(state, key: phones, current: bass))
        XCTAssertNil(OutputEqRules.switchTo(state, key: OutputEqRules.key(for: echo), current: flat))
    }

    func testSameForAllUsesAndEditsTheDefault() {
        var state = OutputEqState(standard: flat)
        let phones = OutputEqRules.key(for: headphones)
        state = OutputEqRules.record(state, key: phones, name: "Soundcore Space One", eq: bass)
        state.sameForAll = true
        XCTAssertEqual(OutputEqRules.resolve(state, key: phones), flat)
        XCTAssertFalse(OutputEqRules.hasOwn(state, key: phones))
        state = OutputEqRules.record(state, key: phones, name: "Soundcore Space One", eq: off)
        XCTAssertEqual(state.standard, off)
        XCTAssertEqual(state.devices[phones]?.eq, bass, "the device's own EQ is kept for later")
        XCTAssertEqual(OutputEqRules.resolve(state, key: "builtin"), off)
        state.sameForAll = false
        XCTAssertEqual(OutputEqRules.resolve(state, key: phones), bass)
    }

    func testUseDefaultForgetsTheDevice() {
        let phones = OutputEqRules.key(for: headphones)
        var state = OutputEqRules.record(OutputEqState(standard: flat), key: phones, name: "x", eq: bass)
        state = OutputEqRules.useStandard(state, key: phones)
        XCTAssertFalse(OutputEqRules.hasOwn(state, key: phones))
        XCTAssertEqual(OutputEqRules.resolve(state, key: phones), flat)
    }

    func testStateSurvivesSaving() throws {
        let state = OutputEqRules.record(OutputEqState(standard: flat), key: "bluetooth:echo dot", name: "Echo Dot", eq: bass)
        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(OutputEqState.self, from: data), state)
    }

    func testHintNamesPresetAndDevice() {
        XCTAssertEqual(OutputEqualizer.presetName(off), String(localized: "Off"))
        XCTAssertEqual(OutputEqualizer.presetName(EqSnapshot(enabled: true, presetID: "custom", gains: [])), String(localized: "Custom"))
        let hint = OutputEqualizer.hintText(bass, device: "Soundcore Space One")
        XCTAssertTrue(hint.hasPrefix("EQ: "))
        XCTAssertTrue(hint.contains("Soundcore Space One"))
        XCTAssertTrue(hint.contains(OutputEqualizer.presetName(bass)))
    }
}
