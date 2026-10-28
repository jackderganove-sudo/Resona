//
//  LyricsTimingTests.swift
//  ResonaTests
//
//  Slowed / sped-up detection and scaling, "fake synced" → plain text,
//  stable line IDs, active line and scroll retargeting. Placeholder texts
//  only (no real lyrics).
//

import XCTest
@testable import Trop

final class LyricsTimingTests: XCTestCase {
    /// Lines every 4 s from `start`, two words each with word timing.
    private func synced(_ count: Int, start: Double = 10, step: Double = 4) -> [LyricLine] {
        (0..<count).map { i in
            let t = start + Double(i) * step
            return LyricLine(text: "Platzhalter Zeile \(i)", startTime: t,
                             words: [LyricWord(text: "Platzhalter ", start: t, end: t + 1),
                                     LyricWord(text: "Zeile \(i)", start: t + 1, end: t + 2)])
        }
    }

    // MARK: Speed variants

    func testSpeedVariantTitles() {
        for title in ["Platzhalter (Slowed + Reverb)", "Platzhalter - sped up", "Platzhalter SUPER SLOWED",
                      "Platzhalter nightcore", "Platzhalter (Speed Up)", "Platzhalter daycore"] {
            XCTAssertTrue(LyricsService.isSpeedVariant(title), title)
        }
        for title in ["Slow Platzhalter", "Platzhalter (Remastered)", "Reverberation", "Speedway Lied"] {
            XCTAssertFalse(LyricsService.isSpeedVariant(title), title)
        }
    }

    func testSlowedVariantIsScaled() {
        // Original 200 s, slowed upload 230 s → factor 1.15.
        let lines = synced(40)   // last line at 166 s
        let result = LyricsService.tempoAdjusted(lines, played: 230, original: 200, isSpeedVariant: true)
        XCTAssertEqual(result.tempo ?? 0, 1.15, accuracy: 0.0001)
        XCTAssertEqual(result.lines.count, lines.count)
        for (scaled, original) in zip(result.lines, lines) {
            XCTAssertEqual(scaled.startTime ?? 0, (original.startTime ?? 0) * 1.15, accuracy: 0.0001)
            XCTAssertEqual(scaled.words?.first?.start ?? 0, (original.words?.first?.start ?? 0) * 1.15, accuracy: 0.0001)
            XCTAssertEqual(scaled.words?.last?.end ?? 0, (original.words?.last?.end ?? 0) * 1.15, accuracy: 0.0001)
            XCTAssertEqual(scaled.id, original.id, "scaling keeps the line id")
            XCTAssertEqual(scaled.text, original.text)
        }
    }

    func testSpedUpVariantIsScaledDown() {
        let lines = synced(40)
        let result = LyricsService.tempoAdjusted(lines, played: 170, original: 200, isSpeedVariant: true)
        XCTAssertEqual(result.tempo ?? 0, 0.85, accuracy: 0.0001)
        XCTAssertEqual(result.lines.last?.startTime ?? 0, 166 * 0.85, accuracy: 0.0001)
    }

    func testOriginalTimingWithoutVariantTitleIsDetectedByMismatch() {
        // Provider returned the original (last line 166 s) for a 150 s song
        // whose title doesn't say "slowed": mismatch → scaled anyway.
        let lines = synced(40)
        XCTAssertTrue(LyricsService.needsOriginalDuration(lines, played: 150, isSpeedVariant: false))
        let result = LyricsService.tempoAdjusted(lines, played: 150, original: 180, isSpeedVariant: false)
        XCTAssertEqual(result.tempo ?? 0, 150.0 / 180.0, accuracy: 0.0001)
    }

    func testMatchingLengthIsUntouched() {
        let lines = synced(40)
        XCTAssertFalse(LyricsService.needsOriginalDuration(lines, played: 200, isSpeedVariant: false))
        let same = LyricsService.tempoAdjusted(lines, played: 200, original: nil, isSpeedVariant: false)
        XCTAssertNil(same.tempo)
        XCTAssertEqual(same.lines, lines)
        // Variant title but practically the same length (< 2 %): untouched.
        let close = LyricsService.tempoAdjusted(lines, played: 202, original: 200, isSpeedVariant: true)
        XCTAssertNil(close.tempo)
        XCTAssertEqual(close.lines, lines)
    }

    func testImplausibleFactorFallsBackToPlainText() {
        // Timestamps run past the song and the "original" would mean 0.4×.
        let lines = synced(40)
        let result = LyricsService.tempoAdjusted(lines, played: 80, original: 200, isSpeedVariant: true)
        XCTAssertNil(result.tempo)
        XCTAssertTrue(result.lines.allSatisfy { $0.startTime == nil }, "no wrong timing — plain text")
        XCTAssertEqual(result.lines.map(\.text), lines.map(\.text))
    }

