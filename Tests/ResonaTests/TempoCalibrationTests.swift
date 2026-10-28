//
//  TempoCalibrationTests.swift
//  ResonaTests
//
//  AI tempo calibration with synthetic anchors (known factor and offset,
//  noise and outliers) and the remix helpers. Placeholder texts only.
//

import XCTest
@testable import Trop

final class TempoCalibrationTests: XCTestCase {
    /// Deterministic pseudo random numbers in 0..<1.
    private struct LCG {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
    }

    private func anchors(factor: Double, offset: Double, count: Int, span: Double,
                         noise: Double, outliers: Double, seed: UInt64 = 42) -> [TimeAnchor] {
        var random = LCG(state: seed)
        return (0..<count).map { index in
            let original = span * Double(index) / Double(max(1, count - 1))
            var observed = factor * original + offset + (random.next() - 0.5) * 2 * noise
            if random.next() < outliers { observed = random.next() * span * 1.5 }   // wrong match
            return TimeAnchor(original: original, observed: observed)
        }
    }

    func testFitsFactorAndOffsetDespiteNoiseAndOutliers() {
        let data = anchors(factor: 1.193, offset: 0.4, count: 60, span: 180, noise: 0.15, outliers: 0.2)
        guard case .fitted(let calibration) = TempoCalibrator.fit(data) else {
            return XCTFail("expected a good fit, got \(TempoCalibrator.fit(data))")
        }
        XCTAssertEqual(calibration.factor, 1.193, accuracy: 0.003)
        XCTAssertEqual(calibration.offset, 0.4, accuracy: 0.25)
        XCTAssertLessThan(calibration.rms, 0.2)
        XCTAssertGreaterThanOrEqual(calibration.anchors, 40, "outliers are not counted as inliers")
    }

    func testFewButSpreadAnchorsAreEnough() {
        // ~10 % recognized: 8 anchors over the whole song.
        let data = anchors(factor: 0.87, offset: -1.2, count: 8, span: 200, noise: 0.1, outliers: 0)
        guard case .fitted(let calibration) = TempoCalibrator.fit(data) else { return XCTFail("expected a fit") }
        XCTAssertEqual(calibration.factor, 0.87, accuracy: 0.004)
        XCTAssertEqual(calibration.offset, -1.2, accuracy: 0.3)
    }

    func testTooFewAnchors() {
        let data = anchors(factor: 1.2, offset: 0, count: 5, span: 180, noise: 0, outliers: 0)
        XCTAssertEqual(TempoCalibrator.fit(data), .tooFewAnchors(5))
    }

    func testClusteredAnchorsAreNotTrusted() {
        // All anchors within 10 s of a 3-minute song: the slope is a guess.
        let data = anchors(factor: 1.2, offset: 0, count: 20, span: 10, noise: 0.05, outliers: 0)
        guard case .poorFit = TempoCalibrator.fit(data) else { return XCTFail("clustered anchors must not count as a good fit") }
    }

    func testApplyMapsLinesAndWords() {
        var line = LyricLine(text: "la la Zeile", startTime: 10,
                             words: [LyricWord(text: "la ", start: 10, end: 10.5), LyricWord(text: "Zeile", start: 10.5, end: 11)])
        line.id = "fixed"
        let mapped = TempoCalibrator.apply([line, LyricLine(text: "ohne Zeit", startTime: nil)],
                                           TempoCalibration(factor: 1.2, offset: 0.5, anchors: 10, rms: 0.1))
        XCTAssertEqual(mapped[0].startTime ?? 0, 12.5, accuracy: 1e-9)
        XCTAssertEqual(mapped[0].words?[1].start ?? 0, 13.1, accuracy: 1e-9)
        XCTAssertEqual(mapped[0].words?[1].end ?? 0, 13.7, accuracy: 1e-9)
        XCTAssertEqual(mapped[0].id, "fixed")
        XCTAssertNil(mapped[1].startTime)
    }

    func testAnchorsFromWordSyncedLyrics() {
        // Word-synced placeholder lyrics; the recording is 1.2× slower + 0.5 s.
        let texts = ["erste Zeile mit Platzhalter", "zweite Reihe voller Testwort", "dritte Strophe ohne Inhalt",
                     "vierte Zeile kommt danach", "fuenfte Reihe bleibt kurz", "sechste Strophe endet hier"]
        var lines: [LyricLine] = []
        var recognized: [RecognizedWord] = []
        for (index, text) in texts.enumerated() {
            let start = 10 + Double(index) * 25
            let parts = text.split(separator: " ").map(String.init)
            let words = parts.enumerated().map { k, part in
                LyricWord(text: part + (k < parts.count - 1 ? " " : ""), start: start + Double(k) * 0.6, end: start + Double(k) * 0.6 + 0.5)
            }
            lines.append(LyricLine(text: text, startTime: start, words: words))
            for word in words {
                recognized.append(RecognizedWord(text: word.text, start: 1.2 * word.start + 0.5, end: 1.2 * word.end + 0.5))
            }
        }
        let found = LyricsAligner.anchors(lines: lines, recognized: recognized)
        XCTAssertGreaterThanOrEqual(found.count, 20)
        guard case .fitted(let calibration) = TempoCalibrator.fit(found) else { return XCTFail("expected a fit") }
        XCTAssertEqual(calibration.factor, 1.2, accuracy: 0.001)
        XCTAssertEqual(calibration.offset, 0.5, accuracy: 0.05)
    }

    // MARK: Remix: partial sync

    func testLineOccurrencesFindRepeatsAndReordering() {
        let texts = ["alpha beta gamma delta", "epsilon zeta eta theta", "kappa lambda my ny"]
        // The "remix" sings line 3, then line 1, then line 3 twice more;
        // line 2 never. Extra filler words in between.
        var recognized: [RecognizedWord] = []
        var t = 5.0
        func sing(_ text: String) {
            for word in text.split(separator: " ") {
                recognized.append(RecognizedWord(text: String(word), start: t, end: t + 0.3))
                t += 0.4
            }
            t += 2
        }
        sing("kappa lambda my ny")
        sing("ooh yeah")
        sing("alpha beta gamma delta")
        sing("kappa lambda my ny")
        sing("kappa lambda ny")          // one word missed: still ≥ 70 %
        let occurrences = LyricsAligner.lineOccurrences(lines: texts, recognized: recognized)
        XCTAssertEqual(occurrences.map(\.lineIndex), [2, 0, 2, 2])
        XCTAssertEqual(occurrences.map(\.start), occurrences.map(\.start).sorted())
        XCTAssertEqual(occurrences.first?.start ?? -1, 5, accuracy: 0.001)
        for occurrence in occurrences {
            let starts = occurrence.words.map(\.start)
            XCTAssertEqual(starts, starts.sorted())
        }
    }

    func testNoOccurrencesForUnrelatedAudio() {
        let texts = ["alpha beta gamma delta", "epsilon zeta eta theta"]
        let recognized = ["ganz", "andere", "Silben", "hier", "und", "dort"].enumerated().map {
            RecognizedWord(text: $1, start: Double($0), end: Double($0) + 0.3)
        }
        XCTAssertTrue(LyricsAligner.lineOccurrences(lines: texts, recognized: recognized).isEmpty)
    }
}
