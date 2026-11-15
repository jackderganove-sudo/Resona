//
//  ChunkedDownloadTests.swift
//  ResonaTests
//
//  Block download (round 12) against a fake server: ranges like YouTube, an
//  expired link (403) mid-download, 416 past the end, a format change on
//  refresh. Same cases as Resona-Android's ChunkedDownloadDataSourceTest.
//

import XCTest
@testable import Trop

final class FakeRangeServer: URLProtocol {
    nonisolated(unsafe) static var content = Data()
    nonisolated(unsafe) static var refuse: Set<Int> = []
    nonisolated(unsafe) static var requests: [(url: URL, range: String)] = []
    nonisolated(unsafe) static var ignoreRange = false

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "fake.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let n = Self.requests.count
        let range = request.value(forHTTPHeaderField: "Range") ?? ""
        Self.requests.append((request.url!, range))
        func respond(_ status: Int, _ headers: [String: String], _ body: Data) {
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
        if Self.refuse.contains(n) { return respond(403, [:], Data()) }
        if Self.ignoreRange { return respond(200, [:], Self.content) }
        let parts = range.replacingOccurrences(of: "bytes=", with: "").split(separator: "-").compactMap { Int($0) }
        let start = parts[0]
        guard start < Self.content.count else { return respond(416, [:], Data()) }
        let end = min(parts[1], Self.content.count - 1)
        respond(206, ["Content-Range": "bytes \(start)-\(end)/\(Self.content.count)"], Self.content.subdata(in: start..<(end + 1)))
    }

    override func stopLoading() {}
}

final class ChunkedDownloadTests: XCTestCase {
    private var session: URLSession!
    private let target = FileManager.default.temporaryDirectory.appendingPathComponent("chunked-test.bin")

    override func setUp() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FakeRangeServer.self]
        session = URLSession(configuration: config)
        FakeRangeServer.content = Data((0..<2_500_000).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })
        FakeRangeServer.refuse = []
        FakeRangeServer.requests = []
        FakeRangeServer.ignoreRange = false
    }

    private func run(url: String = "https://fake.invalid/videoplayback?itag=140", refreshTo: String = "https://fake.invalid/videoplayback?itag=140&fresh=1",
                     maxAttempts: Int = 6, onRetry: @escaping @Sendable (Int64, Int?) -> Void = { _, _ in }) async throws -> ChunkedDownload.Stats {
        try await ChunkedDownload.run(
            url: URL(string: url)!, to: target, session: session, chunkSize: 1_000_000, maxAttempts: maxAttempts,
            backoff: { _ in }, refresh: { URL(string: refreshTo)! }, onRetry: onRetry
        )
    }

    func testDownloadsInBlocks() async throws {
        let stats = try await run()
        XCTAssertEqual(try Data(contentsOf: target), FakeRangeServer.content)
        XCTAssertEqual(FakeRangeServer.requests.map(\.range), ["bytes=0-999999", "bytes=1000000-1999999", "bytes=2000000-2499999"])
        XCTAssertEqual(stats.requests, 3)
        XCTAssertEqual(stats.retries, 0)
    }

    func testExpiredLinkContinuesAtTheSamePositionWithAFreshLink() async throws {
        FakeRangeServer.refuse = [1]
        let positions = Positions()
        let stats = try await run(onRetry: { pos, status in positions.add(pos, status) })
        XCTAssertEqual(try Data(contentsOf: target), FakeRangeServer.content)
        XCTAssertEqual(positions.items.first?.0, 1_000_000)
        XCTAssertEqual(positions.items.first?.1, 403)
        XCTAssertEqual(FakeRangeServer.requests[2].range, "bytes=1000000-1999999")
        XCTAssertTrue(FakeRangeServer.requests[2].url.absoluteString.contains("fresh=1"))
        XCTAssertEqual(stats.retries, 1)
    }

    func testOtherFormatOnRefreshStartsTheFileAgain() async throws {
        FakeRangeServer.refuse = [1]
        _ = try await run(refreshTo: "https://fake.invalid/videoplayback?itag=251")
        XCTAssertEqual(try Data(contentsOf: target), FakeRangeServer.content)
        XCTAssertEqual(FakeRangeServer.requests[2].range, "bytes=0-999999")
    }

    func testServerIgnoringTheRange() async throws {
        FakeRangeServer.ignoreRange = true
        _ = try await run()
        XCTAssertEqual(try Data(contentsOf: target), FakeRangeServer.content)
        XCTAssertEqual(FakeRangeServer.requests.count, 1)
    }

    func testGivesUpAfterMaxAttempts() async {
        FakeRangeServer.refuse = Set(0..<20)
        do {
            _ = try await run(maxAttempts: 3)
            XCTFail("should fail")
        } catch let failure as ChunkedDownload.Failure {
            XCTAssertEqual(failure, .http(403, position: 0))
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testTotalLengthFromContentRange() {
        let response = HTTPURLResponse(url: URL(string: "https://x")!, statusCode: 206, httpVersion: nil,
                                       headerFields: ["Content-Range": "bytes 0-8388607/58123456"])!
        XCTAssertEqual(ChunkedDownload.totalLength(response), 58_123_456)
        XCTAssertEqual(ChunkedDownload.itag(of: URL(string: "https://x/v?a=1&itag=140")!), "140")
    }
}

private final class Positions: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var items: [(Int64, Int?)] = []
    func add(_ p: Int64, _ s: Int?) { lock.lock(); items.append((p, s)); lock.unlock() }
}
