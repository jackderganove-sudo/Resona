//
//  StreamClientFallbackTests.swift
//  ResonaTests
//
//  Playback client fallback, error log and redaction (round 12). Invented
//  video ids and answers only, no network, no credentials.
//

import XCTest
import SwiftyTube
@testable import Trop

final class StreamClientFallbackTests: XCTestCase {
    private func result(_ client: YouTubeClient, url: String = "https://rr1.example.invalid/videoplayback?itag=251&sig=x") -> PlaybackResult {
        PlaybackResult(
            streamUrl: url, itag: 251, mimeType: "audio/webm", bitrate: 160_000, audioQuality: "medium",
            videoId: "vid00000001", title: "Platzhalter", author: "Niemand", duration: 180,
            expiresInSeconds: 3600, clientName: client.clientName, musicVideoType: nil,
            hasVideoContent: false, muxedStreamUrl: nil, loudnessDb: nil
        )
    }

    private actor Recorder {
        var entries: [PlaybackLogEntry] = []
        var blocked: [String] = []
        var resolved: [String] = []
        func log(_ entry: PlaybackLogEntry) { entries.append(entry) }
        func block(_ key: String) { blocked.append(key) }
        func resolve(_ name: String) { resolved.append(name) }
    }

    func testChainMatchesAndroidAndDropsTheDeadEmbeddedClient() {
        let names = ResonaStreamChain.playback.map(\.client.clientName)
        XCTAssertEqual(names.first, "VISIONOS")
        XCTAssertFalse(names.contains("TVHTML5_SIMPLY_EMBEDDED_PLAYER"), "YouTube answers: no longer supported")
        for android in ["VISIONOS", "ANDROID_VR", "WEB_REMIX", "WEB", "MWEB"] {
            XCTAssertTrue(names.contains(android), "\(android) is in Android's chain too")
        }
        XCTAssertEqual(ResonaStreamChain.mobileWeb.clientVersion, "2.20260708.05.00", "same version as Resona-Android")
        XCTAssertEqual(ResonaStreamChain.key(for: "VISIONOS"), "VISIONOS 0.1")
    }

    func testNextClientAfterResolveAndProbeFailures() async throws {
        let recorder = Recorder()
        let chain = Array(ResonaStreamChain.playback.prefix(4))
        let found = try await StreamClientFallback.run(
            videoId: "vid00000001",
            chain: chain,
            isBlocked: { _ in false },
            resolve: { entry in
                await recorder.resolve(entry.client.clientName + " " + entry.client.clientVersion)
                if entry.client.clientName == "VISIONOS" { throw InnerTubeError.httpError(statusCode: 400, data: Data()) }
                return self.result(entry.client, url: "https://rr1.example.invalid/\(entry.client.clientVersion)")
            },
            probe: { url in url.hasSuffix("1.65.10") ? 403 : 206 },
            log: { await recorder.log($0) },
            block: { await recorder.block($0) }
        )
        XCTAssertEqual(found.clientName, "ANDROID_VR")
        let resolved = await recorder.resolved
        XCTAssertEqual(resolved, ["VISIONOS 0.1", "ANDROID_VR 1.65.10", "ANDROID_VR 1.61.48"], "stops at the first stream that answers")
        let entries = await recorder.entries
        XCTAssertEqual(entries.map(\.stage), [.resolve, .validate, .success])
        XCTAssertEqual(entries.map(\.httpStatus), [400, 403, nil])
        XCTAssertEqual(entries.first?.client, "VISIONOS 0.1")
        let blocked = await recorder.blocked
        XCTAssertEqual(blocked, ["VISIONOS 0.1", "ANDROID_VR 1.65.10"])
    }

    func testBlockedClientsAreSkippedAndAllFailedThrows() async {
        let recorder = Recorder()
        let chain = Array(ResonaStreamChain.playback.prefix(3))
        do {
            _ = try await StreamClientFallback.run(
                videoId: "vid00000002",
                chain: chain,
                isBlocked: { $0.hasPrefix("VISIONOS") },
                resolve: { entry in
                    await recorder.resolve(entry.client.clientName)
                    throw StreamError.unplayable(reason: "invented")
                },
                probe: { _ in 206 },
                log: { await recorder.log($0) },
                block: { await recorder.block($0) }
            )
            XCTFail("every client failed")
        } catch let failure as StreamClientFallback.Failure {
            XCTAssertEqual(failure.tried, 2, "the blocked client is not asked")
        } catch {
            XCTFail("unexpected \(error)")
        }
        let resolved = await recorder.resolved
        XCTAssertFalse(resolved.contains("VISIONOS"))
    }

