//
//  SpeakerPickerTests.swift
//  ResonaTests
//
//  Output kinds, icons and names for the speaker button (round 12).
//

import XCTest
import AVFoundation
@testable import Trop

final class SpeakerPickerTests: XCTestCase {
    func testPortTypes() {
        XCTAssertEqual(AudioOutput.kind(forPortType: AVAudioSession.Port.builtInSpeaker.rawValue), .builtIn)
        XCTAssertEqual(AudioOutput.kind(forPortType: AVAudioSession.Port.bluetoothA2DP.rawValue), .bluetooth)
        XCTAssertEqual(AudioOutput.kind(forPortType: AVAudioSession.Port.bluetoothLE.rawValue), .bluetooth)
        XCTAssertEqual(AudioOutput.kind(forPortType: AVAudioSession.Port.airPlay.rawValue), .airPlay)
        XCTAssertEqual(AudioOutput.kind(forPortType: AVAudioSession.Port.headphones.rawValue), .headphones)
        XCTAssertEqual(AudioOutput.kind(forPortType: AVAudioSession.Port.carAudio.rawValue), .car)
        XCTAssertEqual(AudioOutput.kind(forPortType: "SomethingNew"), .other)
    }

    func testIconsAndNames() {
        let echo = AudioOutput(kind: .bluetooth, name: "Echo Dot")
        XCTAssertEqual(echo.systemImage, "hifispeaker.fill")
        XCTAssertEqual(echo.displayName, "Echo Dot")
        XCTAssertTrue(echo.isExternal)
        XCTAssertEqual(AudioOutput(kind: .bluetooth, name: "Platzhalter AirPods").systemImage, "airpods")
        XCTAssertEqual(AudioOutput(kind: .airPlay, name: "Wohnzimmer").systemImage, "airplayaudio")
        XCTAssertFalse(AudioOutput.builtInSpeaker.isExternal)
        XCTAssertFalse(AudioOutput.builtInSpeaker.displayName.isEmpty, "this device has a name too")
    }
}
