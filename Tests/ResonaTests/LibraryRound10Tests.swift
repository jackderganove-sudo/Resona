//
//  LibraryRound10Tests.swift
//  ResonaTests
//
//  Round 10 library: CSV export, local music file names and ids.
//

import XCTest
import SwiftyTube
@testable import Trop

final class LibraryRound10Tests: XCTestCase {
    func testCSVQuotesAndFormats() {
        let songs = [
            SongItem(videoId: "abc123", title: "Platzhalter, \"Teil 2\"", artists: [YTArtist(name: "Band A"), YTArtist(name: "Band B")],
                     album: "Testalbum", duration: 245, isExplicit: false),
            SongItem(videoId: "xyz789", title: "Ohne Album", artists: [], duration: 3725, isExplicit: false)
        ]
        let lines = PlaylistCSV.csv(for: songs).components(separatedBy: "\r\n")
        XCTAssertEqual(lines[0], "Title,Artists,Album,Duration,Video ID,URL")
        XCTAssertEqual(lines[1], "\"Platzhalter, \"\"Teil 2\"\"\",\"Band A, Band B\",Testalbum,4:05,abc123,https://music.youtube.com/watch?v=abc123")
        XCTAssertEqual(lines[2], "Ohne Album,,,1:02:05,xyz789,https://music.youtube.com/watch?v=xyz789")
        XCTAssertEqual(lines.last, "")
    }

    func testCSVFileHasBOMAndSafeName() throws {
        let url = try PlaylistCSV.writeFile(title: "Mix/Test: 1", songs: [])
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(url.lastPathComponent, "Mix-Test- 1.csv")
        let data = try Data(contentsOf: url)
        XCTAssertEqual(Array(data.prefix(3)), [0xEF, 0xBB, 0xBF])
    }

    func testLocalFileNameParsing() {
        XCTAssertEqual(LocalMusicLibrary.parseFileName("03 - Testband - Erfundener Titel").artist, "Testband")
        XCTAssertEqual(LocalMusicLibrary.parseFileName("03 - Testband - Erfundener Titel").title, "Erfundener Titel")
        XCTAssertEqual(LocalMusicLibrary.parseFileName("Nur_ein_Titel").title, "Nur ein Titel")
        XCTAssertNil(LocalMusicLibrary.parseFileName("Nur_ein_Titel").artist)
    }

    func testLocalIds() {
        XCTAssertTrue(LocalMusicLibrary.isLocal("local-1234"))
        XCTAssertFalse(LocalMusicLibrary.isLocal("dQw4w9WgXcQ"))
        XCTAssertNil(LocalMusicLibrary.fileURL(for: "dQw4w9WgXcQ"))
        XCTAssertNil(LocalMusicLibrary.fileURL(for: "local-does-not-exist"))
    }
}
