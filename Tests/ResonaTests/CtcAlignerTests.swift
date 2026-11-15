//
//  CtcAlignerTests.swift
//  ResonaTests
//
//  Same synthetic cases as Resona-Android's CtcAlignerTest (round 12), plus
//  German placeholder lyrics (umlauts, ß folded). Invented text only.
//

import XCTest
@testable import Trop

final class CtcAlignerTests: XCTestCase {
    private let words = "placeholder lantern river invented maple window".split(separator: " ").map(String.init)

    /// Synthetic emissions: the given word starts, letters 3 frames each, blank elsewhere.
    private func emissions(_ starts: [Int], frames: Int, chosen: [String]? = nil) -> [[Float]] {
        var top = [Int](repeating: CtcAligner.blank, count: frames)
        for (word, start) in zip(chosen ?? words, starts) {
            for (i, id) in CtcAligner.letters(word).enumerated() {
                for f in 0..<3 { top[start + i * 3 + f] = id }
            }
        }
        return top.map { best in (0..<32).map { $0 == best ? Float(log(0.9)) : Float(log(0.1 / 31)) } }
    }

    func testLettersFoldUmlautsAndDropOther() {
        XCTAssertEqual(CtcAligner.letters("MUEDE").count - 1, CtcAligner.letters("müde").count)
        XCTAssertTrue(CtcAligner.letters("123 !?").isEmpty)
        XCTAssertEqual(CtcAligner.letters("strasse"), CtcAligner.letters("straße"))
    }

    func testSeparatorsOnlyBetweenWords() {
        XCTAssertEqual(CtcAligner.tokens(["ab", "--", "cd"]).map(\.id), [7, 24, 4, 19, 14])
    }

    func testFindsTheWordsWhereTheyAre() {
        let starts = [100, 180, 260, 400, 480, 540]
        let found = CtcAligner.words(emissions(starts, frames: 800), lyricWords: words, minConfidence: 0)
        XCTAssertEqual(found.count, words.count)
        for (word, start) in zip(found, starts) {
            XCTAssertEqual(word.start, Double(start) * CtcAligner.frameSeconds, accuracy: 0.1)
            XCTAssertGreaterThan(word.end, word.start)
        }
        XCTAssertEqual(found.map(\.start), found.map(\.start).sorted())
    }

    func testWordsTheModelDoesNotHearAreLeftOut() {
        let found = CtcAligner.words(emissions([50, 130, 210], frames: 400, chosen: Array(words.prefix(3))), lyricWords: words, minConfidence: 0.5)
        XCTAssertTrue((3...4).contains(found.count))
        XCTAssertEqual(found.prefix(3).map(\.text), Array(words.prefix(3)))
    }

    func testGoesThroughTheSameAligner() {
        let found = CtcAligner.words(emissions([100, 180, 260, 400, 480, 540], frames: 800), lyricWords: words, minConfidence: 0)
        let aligned = LyricsAligner.align(lines: ["placeholder lantern river", "invented maple window"], recognized: found, duration: 16)
        XCTAssertEqual(aligned.matchedRatio, 1, accuracy: 1e-9)
        XCTAssertEqual(aligned.lines[0].startTime ?? -1, 2.0, accuracy: 0.2)
        XCTAssertEqual(aligned.lines[1].startTime ?? -1, 8.0, accuracy: 0.2)
    }

    /// Round 12, point 4: German placeholder lyrics. The English model sees the
    /// folded letters (ü → U, ß → SS); when the audio carries exactly those
    /// letters the path is exact. Real German singing is not testable here.
    func testGermanPlaceholderLyrics() {
        let german = "Grüße aus der erfundenen Straße über müde Täler".split(separator: " ").map(String.init)
        let starts = [40, 110, 160, 200, 300, 380, 440, 500]
        let found = CtcAligner.words(emissions(starts, frames: 700, chosen: german), lyricWords: german, minConfidence: 0)
        XCTAssertEqual(found.map(\.text), german)
        for (word, start) in zip(found, starts) {
            XCTAssertEqual(word.start, Double(start) * CtcAligner.frameSeconds, accuracy: 0.1)
        }
        XCTAssertTrue(CtcModel.suits(["Grüße aus der erfundenen Straße", "über müde Täler und Höhen"]))
        XCTAssertFalse(CtcModel.suits(["これは架空のテキストです", "ここにも架空の行があります"]))
    }

    func testLogSoftmaxAndNormalisation() {
        let row = CtcEmissions.logSoftmax([1, 2, 3])
        XCTAssertEqual(row.map { exp(Double($0)) }.reduce(0, +), 1, accuracy: 1e-5)
        let n = CtcEmissions.normalized([1, 2, 3, 4], from: 0, to: 4)
        XCTAssertEqual(Double(n.reduce(0, +)), 0, accuracy: 1e-5)
    }
}
