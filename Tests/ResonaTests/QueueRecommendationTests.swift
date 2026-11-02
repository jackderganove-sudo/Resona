//
//  QueueRecommendationTests.swift
//  ResonaTests
//
//  Round 10 queue: YouTube recommendation chips (parsing, selection),
//  "Play next" as a move, multi-remove, replacing the upcoming songs.
//

import XCTest
import SwiftyTube
@testable import Trop

final class QueueRecommendationTests: XCTestCase {
    // MARK: Chips

    private func chip(_ title: String, selected: Bool = false, playlist: String, params: String? = "p-\(UUID().uuidString.prefix(4))",
                      deselect: Bool = false) -> [String: Any] {
        var renderer: [String: Any] = [
            "text": ["runs": [["text": title]]],
            "uniqueId": title,
            "isSelected": selected,
            "navigationEndpoint": ["queueUpdateCommand": ["fetchContentsCommand": ["watchEndpoint": [
                "playlistId": playlist, "params": params as Any
            ]]]]
        ]
        if deselect {
            renderer["onDeselectedCommand"] = ["watchEndpoint": ["playlistId": "RDAMVMseed01"]]
        }
        return ["chipCloudChipRenderer": renderer]
    }

    private func nextResponse(chips: [[String: Any]]) -> [String: Any] {
        ["contents": ["singleColumnMusicWatchNextResultsRenderer": ["tabbedRenderer": ["watchNextTabbedResultsRenderer": [
            "tabs": [["tabRenderer": ["content": ["musicQueueRenderer": [
                "subHeaderChipCloud": ["chipCloudRenderer": ["chips": chips]],
                "content": ["playlistPanelRenderer": ["contents": []]]
            ]]]]]
        ]]]]]
    }

    func testParsesChipsWithEndpointsAndSelection() {
        let json = nextResponse(chips: [
            chip("Alle", selected: true, playlist: "RDAMVMseed01", params: nil),
            chip("Beliebt", playlist: "RDATpopular", deselect: true),
            ["chipCloudChipRenderer": ["text": ["runs": [["text": "Ohne Ziel"]]], "navigationEndpoint": [:]]],
            chip("", playlist: "RDATempty")
        ])
        let chips = QueueChipParser.chips(from: json)
        XCTAssertEqual(chips.map(\.title), ["Alle", "Beliebt"])
        XCTAssertTrue(chips[0].isSelected)
        XCTAssertNil(chips[0].endpoint.params)
        XCTAssertEqual(chips[1].endpoint.playlistId, "RDATpopular")
        XCTAssertNotNil(chips[1].endpoint.params)
        XCTAssertEqual(chips[1].deselectEndpoint?.playlistId, "RDAMVMseed01")
        XCTAssertNotEqual(chips[0].id, chips[1].id)
    }

    func testNoChipsWithoutCloud() {
        XCTAssertTrue(QueueChipParser.chips(from: [:]).isEmpty)
    }

    func testAcceptMarksRequestedChipWhenServerSendsNoSelection() {
        let chips = QueueChipParser.chips(from: nextResponse(chips: [
            chip("Alle", selected: true, playlist: "RDAMVMseed01"),
            chip("Raritäten", playlist: "RDATrare")
        ]))
        let updated = QueueChipParser.accept(returned: [], previous: chips, requested: chips[1])
        XCTAssertEqual(updated.map(\.isSelected), [false, true])

        // Server reply with its own selection wins.
        var returned = chips
        returned[0].isSelected = true
        returned[1].isSelected = false
        XCTAssertEqual(QueueChipParser.accept(returned: returned, previous: updated, requested: chips[1]).map(\.isSelected), [true, false])
    }

    // MARK: Queue edits

    private func songs(_ ids: [String]) -> [SongItem] {
        ids.map { SongItem(videoId: $0, title: "Platzhalter \($0)", artists: [YTArtist(name: "Testband")], duration: 200, isExplicit: false) }
    }

    func testPlayNextMovesBehindCurrent() {
        let queue = songs(["a", "b", "c", "d", "e"])
        let result = QueueEditing.movingToNext(queue, current: 1, indices: IndexSet(integer: 4))
        XCTAssertEqual(result.songs.map(\.videoId), ["a", "b", "e", "c", "d"])
        XCTAssertEqual(result.current, 1)
    }

    func testPlayNextFromHistoryShiftsCurrentIndex() {
        let queue = songs(["a", "b", "c", "d"])
        let result = QueueEditing.movingToNext(queue, current: 2, indices: IndexSet([0, 3]))
        XCTAssertEqual(result.songs.map(\.videoId), ["b", "c", "a", "d"])
        XCTAssertEqual(result.current, 1)
        XCTAssertEqual(result.songs[result.current].videoId, "c")
    }

    func testPlayNextIgnoresCurrentSong() {
        let queue = songs(["a", "b", "c"])
        let result = QueueEditing.movingToNext(queue, current: 1, indices: IndexSet(integer: 1))
        XCTAssertEqual(result.songs.map(\.videoId), ["a", "b", "c"])
        XCTAssertEqual(result.current, 1)
    }

    func testRemoveKeepsCurrentSong() {
        let queue = songs(["a", "b", "c", "d", "e"])
        let result = QueueEditing.removing(queue, current: 2, indices: IndexSet([0, 2, 4]))
        XCTAssertEqual(result.songs.map(\.videoId), ["b", "c", "d"])
        XCTAssertEqual(result.songs[result.current].videoId, "c")
    }

    func testReplacingUpcomingKeepsHistoryAndDropsDuplicates() {
        let queue = songs(["a", "b", "c", "d"])
        let result = QueueEditing.replacingUpcoming(queue, current: 1, with: songs(["b", "x", "a", "y", "x"]))
        XCTAssertEqual(result.map(\.videoId), ["a", "b", "x", "y"])
    }
}
