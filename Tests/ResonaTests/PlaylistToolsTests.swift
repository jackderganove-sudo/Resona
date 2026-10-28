//
//  PlaylistToolsTests.swift
//  ResonaTests
//
//  Automatic history playlists against a test history in the app's
//  database (simulator container), duplicate detection and playlist
//  splitting. All ids are prefixed "t4-" so real data is never touched.
//

import XCTest
@testable import Trop

final class PlaylistToolsTests: XCTestCase {
    private let db = DatabaseService.shared
    private let day: TimeInterval = 24 * 3600

    private func song(_ id: String, _ title: String, artist: String, album: String? = nil) -> SongEntity {
        SongEntity.merging(existing: nil, id: id, title: title, artistName: artist, albumName: album,
                           duration: 180, thumbnailUrl: nil)
    }

    private func play(_ id: String, daysAgo: Double, seconds: Int64) async throws {
        try await db.insert(Event(id: nil, songId: id, timestamp: Date().addingTimeInterval(-daysAgo * day), playTime: seconds * 1000))
    }

    /// Fixed test history (inserted once per test run, unique ids).
    private func seedHistory(prefix: String) async throws {
        for (id, title) in [("a", "Testlied Alpha"), ("b", "Testlied Beta"), ("c", "Testlied Gamma"), ("d", "Testlied Delta")] {
            try await db.insertOrReplace(song(prefix + id, title, artist: "Testkünstler"))
        }
        // A: often this month.          B: twice this month.
        // C: very often, but 60-90 days ago (forgotten favourite).
        // D: first and only play 5 days ago (new discovery).
        for d in [1.0, 3, 5, 8, 10] { try await play(prefix + "a", daysAgo: d, seconds: 200) }
        for d in [2.0, 3] { try await play(prefix + "b", daysAgo: d, seconds: 100) }
        for d in [60.0, 70, 80, 90] { try await play(prefix + "c", daysAgo: d, seconds: 400) }
        try await play(prefix + "d", daysAgo: 5, seconds: 50)
    }

    func testHistoryPlaylists() async throws {
        let prefix = "t4-\(UUID().uuidString.prefix(6))-"
        try await seedHistory(prefix: prefix)
        func ids(_ kind: HistoryPlaylistKind) async throws -> [String] {
            try await kind.songs().map(\.id).filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
        }
        let month = try await ids(.topMonth)
        XCTAssertEqual(month, ["a", "b", "d"], "this month by play time; C is too old")
        let allTime = try await ids(.topAllTime)
        XCTAssertEqual(allTime, ["c", "a", "b", "d"], "all time by total play time")
        let forgotten = try await ids(.forgotten)
        XCTAssertEqual(forgotten, ["c"], "≥ 3 plays, none in the last 30 days")
        let discoveries = try await ids(.newDiscoveries)
        XCTAssertEqual(Set(discoveries), ["a", "b", "d"], "first played in the last 14 days")
        XCTAssertFalse(discoveries.contains("c"))
    }

    func testDuplicatesInPlaylist() async throws {
        let prefix = "t4-\(UUID().uuidString.prefix(6))-"
        let playlist = prefix + "playlist"
        try await db.insertOrReplace(song(prefix + "1", "Platzhalter Eins", artist: "Testband"))
        try await db.insertOrReplace(song(prefix + "2", "Platzhalter Zwei", artist: "Testband"))
        // Same title + artist as #2 under another video id (re-upload).
        try await db.insertOrReplace(song(prefix + "3", "Platzhalter Zwei", artist: "Testband"))
        try await db.insertOrReplace(song(prefix + "4", "Platzhalter Zwei", artist: "Andere Band"))
        let entries: [(String, String)] = [("1", "s1"), ("2", "s2"), ("1", "s3"), ("3", "s4"), ("4", "s5")]
        for (position, entry) in entries.enumerated() {
            try await db.insert(PlaylistSongMap(id: nil, playlistId: playlist, songId: prefix + entry.0,
                                                position: position, setVideoId: entry.1))
        }
        let duplicates = await PlaylistTools.duplicates(in: playlist)
        XCTAssertEqual(duplicates.map(\.setVideoId), ["s3", "s4"],
                       "second occurrence of #1 and the re-upload of #2; same title by another artist stays")
        XCTAssertEqual(duplicates.map(\.songId), [prefix + "1", prefix + "3"])
    }

    func testNoDuplicatesInEmptyPlaylist() async {
        let duplicates = await PlaylistTools.duplicates(in: "t4-does-not-exist")
        XCTAssertTrue(duplicates.isEmpty)
    }

    // MARK: Split

    private func item(_ id: String, artist: String, album: String? = nil) -> SongItem {
        SongItem(videoId: id, title: "Titel \(id)", artists: [YTArtist(name: artist)], album: album,
                 duration: 180, isExplicit: false)
    }

    func testSplitByArtistMergesSmallGroups() {
        let songs = [
            item("1", artist: "X"), item("2", artist: "Y"), item("3", artist: "X"), item("4", artist: "Z"),
            item("5", artist: "Y"), item("6", artist: "X"), item("7", artist: "W"), item("8", artist: "Y"),
            item("9", artist: "X"), item("10", artist: "W")
        ]
        let groups = PlaylistTools.splitGroups(songs, title: "Mix", key: { $0.artists.first?.name ?? "" })
        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups[0].name, "Mix – X")
        XCTAssertEqual(groups[0].songs.map(\.videoId), ["1", "3", "6", "9"])
        XCTAssertEqual(groups[1].name, "Mix – Y")
        XCTAssertEqual(groups[1].songs.map(\.videoId), ["2", "5", "8"])
        // Z (1) and W (2) → "More", in order of first appearance.
        XCTAssertTrue(groups[2].name.hasPrefix("Mix – "))
        XCTAssertEqual(groups[2].songs.map(\.videoId), ["4", "7", "10"])
        XCTAssertEqual(groups.flatMap(\.songs).count, songs.count, "no song lost or duplicated")
    }

    func testSplitKeepsAtMostSevenGroups() {
        // 9 artists × 3 songs: 7 groups stay, the other 2 are merged into "More".
        let songs = (0..<27).map { item("\($0)", artist: "Künstler \($0 % 9)") }
        let groups = PlaylistTools.splitGroups(songs, title: "Alles", key: { $0.artists.first?.name ?? "" })
        XCTAssertEqual(groups.count, 8)
        XCTAssertEqual(groups.last?.songs.count, 6)
        XCTAssertEqual(Set(groups.flatMap(\.songs).map(\.videoId)).count, 27)
    }

    func testSplitByAlbum() {
        let songs = (0..<6).map { item("\($0)", artist: "A", album: $0 < 3 ? "Album Eins" : "Album Zwei") }
        let groups = PlaylistTools.splitGroups(songs, title: "P", key: { $0.album ?? "" })
        XCTAssertEqual(groups.map(\.name), ["P – Album Eins", "P – Album Zwei"])
    }
}
