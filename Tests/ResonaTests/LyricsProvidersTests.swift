//
//  LyricsProvidersTests.swift
//  ResonaTests
//
//  New lyrics sources (response parsing with invented payloads — no real
//  lyrics) and the version ranking.
//

import XCTest
@testable import Trop

final class LyricsProvidersTests: XCTestCase {
    private let lrc = "[00:01.00]la la erste Zeile\n[00:04.50]zweite Zeile mit Wort\n[00:08.00]dritte Reihe hier"

    func testSimpMusicParsesAndPrefersClosestDuration() {
        let json: [String: Any] = [
            "type": "success",
            "data": [
                ["songTitle": "Platzhalter (Remix)", "artistName": "Testband", "durationSeconds": 200, "syncedLyrics": lrc],
                ["songTitle": "Platzhalter", "artistName": "Testband", "durationSeconds": 181, "syncedLyrics": lrc],
                ["songTitle": "Nur Text", "artistName": "Testband", "durationSeconds": 150, "plainLyric": "zeile eins\nzeile zwei"]
            ]
        ]
        let candidates = SimpMusicLyricsProvider.parse(json, queryDuration: 180)
        XCTAssertEqual(candidates.count, 3)
        XCTAssertEqual(candidates.first?.title, "Platzhalter")
        XCTAssertTrue(candidates.allSatisfy(\.exactVersion), "keyed by the video id")
        XCTAssertEqual(candidates.first?.lines.count, 3)
        XCTAssertEqual(candidates.first?.lines[1].startTime ?? 0, 4.5, accuracy: 0.001)
        XCTAssertEqual(candidates.last?.lines.map(\.text), ["zeile eins", "zeile zwei"])
        XCTAssertTrue(SimpMusicLyricsProvider.parse(["type": "error"], queryDuration: 0).isEmpty)
    }

    func testUnisonCandidate() {
        let item: [String: Any] = ["id": 7, "videoId": "abc", "song": "Platzhalter", "artist": "Testband",
                                   "lyrics": lrc, "format": "lrc", "syncType": "line"]
        let exact = UnisonLyricsProvider.candidate(item, videoId: "abc")
        XCTAssertEqual(exact?.lines.count, 3)
        XCTAssertEqual(exact?.exactVersion, true)
        XCTAssertEqual(UnisonLyricsProvider.candidate(item, videoId: "other")?.exactVersion, false)
        XCTAssertNil(UnisonLyricsProvider.candidate(["song": "x"], videoId: nil))
    }

    func testMegalobizPages() {
        let search = #"<a class="entity_name" href="/lrc/maker/download/12345/platzhalter-testband">Platzhalter</a>"#
        XCTAssertEqual(MegalobizLyricsProvider.firstLrcPath(in: search), "/lrc/maker/download/12345/platzhalter-testband")
        let detail = #"<span id="lrc_12345_details" class="x">[00:01.00]la &amp; la<br />[00:03.00]zweite &#39;Zeile&#39;<br/></span>"#
        let lines = MegalobizLyricsProvider.lrcLines(fromDetailPage: detail)
        XCTAssertEqual(lines.map(\.text), ["la & la", "zweite 'Zeile'"])
        XCTAssertEqual(lines.last?.startTime ?? 0, 3, accuracy: 0.001)
    }

    func testQQMusicSearchAndJSONP() throws {
        let body = #"callback({"data":{"song":{"list":[{"songmid":"m1","songname":"Platzhalter &amp; Co","interval":181,"singer":[{"name":"Testband"},{"name":"Gast"}]}]}}})"#
        let json = try QQMusicLyricsProvider.decodeJSONP(Data(body.utf8))
        let songs = QQMusicLyricsProvider.parseSearch(json)
        XCTAssertEqual(songs, [QQMusicLyricsProvider.Song(mid: "m1", title: "Platzhalter & Co", artist: "Testband, Gast", duration: 181)])
    }

    func testFormatDetection() {
        XCTAssertEqual(ProviderLyricsFormat.lines(from: lrc).count, 3)
        XCTAssertNil(ProviderLyricsFormat.lines(from: "eins\nzwei").first?.startTime)
        XCTAssertTrue(ProviderLyricsFormat.lines(from: "  ").isEmpty)
    }

    func testVersionHint() {
        XCTAssertEqual(LyricsService.versionHint("Platzhalter (NovaX Remix)"), "novax remix")
        XCTAssertEqual(LyricsService.versionHint("Platzhalter - Radio Edit"), "radio edit")
        XCTAssertEqual(LyricsService.versionHint("Platzhalter [Live]"), "live")
        XCTAssertNil(LyricsService.versionHint("Platzhalter"))
        XCTAssertNil(LyricsService.versionHint("Platzhalter (feat. Gast)"))
    }

    func testRankingPrefersThisVersionForRemixes() {
        let remix = LyricsQuery(title: "Platzhalter", artist: "Testband", album: nil, duration: 200, videoId: "abc",
                                versionHint: "novax remix")
        let plain = LyricsQuery(title: "Platzhalter", artist: "Testband", album: nil, duration: 200, videoId: "abc")
        let originalWord = LyricsCandidate(lines: [], title: "Platzhalter", artist: "Testband", duration: nil)
        let exactLine = LyricsCandidate(lines: [], title: "Platzhalter (NovaX Remix)", artist: "Testband", duration: 200, exactVersion: true)
        // Remix: version-exact line-synced beats the original's word-synced.
        XCTAssertGreaterThan(LyricsManager.score(quality: .lineSynced, order: 3, candidate: exactLine, query: remix),
                             LyricsManager.score(quality: .wordSynced, order: 0, candidate: originalWord, query: remix))
        // Normal song: word-synced stays first; same quality → this version.
        XCTAssertGreaterThan(LyricsManager.score(quality: .wordSynced, order: 0, candidate: originalWord, query: plain),
                             LyricsManager.score(quality: .lineSynced, order: 3, candidate: exactLine, query: plain))
        XCTAssertGreaterThan(LyricsManager.score(quality: .lineSynced, order: 3, candidate: exactLine, query: plain),
                             LyricsManager.score(quality: .lineSynced, order: 0, candidate: originalWord, query: plain))
        // A length far off counts against a candidate.
        let wrongLength = LyricsCandidate(lines: [], title: "Platzhalter", artist: "Testband", duration: 150)
        XCTAssertLessThan(LyricsManager.score(quality: .lineSynced, order: 0, candidate: wrongLength, query: plain),
                          LyricsManager.score(quality: .lineSynced, order: 0, candidate: originalWord, query: plain))
    }
}
