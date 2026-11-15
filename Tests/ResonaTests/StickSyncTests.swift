//
//  StickSyncTests.swift
//  ResonaTests
//
//  Same cases as Resona-Android's ResonaFileLayoutTest for the stick layout
//  (round 12, point 7). Invented titles and artists only.
//

import XCTest
@testable import Trop

final class StickSyncTests: XCTestCase {
    private let songs: [String: StickPlan.SongInfo] = [
        "a": .init(title: "Erfundener Titel", artist: "Platzhalter Band"),
        "b": .init(title: "Was? Wie: Wo*", artist: "AC/DC-Ersatz"),
        "c": .init(title: "Dritter Song", artist: "Niemand"),
    ]

    private func plan(_ old: StickManifest, _ playlists: [StickPlan.Playlist]) -> ([StickStep], StickManifest) {
        StickPlan.plan(old: old, playlists: playlists, info: { self.songs[$0] })
    }

    func testNamesAreFat32SafeLikeAndroid() {
        XCTAssertEqual(StickFileNames.safe("Was? Wie: Wo*"), "Was_ Wie_ Wo_")
        XCTAssertEqual(StickFileNames.safe("AC/DC"), "AC_DC")
        XCTAssertEqual(StickFileNames.safe("..."), "_")
        XCTAssertEqual(StickFileNames.safe("CON"), "CON_")
        XCTAssertEqual(StickFileNames.safe("  a\t\nb . "), "a b")
        XCTAssertLessThanOrEqual(StickFileNames.safe(String(repeating: "x", count: 500)).utf16.count, 80)
        XCTAssertEqual(StickFileNames.song(number: 3, artist: "Platzhalter Band", title: "Erfundener Titel"),
                       "03 - Platzhalter Band - Erfundener Titel.m4a")
        XCTAssertEqual(StickFileNames.unique("x.m4a", taken: ["X.M4A"]), "x (2).m4a")
        XCTAssertEqual(StickFileNames.unique("x.m4a", taken: ["x.m4a", "x (2).m4a"]), "x (3).m4a")
    }

    func testReadsAndroidManifestWithoutDefaults() throws {
        // kotlinx leaves default values out: no version, size or format here.
        let json = #"{"songs":{"p1/a":{"path":"Mix/01 - Platzhalter Band - Erfundener Titel.m4a","title":"Erfundener Titel"}},"folders":{"p1":"Mix"}}"#
        let m = StickManifest.decode(Data(json.utf8))
        XCTAssertEqual(m.version, 1)
        XCTAssertEqual(m.songs["p1/a"]?.format, 0)
        XCTAssertEqual(m.folders["p1"], "Mix")
        XCTAssertEqual(StickManifest.decode(m.encoded()), m)
        XCTAssertEqual(StickManifest.decode(Data("{kaputt".utf8)), StickManifest())
    }

    func testFirstSyncThenNothing() {
        let playlists = [StickPlan.Playlist(id: "p1", name: "Mein Mix", songIds: ["a", "b"])]
        let (steps, first) = plan(StickManifest(), playlists)
        XCTAssertEqual(steps, [.add(songId: "a", path: "Mein Mix/01 - Platzhalter Band - Erfundener Titel.m4a"),
                               .add(songId: "b", path: "Mein Mix/02 - AC_DC-Ersatz - Was_ Wie_ Wo_.m4a")])
        var synced = first
        for key in synced.songs.keys { synced.songs[key]?.format = StickManifest.currentFormat }
        let (again, second) = plan(synced, playlists)
        XCTAssertTrue(again.isEmpty)
        XCTAssertEqual(second.songs.mapValues(\.path), first.songs.mapValues(\.path))
    }

    func testRenameRemoveRenumberAndOldFormat() {
        var (_, first) = plan(StickManifest(), [StickPlan.Playlist(id: "p1", name: "Mein Mix", songIds: ["a", "b", "c"])])
        for key in first.songs.keys { first.songs[key]?.format = StickManifest.currentFormat }
        first.songs["p1/c"]?.format = 1
        let (steps, _) = plan(first, [StickPlan.Playlist(id: "p1", name: "Neuer Name", songIds: ["b", "c"])])
        XCTAssertEqual(steps.first, .renameFolder(playlistId: "p1", from: "Mein Mix", to: "Neuer Name"))
        XCTAssertTrue(steps.contains(.delete(songId: "a", path: "Neuer Name/01 - Platzhalter Band - Erfundener Titel.m4a")))
        XCTAssertTrue(steps.contains(.move(songId: "b", from: "Neuer Name/02 - AC_DC-Ersatz - Was_ Wie_ Wo_.m4a",
                                           to: "Neuer Name/01 - AC_DC-Ersatz - Was_ Wie_ Wo_.m4a")))
        // c moves (03 → 02); its old format is rewritten only where it already lies.
        XCTAssertFalse(steps.contains { if case .add = $0 { return true } else { return false } })
    }

    func testDroppedPlaylistDeletesItsFolder() {
        let (_, first) = plan(StickManifest(), [StickPlan.Playlist(id: "p1", name: "Mix", songIds: ["a"]),
                                                StickPlan.Playlist(id: "p2", name: "Weg", songIds: ["c"])])
        let (steps, manifest) = plan(first, [StickPlan.Playlist(id: "p1", name: "Mix", songIds: ["a"])])
        XCTAssertTrue(steps.contains(.deleteFolder(playlistId: "p2", folder: "Weg")))
        XCTAssertFalse(steps.contains { if case .delete = $0 { return true } else { return false } })
        XCTAssertNil(manifest.folders["p2"])
    }
}
