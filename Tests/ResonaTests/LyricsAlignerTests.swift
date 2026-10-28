//
//  LyricsAlignerTests.swift
//  ResonaTests
//
//  Forced alignment with synthetic recognitions. All texts are invented
//  placeholders — never real song lyrics.
//

import XCTest
@testable import Trop

final class LyricsAlignerTests: XCTestCase {
    private let lines = [
        "la la erste Zeile",
        "zweite Zeile mit Wort Wort",
        "dritte Reihe hier",
        "vierte Zeile endet bald"
    ]

    /// Every word 0.4 s, 1 s pause between lines, first word at 2 s.
    private func recognition(of lines: [String], start: Double = 2) -> (words: [RecognizedWord], lineStarts: [Double]) {
        var t = start
        var words: [RecognizedWord] = []
        var lineStarts: [Double] = []
        for line in lines {
            lineStarts.append(t)
            for word in line.split(separator: " ") {
                words.append(RecognizedWord(text: String(word), start: t, end: t + 0.35))
                t += 0.4
            }
            t += 1
        }
        return (words, lineStarts)
    }

    private func assertMonotonic(_ result: LyricsAligner.Result, file: StaticString = #filePath, line: UInt = #line) {
        let starts = result.lines.flatMap { $0.words?.map(\.start) ?? [$0.startTime].compactMap { $0 } }
        for (a, b) in zip(starts, starts.dropFirst()) {
            XCTAssertLessThanOrEqual(a, b + 1e-9, "word times must not go backwards", file: file, line: line)
        }
        for word in result.lines.flatMap({ $0.words ?? [] }) {
            XCTAssertGreaterThan(word.end, word.start, file: file, line: line)
        }
    }

    func testExactRecognition() {
        let (words, starts) = recognition(of: lines)
        let result = LyricsAligner.align(lines: lines, recognized: words, duration: 60)
        XCTAssertEqual(result.matchedRatio, 1, accuracy: 0.001)
        XCTAssertEqual(result.lines.count, lines.count)
        for (line, expected) in zip(result.lines, starts) {
            XCTAssertEqual(line.startTime ?? -1, expected, accuracy: 0.001)
            XCTAssertEqual(line.words?.count, line.text.split(separator: " ").count)
        }
        XCTAssertEqual(result.lines.map(\.text), lines, "texts stay exactly as given")
        assertMonotonic(result)
    }

    func testMissingWordsAreInterpolated() {
        var (words, starts) = recognition(of: lines)
        // The recognizer misses "mit" and "hier".
        words.removeAll { $0.text == "mit" || $0.text == "hier" }
        let result = LyricsAligner.align(lines: lines, recognized: words, duration: 60)
        let total = lines.flatMap { $0.split(separator: " ") }.count
        XCTAssertEqual(result.matchedRatio, Double(total - 2) / Double(total), accuracy: 0.001)
        for (line, expected) in zip(result.lines, starts) {
            XCTAssertEqual(line.startTime ?? -1, expected, accuracy: 0.001)
        }
        // "mit" sits between "Zeile" and "Wort" of line 2.
        let second = result.lines[1].words ?? []
        XCTAssertEqual(second.count, 5)
        XCTAssertGreaterThanOrEqual(second[2].start, second[1].start)
        XCTAssertLessThanOrEqual(second[2].start, second[3].start)
        assertMonotonic(result)
    }

    func testExtraWordsAreIgnored() {
        let (base, starts) = recognition(of: lines)
        // Ad-libs between the lines and inside line 3.
        var words: [RecognizedWord] = []
        for word in base {
            if word.text == "Reihe" { words.append(RecognizedWord(text: "hey", start: word.start - 0.05, end: word.start - 0.01)) }
            words.append(word)
            if word.text == "Zeile" { words.append(RecognizedWord(text: "yeah", start: word.end, end: word.end + 0.04)) }
        }
        let result = LyricsAligner.align(lines: lines, recognized: words, duration: 60)
        XCTAssertEqual(result.matchedRatio, 1, accuracy: 0.001)
        for (line, expected) in zip(result.lines, starts) {
            XCTAssertEqual(line.startTime ?? -1, expected, accuracy: 0.001)
        }
        assertMonotonic(result)
    }

    func testMisspelledWordsStillMatch() {
        let heard = [
            "la la ersde Zeile",
            "zwaite Zeile mit Wort Wort",
            "dritt Reihe hier",
            "vierte Zeile endett bald"
        ]
        let (words, starts) = recognition(of: heard)
        let result = LyricsAligner.align(lines: lines, recognized: words, duration: 60)
        XCTAssertEqual(result.matchedRatio, 1, accuracy: 0.001)
        for (line, expected) in zip(result.lines, starts) {
            XCTAssertEqual(line.startTime ?? -1, expected, accuracy: 0.001)
        }
        XCTAssertEqual(result.lines.map(\.text), lines, "the known lyrics are kept, not the recognized spelling")
    }

