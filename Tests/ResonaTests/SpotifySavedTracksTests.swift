//
//  SpotifySavedTracksTests.swift
//  ResonaTests
//
//  Round 10: parsing Spotify's fetchLibraryTracks answer (invented data)
//  and choosing the YouTube Music match.
//

import XCTest
import SwiftyTube
@testable import Trop

final class SpotifySavedTracksTests: XCTestCase {
    private func item(_ uri: String, _ name: String, artists: [String], duration: Int) -> [String: Any] {
        ["track": ["_uri": uri, "data": [
            "name": name,
            "artists": ["items": artists.map { ["uri": "spotify:artist:x", "profile": ["name": $0]] }],
            "albumOfTrack": ["name": "Platzhalteralbum", "coverArt": ["sources": [
                ["url": "https://example.com/64.jpg", "width": 64],
                ["url": "https://example.com/640.jpg", "width": 640],
                ["url": "https://example.com/1000.jpg", "width": 1000]
            ]]],
            "duration": ["totalMilliseconds": duration]
        ] as [String: Any]] as [String: Any]]
    }

    func testParsesLibraryTracksAndSkipsLocalFiles() throws {
        let json: [String: Any] = ["data": ["me": ["library": ["tracks": [
            "totalCount": 3,
            "items": [
                item("spotify:track:a", "Erfundenes Lied", artists: ["Band Eins", "Gast"], duration: 201_000),
                item("spotify:local:x", "Lokale Datei", artists: ["Niemand"], duration: 100_000),
                ["track": ["_uri": "spotify:track:empty", "data": ["name": ""]]]
            ]
        ]]]]]
        let page = try XCTUnwrap(SpotifyLibraryAPI.parse(json))
        XCTAssertEqual(page.total, 3)
        XCTAssertEqual(page.tracks.count, 1)
        let track = page.tracks[0]
        XCTAssertEqual(track.id, "spotify:track:a")
        XCTAssertEqual(track.artistLine, "Band Eins, Gast")
        XCTAssertEqual(track.album, "Platzhalteralbum")
        XCTAssertEqual(track.coverURL, "https://example.com/640.jpg")
        XCTAssertEqual(track.durationMs, 201_000)
    }

    func testUnexpectedAnswer() {
        XCTAssertNil(SpotifyLibraryAPI.parse(["errors": []]))
    }

    func testMatchPrefersSimilarDuration() {
        let track = SpotifySavedTrack(id: "spotify:track:a", title: "Lied", artists: ["Band"], album: nil, coverURL: nil, durationMs: 200_000)
        let songs = [
            SongItem(videoId: "long", title: "Lied (Extended)", artists: [], duration: 400, isExplicit: false),
            SongItem(videoId: "match", title: "Lied", artists: [], duration: 205, isExplicit: false)
        ]
        XCTAssertEqual(SpotifyMatcher.best(songs, for: track)?.videoId, "match")
        XCTAssertEqual(SpotifyMatcher.best([songs[0]], for: track)?.videoId, "long")
        XCTAssertNil(SpotifyMatcher.best([], for: track))
    }
}
