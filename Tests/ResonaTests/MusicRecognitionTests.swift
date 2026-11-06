//
//  MusicRecognitionTests.swift
//  ResonaTests
//
//  Round 11: the iPad's signature must match Android's byte for byte. Both are
//  tested against one reference from a third implementation (same synthetic
//  PCM, no real audio). Responses are invented.
//

import XCTest
@testable import Trop

final class MusicRecognitionTests: XCTestCase {
    /// Integer-only test signal: noise plus two square waves, 8.4 s at 16 kHz.
    private func testPCM() -> [Int16] {
        var state: UInt64 = 12345
        return (0..<134_400).map { index in
            state = (state &* 1_103_515_245 &+ 12345) & 0x7FFF_FFFF
            let noise = (Int((state >> 16) & 0x7FFF) - 16384) >> 2
            let first = (index / 18) % 2 == 0 ? 6000 : -6000
            let second = (index / 5) % 2 == 0 ? 3000 : -3000
            return Int16(max(-32768, min(32767, noise + first + second)))
        }
    }

    func testSignatureMatchesTheReference() throws {
        let pcm = testPCM()
        XCTAssertEqual(Array(pcm.prefix(3)), [10271, 7401, 10433])
        let signature = try XCTUnwrap(ShazamSignatureGenerator.signature(pcm: pcm))
        XCTAssertEqual(signature.bytes.count, 1912)
        XCTAssertEqual(signature.sampleDurationMs, 3104)
        let crc = signature.bytes.subdata(in: 4..<8).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        XCTAssertEqual(crc, 0x6A53_20A3)
        let start = signature.bytes.startIndex + 56
        let body = signature.bytes.subdata(in: start..<(start + 16)).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(body, "4000036037000000234383390e559f5a")
    }

    func testURIAndChecksum() throws {
        let signature = try XCTUnwrap(ShazamSignatureGenerator.signature(pcm: testPCM()))
        XCTAssertTrue(signature.uri.hasPrefix("data:audio/vnd.shazam.sig;base64,"))
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xCBF4_3926)
    }

    func testSilenceHasNoSignature() {
        XCTAssertNil(ShazamSignatureGenerator.signature(pcm: [Int16](repeating: 0, count: 134_400)))
        XCTAssertNil(ShazamSignatureGenerator.signature(pcm: []))
    }

    func testRequest() throws {
        let signature = ShazamSignature(bytes: Data([1, 2, 3]), sampleDurationMs: 3104)
        let request = ShazamClient.request(signature: signature, now: Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.host, "amp.shazam.com")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["timestamp"] as? Int, 1000)
        let sent = try XCTUnwrap(body["signature"] as? [String: Any])
        XCTAssertEqual(sent["samplems"] as? Int, 3104)
        XCTAssertEqual(sent["uri"] as? String, signature.uri)
    }

    func testParsesAMatch() throws {
        let json = #"""
        {"matches":[{"id":"1"}],"track":{"key":"42","title":"Testtitel","subtitle":"Testband",
         "images":{"coverart":"https://example.com/a.jpg","coverarthq":"https://example.com/b.jpg"},
         "sections":[{"type":"SONG","metadata":[{"title":"Album","text":"Testalbum"}]}]}}
        """#
        let song = try ShazamClient.parse(Data(json.utf8))
        XCTAssertEqual(song.id, "42")
        XCTAssertEqual(song.title, "Testtitel")
        XCTAssertEqual(song.artist, "Testband")
        XCTAssertEqual(song.album, "Testalbum")
        XCTAssertEqual(song.coverURL, "https://example.com/b.jpg")
    }

    func testNoTrackIsNoMatch() {
        XCTAssertThrowsError(try ShazamClient.parse(Data(#"{"matches":[]}"#.utf8))) {
            XCTAssertEqual($0 as? ShazamClient.Failure, .noMatch)
        }
        XCTAssertThrowsError(try ShazamClient.parse(Data("kein json".utf8)))
    }
}