    func testCaseDiacriticsAndPunctuationAreNormalized() {
        XCTAssertEqual(LyricsAligner.normalize("Zéile,"), "zeile")
        XCTAssertEqual(LyricsAligner.normalize("Wort's"), "worts")
        XCTAssertEqual(LyricsAligner.similarity("wort", "wort"), 1)
        XCTAssertEqual(LyricsAligner.similarity("", ""), 0)
        XCTAssertGreaterThanOrEqual(LyricsAligner.similarity("zeile", "zeilen"), 0.55)
        XCTAssertLessThan(LyricsAligner.similarity("bald", "hier"), 0.55)
    }

    func testNothingRecognized() {
        let result = LyricsAligner.align(lines: lines, recognized: [], duration: 60)
        XCTAssertEqual(result.matchedRatio, 0)
        XCTAssertEqual(result.lines.count, lines.count)
        assertMonotonic(result)
    }

    func testOutlierTimesDoNotMakeLinesJump() {
        var (words, starts) = recognition(of: lines)
        // Two recognitions with absurd times (hallucination / wrong chunk):
        // "dritte" claims to be at 0.3 s, "vierte" at 55 s.
        words = words.map { word in
            switch word.text {
            case "dritte": return RecognizedWord(text: word.text, start: 0.3, end: 0.6)
            case "vierte": return RecognizedWord(text: word.text, start: 55, end: 55.3)
            default: return word
            }
        }
        let result = LyricsAligner.align(lines: lines, recognized: words, duration: 60)
        let lineStarts = result.lines.compactMap(\.startTime)
        XCTAssertEqual(lineStarts.count, lines.count)
        XCTAssertEqual(lineStarts, lineStarts.sorted(), "line starts never go backwards")
        // The outliers are interpolated from their neighbours, not taken over.
        XCTAssertEqual(lineStarts[2], starts[2], accuracy: 1.2)
        XCTAssertEqual(lineStarts[3], starts[3], accuracy: 1.2)
        assertMonotonic(result)
    }

    func testUnsortedRecognitionStaysMonotonic() {
        // Chunks transcribed in parallel may come back out of order.
        let (words, _) = recognition(of: lines)
        let shuffled = Array(words[8...]) + Array(words[..<8])
        let result = LyricsAligner.align(lines: lines, recognized: shuffled, duration: 60)
        let lineStarts = result.lines.compactMap(\.startTime)
        XCTAssertEqual(lineStarts, lineStarts.sorted())
        assertMonotonic(result)
    }

    func testLongestNonDecreasing() {
        let values: [Double?] = [1, nil, 3, 2, 4, 0, 5, 5]
        let picked = LyricsAligner.longestNonDecreasing(values)
        XCTAssertEqual(picked.count, 5)
        let pickedValues = picked.compactMap { values[$0] }
        XCTAssertEqual(pickedValues, pickedValues.sorted())
        XCTAssertTrue(LyricsAligner.longestNonDecreasing([nil, nil]).isEmpty)
    }

    func testMonotonicTimingPullsBackwardLinesUp() {
        let scrambled = [
            LyricLine(text: "la la eins", startTime: 1),
            LyricLine(text: "la la zwei", startTime: 5),
            LyricLine(text: "la la drei", startTime: 3),
            LyricLine(text: "la la vier", startTime: 7),
            LyricLine(text: "ohne Zeit", startTime: nil)
        ]
        let fixed = LyricLine.monotonicTiming(scrambled)
        for (got, want) in zip(fixed.compactMap(\.startTime), [1, 5, 5.2, 7]) {
            XCTAssertEqual(got, want, accuracy: 1e-9)
        }
        XCTAssertNil(fixed[4].startTime)
        XCTAssertEqual(fixed.map(\.id), scrambled.map(\.id), "ids unchanged")
        let ordered = [LyricLine(text: "a", startTime: 1), LyricLine(text: "b", startTime: 2)]
        XCTAssertEqual(LyricLine.monotonicTiming(ordered), ordered, "correct timing is untouched")
    }

    func testCompletelyDifferentAudioHasLowRatio() {
        let (words, _) = recognition(of: ["ganz andere Silben", "nichts davon passt", "komplett fremd"])
        let result = LyricsAligner.align(lines: lines, recognized: words, duration: 60)
        XCTAssertLessThan(result.matchedRatio, 0.3, "below the 30 % threshold → AI sync refuses to save")
    }
}
