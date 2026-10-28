//
//  AISyncPipelineTests.swift
//  ResonaTests
//
//  KI-Sync end to end on synthetic speech: the CI script creates several
//  minutes of spoken, generated sentences with macOS `say` (no songs, no
//  lyrics) and passes the files via TEST_RUNNER_RESONA_SPEECH_AUDIO /
//  _TEXT. Checks: ffmpeg conversion keeps the full length, Whisper covers
//  the WHOLE file (not only the first 30 s window), alignment > 80 %.
//

import XCTest
@testable import Trop

final class AISyncPipelineTests: XCTestCase {
    func testSpeechIsAlignedOverItsWholeLength() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let audio = env["RESONA_SPEECH_AUDIO"], let textPath = env["RESONA_SPEECH_TEXT"],
              FileManager.default.fileExists(atPath: audio) else {
            throw XCTSkip("no synthetic speech fixture (only created by scripts/simulator_tests.sh)")
        }
        let expectedSeconds = Double(env["RESONA_SPEECH_SECONDS"] ?? "") ?? 0
        let lines = try String(contentsOfFile: textPath, encoding: .utf8)
            .split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        XCTAssertGreaterThan(lines.count, 20)

        let result = try await AILyricsSync.transcribeFile(audio, variant: "openai_whisper-base", language: "en")
        if expectedSeconds > 0 {
            XCTAssertEqual(result.audioSeconds, expectedSeconds, accuracy: max(1, expectedSeconds * 0.01),
                           "16 kHz WAV must keep the full length")
        }
        let lastWord = result.words.last?.start ?? 0
        XCTAssertGreaterThan(lastWord, result.audioSeconds * 0.85, "recognized words must reach the end, not stop after 30 s")

        let aligned = LyricsAligner.align(lines: lines, recognized: result.words, duration: result.audioSeconds)
        print("AISYNC test: \(result.words.count) words, audio \(Int(result.audioSeconds)) s, last word \(Int(lastWord)) s, matched \(Int(aligned.matchedRatio * 100)) %")
        XCTAssertGreaterThan(aligned.matchedRatio, 0.8)
        let starts = aligned.lines.compactMap(\.startTime)
        XCTAssertEqual(starts.count, lines.count, "every line gets a time")
        XCTAssertEqual(starts, starts.sorted(), "line times increase")
        XCTAssertGreaterThan(starts.last ?? 0, result.audioSeconds * 0.8, "last line near the end")
    }
}
