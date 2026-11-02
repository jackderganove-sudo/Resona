//
//  HomeDiscoveryTests.swift
//  ResonaTests
//
//  Round 10 home: staggered genre layout, daily genre pick, featured
//  playlist shelves, varied Quick Picks.
//

import XCTest
import SwiftyTube
@testable import Trop

final class HomeDiscoveryTests: XCTestCase {
    func testShapeAndHeightAreStablePerTitle() {
        XCTAssertEqual(GenreTileShape.of("Platzhalter-Pop"), GenreTileShape.of("platzhalter-pop"))
        XCTAssertEqual(GenreLayout.height(for: "Testgenre"), GenreLayout.height(for: "Testgenre"))
        let heights = Set(["A", "B", "C", "D", "E", "F", "G", "H"].map { GenreLayout.height(for: $0) })
        XCTAssertGreaterThan(heights.count, 1, "tiles should not all be the same height")
    }

    func testMasonryFillsShortestColumn() {
        let heights: [String: CGFloat] = ["a": 100, "b": 50, "c": 50, "d": 50]
        let columns = GenreLayout.columns(["a", "b", "c", "d"], count: 2, height: { heights[$0]! }, spacing: 0)
        XCTAssertEqual(columns, [["a", "d"], ["b", "c"]])
    }

    func testDailyPickIsStableWithinADay() {
        let items = Array(0..<30)
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let first = GenreLayout.daily(items, count: 10, day: day)
        XCTAssertEqual(first, GenreLayout.daily(items, count: 10, day: day.addingTimeInterval(60)))
        XCTAssertEqual(first.count, 10)
        XCTAssertEqual(Set(first).count, 10)
        XCTAssertNotEqual(first, GenreLayout.daily(items, count: 10, day: day.addingTimeInterval(86_400 * 3)))
        XCTAssertEqual(GenreLayout.daily([1, 2], count: 10), [1, 2])
    }

    func testGenreShapesProducePaths() {
        let rect = CGRect(x: 0, y: 0, width: 180, height: 120)
        for kind in GenreTileShape.allCases {
            XCTAssertFalse(GenreShape(kind: kind).path(in: rect).isEmpty, "\(kind)")
        }
    }

    func testFeaturedShelfNeedsMostlyPlaylists() {
        func playlist(_ id: String) -> YTItem { .playlist(PlaylistItem(id: id, title: "Platzhalter \(id)")) }
        func song(_ id: String) -> YTItem { .song(SongItem(videoId: id, title: "Lied \(id)", artists: [], duration: 100, isExplicit: false)) }
        XCTAssertTrue(FeaturedShelf.isPlaylistShelf([playlist("1"), playlist("2"), song("3")]))
        XCTAssertFalse(FeaturedShelf.isPlaylistShelf([playlist("1"), song("2"), song("3")]))
        XCTAssertFalse(FeaturedShelf.isPlaylistShelf([playlist("1"), playlist("2")]))
    }

    func testQuickPicksLimitSongsPerArtistAtTheStart() {
        func song(_ id: String, _ artist: String) -> SongItem {
            SongItem(videoId: id, title: "Lied \(id)", artists: [YTArtist(name: artist)], duration: 200, isExplicit: false)
        }
        let songs = [song("1", "Band A"), song("2", "Band A"), song("3", "band a"), song("4", "Band B"), song("5", "Band A")]
        XCTAssertEqual(QuickPicksMix.diversified(songs).map(\.videoId), ["1", "2", "4", "3", "5"])
    }
}
