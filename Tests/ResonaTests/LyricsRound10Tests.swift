//
//  LyricsRound10Tests.swift
//  ResonaTests
//
//  Round 10 lyrics additions (as in ArchiveTune 15): Binimum lookup,
//  enhanced LRC word times on repeated lines, AI translation reply
//  parsing. Placeholder texts only.
//

import XCTest
@testable import Trop

final class LyricsRound10Tests: XCTestCase {
    func testBinimumPrefersWordTimingThenDuration() {
        let json: [String: Any] = ["results": [
            ["lyricsUrl": "https://example.org/a.ttml", "timing_type": "line", "duration": 180],
            ["lyricsUrl": "https://example.org/b.ttml", "timing_type": "word", "duration": 200],
            ["lyricsUrl": "https://example.org/c.ttml", "timing_type": "word", "duration": 181],
            ["lyricsUrl": "https://example.org/c.ttml", "timing_type": "word", "duration": 181]
        ]]
        let matches = BinimumLyricsProvider.parseLookup(json, queryDuration: 180)
        XCTAssertEqual(matches.map(\.url), ["https://example.org/c.ttml", "https://example.org/b.ttml", "https://example.org/a.ttml"])
    }

    func testRepeatedLrcLineShiftsWordTimes() {
        let raw = "[00:10.00][00:30.00]<00:10.00>la <00:10.50>la <00:11.00>Zeile"
        let lines = LyricsParsing.parseLrc(raw)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].words?.map(\.start), [10, 10.5, 11])
        XCTAssertEqual(lines[1].startTime, 30)
        XCTAssertEqual(lines[1].words?.map(\.start), [30, 30.5, 31], "words follow the repeated timestamp")
    }

    func testAITranslationReplyParsing() throws {
        XCTAssertEqual(try AILyricsTranslator.jsonArray(in: "```json\n[\"eins\", \"zwei\"]\n```"), ["eins", "zwei"])
        XCTAssertEqual(try AILyricsTranslator.jsonArray(in: "Hier: [\"a\"] fertig"), ["a"])
        XCTAssertThrowsError(try AILyricsTranslator.jsonArray(in: "keine Liste"))
        XCTAssertThrowsError(try AILyricsTranslator.jsonArray(in: "[1, 2]"))

        let reply = #"{"choices":[{"message":{"content":"[\"x\"]"}}]}"#
        XCTAssertEqual(AILyricsTranslator.messageContent(Data(reply.utf8)), "[\"x\"]")
        let parts = #"{"choices":[{"message":{"content":[{"type":"text","text":"[\"y\"]"}]}}]}"#
        XCTAssertEqual(AILyricsTranslator.messageContent(Data(parts.utf8)), "[\"y\"]")
    }

    func testSystemPromptCarriesCountAndOwnPrompt() {
        let prompt = AILyricsTranslator.systemPrompt(targetLanguage: "German", count: 7, customPrompt: "  Du statt Sie  ")
        XCTAssertTrue(prompt.contains("exactly 7 items"))
        XCTAssertTrue(prompt.hasSuffix("Du statt Sie"))
        XCTAssertFalse(AILyricsTranslator.systemPrompt(targetLanguage: "German", count: 1, customPrompt: " ").hasSuffix("\n"))
    }
}
