//
//  WhatsNewTests.swift
//  ResonaTests
//
//  Round 10 app flow: release notes → New / Improved / Fixed, the
//  releases shown after an update, first-launch detection.
//

import XCTest
@testable import Trop

final class WhatsNewTests: XCTestCase {
    func testCommitSubjectsAreSortedIntoCategories() {
        let notes = """
        - Fix optional chaining in the Deezer lyrics parser
        - Docs: round 9 progress
        - Queue: recommendation chips replace the upcoming songs
        - Lyrics: improve the ranking of remix versions
        - Tests: placeholder fixtures
        - Merge branch 'wip'
        - Player: fixed the drop menu toggle
        """
        let sections = WhatsNewParser.sections(from: notes)
        XCTAssertEqual(sections.map(\.category), [.new, .improved, .fixed])
        XCTAssertEqual(sections[0].entries, [WhatsNewEntry(area: "Queue", text: "Recommendation chips replace the upcoming songs")])
        XCTAssertEqual(sections[1].entries.first?.area, "Lyrics")
        XCTAssertEqual(sections[2].entries.count, 2)
        XCTAssertNil(sections[2].entries[0].area)
    }

    func testHeadingsSetCategoryAndSkipCredits() {
        let notes = """
        ## Bug fixes
        * Seek bar no longer jumps by @someone in https://github.com/example/repo/pull/1
        ## Contributors
        - @someone
        ## Features
        - Sleep timer fades out
        """
        let sections = WhatsNewParser.sections(from: notes)
        XCTAssertEqual(sections.map(\.category), [.new, .fixed])
        XCTAssertEqual(sections[1].entries.first?.text, "Seek bar no longer jumps")
        XCTAssertEqual(sections[0].entries.first?.text, "Sleep timer fades out")
    }

    func testReleasesBetweenLastSeenAndInstalled() {
        func release(_ tag: String, _ body: String = "- Player: a new switch", prerelease: Bool = false) -> [String: Any] {
            ["tag_name": tag, "body": body, "prerelease": prerelease, "html_url": "https://github.com/example/releases/\(tag)"]
        }
        let list = [release("v0.8.13"), release("v0.8.12"), release("v0.8.11"), release("v0.8.10"),
                    release("v0.8.12-beta", prerelease: true), release("v0.8.9", "- Docs: only docs")]
        let shown = WhatsNewCenter.select(list, after: "0.8.10", upTo: "0.8.12")
        XCTAssertEqual(shown.map(\.version), ["0.8.12", "0.8.11"])
        XCTAssertEqual(shown.first?.pageURL?.absoluteString, "https://github.com/example/releases/v0.8.12")
        XCTAssertTrue(WhatsNewCenter.select(list, after: "0.8.8", upTo: "0.8.9").isEmpty)
    }

    func testPreviousVersion() {
        XCTAssertEqual(WhatsNewCenter.previousVersion(of: "0.8.11"), "0.8.10")
        XCTAssertEqual(WhatsNewCenter.previousVersion(of: "1.0.0"), "1.0.0")
    }

    func testExistingInstallDetection() throws {
        let suite = "resona.tests.onboarding.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertFalse(OnboardingState.isExistingInstall(defaults))
        defaults.set(Date().timeIntervalSince1970, forKey: "resona.update.lastCheck")
        XCTAssertTrue(OnboardingState.isExistingInstall(defaults))
    }
}