    func testMismatchWithoutOriginalLengthFallsBackToPlainText() {
        let lines = synced(40)
        let result = LyricsService.tempoAdjusted(lines, played: 120, original: nil, isSpeedVariant: false)
        XCTAssertTrue(result.lines.allSatisfy { $0.startTime == nil })
    }

    func testPlainLyricsNeedNoTempoCheck() {
        let plain = (0..<5).map { LyricLine(text: "nur Text \($0)", startTime: nil) }
        XCTAssertFalse(LyricsService.needsOriginalDuration(plain, played: 100, isSpeedVariant: true))
        XCTAssertEqual(LyricsService.tempoAdjusted(plain, played: 100, original: 300, isSpeedVariant: true).lines, plain)
    }

    // MARK: Tempo check with diagnosis

    private func query(played: Double, variant: Bool) -> LyricsQuery {
        LyricsQuery(title: "Platzhalter", artist: "Testkanal", album: nil, duration: played, isSpeedVariant: variant)
    }

    func testCheckTempoAppliesFactorWithKnownOriginal() async {
        let checked = await LyricsService.checkTempo(synced(40), query: query(played: 230, variant: true),
                                                     knownOriginal: 200, source: "test")
        XCTAssertEqual(checked.info.outcome, .applied)
        XCTAssertEqual(checked.info.factor ?? 0, 1.15, accuracy: 0.0001)
        XCTAssertEqual(checked.info.original, 200)
        XCTAssertEqual(checked.info.source, "test")
        XCTAssertTrue(checked.info.isRelevant)
        XCTAssertEqual(checked.lines.last?.startTime ?? 0, 166 * 1.15, accuracy: 0.0001)
    }

    func testCheckTempoReasons() async {
        let same = await LyricsService.checkTempo(synced(40), query: query(played: 201, variant: true), knownOriginal: 200, source: nil)
        XCTAssertEqual(same.info.outcome, .sameLength)
        let far = await LyricsService.checkTempo(synced(40), query: query(played: 500, variant: true), knownOriginal: 200, source: nil)
        XCTAssertEqual(far.info.outcome, .implausible)
        let unknown = await LyricsService.checkTempo(synced(40), query: query(played: 0, variant: true), knownOriginal: nil, source: nil)
        XCTAssertEqual(unknown.info.outcome, .unknownLength)
        let normal = await LyricsService.checkTempo(synced(40), query: query(played: 200, variant: false), knownOriginal: nil, source: nil)
        XCTAssertEqual(normal.info.outcome, .notNeeded)
        XCTAssertFalse(normal.info.isRelevant, "normal songs show no tempo note")
    }

    func testLyricsOverlapMatchesSameTextOnly() {
        let lines = [
            LyricLine(text: "la la erste Zeile hier", startTime: 1),
            LyricLine(text: "zweite Zeile mit Wort Wort", startTime: 4),
            LyricLine(text: "dritte Reihe ganz am Ende", startTime: 8)
        ]
        let sameSongLRC = "[00:01.00] La la, erste Zeile hier!\n[00:04.00] Zweite Zeile mit Wort-Wort\n[00:08.00] Dritte Reihe ganz am Ende"
        XCTAssertEqual(LyricsService.lyricsOverlap(lines, candidateText: sameSongLRC), 1, accuracy: 0.001)
        let otherSong = "[00:01.00] ganz andere Silben\n[00:04.00] nichts davon passt hier"
        XCTAssertEqual(LyricsService.lyricsOverlap(lines, candidateText: otherSong), 0, accuracy: 0.001)
        XCTAssertEqual(LyricsService.lyricsOverlap(lines, candidateText: ""), 0)
    }

    // MARK: "Fake synced" → plain

    func testAllTimesZeroBecomePlainText() {
        let fake = (0..<6).map { LyricLine(text: "la la Zeile \($0)", startTime: 0) }
        let normalized = LyricLine.normalizedTiming(fake)
        XCTAssertTrue(normalized.allSatisfy { $0.startTime == nil })
        XCTAssertEqual(normalized.map(\.text), fake.map(\.text))
        XCTAssertEqual(LyricsQuality.of(normalized), .plain)
    }

    func testAllTimesEqualButNotZeroBecomePlainText() {
        let fake = (0..<4).map { LyricLine(text: "Zeile \($0)", startTime: 12.5) }
        XCTAssertTrue(LyricLine.normalizedTiming(fake).allSatisfy { $0.startTime == nil })
    }

    func testRealTimingIsKept() {
        let lines = synced(5)
        XCTAssertEqual(LyricLine.normalizedTiming(lines), lines)
        // Two lines at 0 are not enough to call it fake.
        let short = [LyricLine(text: "a", startTime: 0), LyricLine(text: "b", startTime: 0)]
        XCTAssertEqual(LyricLine.normalizedTiming(short), short)
    }

