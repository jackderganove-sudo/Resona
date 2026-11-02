//
//  FeatherLinksTests.swift
//  ResonaTests
//
//  Feather URL schemes as implemented in Feather's FeatherApp._handleURL:
//  feather://install/<https url> and feather://source/<https url>.
//

import XCTest
@testable import Trop

final class FeatherLinksTests: XCTestCase {
    func testInstallLinkAppendsTheRawHTTPSURL() throws {
        let ipa = try XCTUnwrap(URL(string: "https://github.com/jackderganove-sudo/Resona/releases/download/v0.8.14/Resona.ipa"))
        let link = try XCTUnwrap(FeatherLinks.install(ipa))
        XCTAssertEqual(link.scheme, "feather")
        XCTAssertEqual(link.absoluteString, "feather://install/https://github.com/jackderganove-sudo/Resona/releases/download/v0.8.14/Resona.ipa")
        // Feather takes everything after "/install/" and requires https://.
        let range = try XCTUnwrap(link.absoluteString.range(of: "/install/"))
        XCTAssertTrue(link.absoluteString[range.upperBound...].hasPrefix("https://"))
    }

    func testSourceLink() throws {
        let source = try XCTUnwrap(URL(string: UpdateChecker.sourceURL))
        XCTAssertEqual(FeatherLinks.addSource(source)?.absoluteString, "feather://source/" + UpdateChecker.sourceURL)
    }

    func testOnlyHTTPS() throws {
        XCTAssertNil(FeatherLinks.install(try XCTUnwrap(URL(string: "http://example.com/a.ipa"))))
    }
}