    func testBlocklistExpiresAfterTenMinutes() async {
        let list = StreamClientBlocklist()
        let start = Date(timeIntervalSince1970: 1_000_000)
        await list.block(videoId: "v", client: "WEB 1", now: start)
        let soon = await list.isBlocked(videoId: "v", client: "WEB 1", now: start.addingTimeInterval(60))
        let later = await list.isBlocked(videoId: "v", client: "WEB 1", now: start.addingTimeInterval(11 * 60))
        let other = await list.isBlocked(videoId: "w", client: "WEB 1", now: start)
        XCTAssertTrue(soon)
        XCTAssertFalse(later)
        XCTAssertFalse(other, "only for that song")
        await list.block(videoId: "v", client: "WEB 1", now: start)
        await list.reset(videoId: "v")
        let afterRetry = await list.isBlocked(videoId: "v", client: "WEB 1", now: start)
        XCTAssertFalse(afterRetry, "Retry forgets the failures")
    }

    func testRedactionKeepsHostAndItagOnly() {
        let raw = "load failed https://rr3---sn-invented.googlevideo.com/videoplayback?expire=1&itag=140&sig=AAAAABBBBBCCCCCDDDDDEEEEEFFFFFGGGGG&pot=xyz "
            + "cookie=SAPISID123 user someone@example.com token: abcdef visitorData=Cgt0ZXN0dmlzaXRvcg%3D%3D "
            + String(repeating: "Z", count: 40)
        let clean = PlaybackLogRedaction.redact(raw)
        XCTAssertTrue(clean.contains("rr3---sn-invented.googlevideo.com itag=140"))
        XCTAssertFalse(clean.contains("sig="))
        XCTAssertFalse(clean.contains("SAPISID123"))
        XCTAssertFalse(clean.contains("someone@example.com"))
        XCTAssertFalse(clean.contains("abcdef"))
        XCTAssertFalse(clean.contains("Cgt0ZXN0"))
        XCTAssertFalse(clean.contains(String(repeating: "Z", count: 40)))
        XCTAssertTrue(clean.contains("load failed"))
    }

    func testLogKeepsTheLast200AndSurvivesARestart() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("log-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let log = PlaybackErrorLog(file: file)
        for i in 0 ..< 205 {
            await log.record(PlaybackLogEntry(time: Date(timeIntervalSince1970: Double(i)), videoId: "vid\(i)",
                                              client: "WEB 1", stage: .resolve, httpStatus: 403, message: "invented \(i)"))
        }
        let kept = await log.all()
        XCTAssertEqual(kept.count, 200)
        XCTAssertEqual(kept.first?.videoId, "vid5")
        let reopened = PlaybackErrorLog(file: file)
        let again = await reopened.all()
        XCTAssertEqual(again.count, 200)
        let text = await reopened.exportText(appVersion: "0.9.0 (1)", system: "iPad iPadOS 26")
        XCTAssertTrue(text.hasPrefix("Resona 0.9.0 (1)"))
        XCTAssertTrue(text.contains("vid204  WEB 1  resolve  HTTP 403  invented 204"))
    }

    func testMpvHTTPStatus() {
        XCTAssertEqual(PlayerController.httpStatus(inLog: "HTTP error 403 Forbidden"), 403)
        XCTAssertEqual(PlayerController.httpStatus(inLog: "[ffmpeg] https: HTTP error 410 Gone"), 410)
        XCTAssertNil(PlayerController.httpStatus(inLog: "Opening done"))
    }

    func testRefusedStreamHasItsOwnHintAndRetryKnowsTheSong() {
        let info = PlaybackErrorCenter.describe(StreamError.validationFailed("WEB"), videoId: "vid00000003", title: nil)
        let generic = PlaybackErrorCenter.describe(StreamError.noSuitableFormat, videoId: "vid00000003", title: nil)
        XCTAssertNotEqual(info.hint, generic.hint)
        XCTAssertEqual(info.videoId, "vid00000003")
    }
}
