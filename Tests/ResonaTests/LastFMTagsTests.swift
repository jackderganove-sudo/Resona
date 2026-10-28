//
//  LastFMTagsTests.swift
//  ResonaTests
//
//  Last.fm tag parsing and the genre/mood mapping used by "Split playlist".
//  Responses are invented fixtures; nothing is requested from Last.fm.
//

import XCTest
@testable import Trop

final class LastFMTagsTests: XCTestCase {
    private func json(_ name: String) throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func tags(_ pairs: (String, Int)...) -> [LastFMTag] {
        pairs.map { LastFMTag(name: $0.0, count: $0.1) }
    }

    func testParseTopTags() throws {
        let parsed = LastFMTagService.parse(try json("lastfm-toptags"))
        XCTAssertEqual(parsed.map(\.name), ["phonk", "drift phonk", "Hip-Hop", "trap"], "tags under weight 5 are dropped")
        XCTAssertEqual(parsed.first?.count, 100)
    }

    func testParseErrorMeansNoTags() throws {
        XCTAssertTrue(LastFMTagService.parse(try json("lastfm-error")).isEmpty)
        XCTAssertTrue(LastFMTagService.parse(["toptags": ["tag": [Any]()]]).isEmpty)
        // A single tag comes as an object instead of an array.
        let single = LastFMTagService.parse(["toptags": ["tag": ["name": "rock", "count": 100]]])
        XCTAssertEqual(single.map(\.name), ["rock"])
    }

    func testSingleTagGroups() {
        XCTAssertEqual(GenreMoodClassifier.group(of: "Hip-Hop"), .hipHop)
        XCTAssertEqual(GenreMoodClassifier.group(of: "hiphop"), .hipHop)
        XCTAssertEqual(GenreMoodClassifier.group(of: "german hip hop"), .hipHop)
        XCTAssertEqual(GenreMoodClassifier.group(of: "alternative metal"), .metal)
        XCTAssertEqual(GenreMoodClassifier.group(of: "dream pop"), .chillSad, "exact match beats the 'pop' suffix")
        XCTAssertEqual(GenreMoodClassifier.group(of: "Lo-Fi"), .chillSad)
        XCTAssertEqual(GenreMoodClassifier.group(of: "drum and bass"), .electronic)
        XCTAssertEqual(GenreMoodClassifier.group(of: "pop punk"), .rock)
        XCTAssertNil(GenreMoodClassifier.group(of: "seen live"))
        XCTAssertNil(GenreMoodClassifier.group(of: "favorites"))
    }

    func testPhonkWinsOverHipHop() throws {
        let parsed = LastFMTagService.parse(try json("lastfm-toptags"))
        XCTAssertEqual(GenreMoodClassifier.classify(parsed), .phonk)
        // Even when hip-hop is the top tag, a clear phonk tag decides.
        XCTAssertEqual(GenreMoodClassifier.classify(tags(("hip-hop", 100), ("trap", 80), ("phonk", 40))), .phonk)
    }

    func testMoodBeatsWeakGenre() {
        XCTAssertEqual(GenreMoodClassifier.classify(tags(("pop", 100), ("sad", 90), ("melancholic", 60))), .chillSad)
        XCTAssertEqual(GenreMoodClassifier.classify(tags(("pop", 100), ("dance pop", 70), ("sad", 10))), .pop)
    }

    func testGenreVotes() {
        XCTAssertEqual(GenreMoodClassifier.classify(tags(("rock", 100), ("alternative rock", 60), ("indie", 20))), .rock)
        XCTAssertEqual(GenreMoodClassifier.classify(tags(("electronic", 100), ("house", 70), ("pop", 30))), .electronic)
        XCTAssertEqual(GenreMoodClassifier.classify(tags(("rnb", 100), ("soul", 50))), .rnb)
        XCTAssertNil(GenreMoodClassifier.classify(tags(("seen live", 100), ("favorites", 50))))
        XCTAssertNil(GenreMoodClassifier.classify([]))
    }

    func testEveryGroupHasATitleAndKeywords() {
        for group in GenreMood.allCases {
            XCTAssertFalse(group.title.isEmpty)
            XCTAssertFalse(group.keywords.isEmpty)
            XCTAssertEqual(GenreMoodClassifier.group(of: group.keywords[0]), group, "first keyword of \(group) maps back")
        }
    }
}