    func testQualityRanking() {
        XCTAssertEqual(LyricsQuality.of(synced(5)), .wordSynced)
        let lineSynced = (0..<5).map { LyricLine(text: "Zeile \($0)", startTime: Double($0) * 3) }
        XCTAssertEqual(LyricsQuality.of(lineSynced), .lineSynced)
        XCTAssertLessThan(LyricsQuality.plain, LyricsQuality.lineSynced)
        XCTAssertLessThan(LyricsQuality.lineSynced, LyricsQuality.wordSynced)
    }

    // MARK: Stable IDs

    /// Refrain: the same placeholder line several times.
    private func refrainSong() -> [LyricLine] {
        let texts = ["Strophe eins", "Refrain la la la", "Refrain oh oh", "Strophe zwei",
                     "Refrain la la la", "Refrain oh oh", "Refrain la la la", "Refrain oh oh"]
        return texts.enumerated().map { LyricLine(text: $1, startTime: 5 + Double($0) * 3.5) }
    }

    func testRefrainLinesGetUniqueIds() {
        let lines = LyricLine.stable(refrainSong())
        XCTAssertEqual(Set(lines.map(\.id)).count, lines.count, "identical refrain lines must not share an id")
    }

    func testIdsAreStableAcrossReloads() {
        // Every reload builds new LyricLine values (fresh UUIDs) — the
        // stable ids must come out identical, otherwise SwiftUI would
        // rebuild every row (the old doubling/jumping bug).
        let first = LyricLine.stable(refrainSong())
        let second = LyricLine.stable(refrainSong())
        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertTrue(zip(first, second).allSatisfy { $0.sameContent(as: $1) })
        // Scaling (tempo) keeps them too.
        XCTAssertEqual(LyricLine.scaled(first, by: 1.1).map(\.id), first.map(\.id))
    }

    // MARK: Active line / scrolling

    func testActiveIndex() {
        let lines = refrainSong()   // 5, 8.5, 12, …
        XCTAssertEqual(LyricsTiming.activeIndex(in: lines, at: 0), -1, "intro: no active line")
        XCTAssertEqual(LyricsTiming.activeIndex(in: lines, at: 5), 0)
        XCTAssertEqual(LyricsTiming.activeIndex(in: lines, at: 8.49), 0)
        XCTAssertEqual(LyricsTiming.activeIndex(in: lines, at: 8.5), 1)
        XCTAssertEqual(LyricsTiming.activeIndex(in: lines, at: 1000), lines.count - 1)
    }

    func testActiveIndexIsMonotonicThroughTheSong() {
        let lines = refrainSong()
        var previous = -1
        var changes = 0
        for step in 0...4000 {
            let index = LyricsTiming.activeIndex(in: lines, at: Double(step) * 0.01)
            XCTAssertGreaterThanOrEqual(index, previous)
            if index != previous { changes += 1 }
            previous = index
        }
        XCTAssertEqual(changes, lines.count, "exactly one change per line")
    }

    /// Simulates the stage: every 10 ms the scroll line is computed (with
    /// the lead) and its target sent to the scroller, including sub-pixel
    /// jitter from row measurements. The scroller may only retarget when
    /// the line changes.
    @MainActor
    func testScrollerRetargetsOnlyOnLineChange() {
        let lines = LyricLine.stable(refrainSong())
        let rowHeight: CGFloat = 72
        let scroller = LyricsScroller()
        scroller.displayScale = 2
        var targets: [CGFloat] = []
        var lineChanges = 0
        var lastIndex = Int.min
        for step in 0...4000 {
            let t = Double(step) * 0.01
            let index = max(0, LyricsTiming.activeIndex(in: lines, at: t + LyricsTiming.scrollLead))
            if index != lastIndex { lineChanges += 1; lastIndex = index }
            let jitter = CGFloat(step % 3) * 0.15   // < 0.5 pt measurement noise
            scroller.animate(to: CGFloat(index) * rowHeight + jitter, reason: .lineChange)
            if targets.last != scroller.target { targets.append(scroller.target) }
        }
        XCTAssertEqual(targets.count, lineChanges, "one retarget per line change, none from jitter")
        XCTAssertEqual(targets, targets.sorted(), "never scrolls back on its own")
    }

    @MainActor
    func testScrollerPublishesWholePixels() {
        let scroller = LyricsScroller()
        scroller.displayScale = 3
        scroller.jump(to: 100.1234, reason: .initial)
        XCTAssertEqual(scroller.y * 3, (scroller.y * 3).rounded(), accuracy: 0.0001)
        scroller.drag(to: 47.77)
        XCTAssertEqual(scroller.y * 3, (scroller.y * 3).rounded(), accuracy: 0.0001)
    }
}
