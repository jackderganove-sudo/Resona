//
//  StreamClientFallback.swift
//  Resona
//
//  Playback stream resolution, one YouTube client after the other (like
//  Resona-Android / ArchiveTune): every attempt is written to the error log,
//  a client that failed for a song is skipped for that song for 10 minutes,
//  and a stream the player can't load moves on to the next client.
//
//  Chain (direct URLs first, web clients with signature + PoToken after):
//  VISIONOS, ANDROID_VR 1.65.10 / 1.61.48 / 1.43.32, WEB_REMIX, WEB, MWEB,
//  IOS, TVHTML5, ANDROID. Android's playback chain is WEB_REMIX (main),
//  VISIONOS, ANDROID_VR 1.65.10, WEB_REMIX, WEB, MWEB. The iPad used to stop
//  at TVHTML5_SIMPLY_EMBEDDED_PLAYER (YouTube answers "no longer supported")
//  and had neither WEB nor MWEB.
//

import Foundation
import SwiftyTube

enum ResonaStreamChain {
    /// Mobile web, same version as Resona-Android.
    static let mobileWeb = YouTubeClient(
        clientName: "MWEB",
        clientVersion: "2.20260708.05.00",
        clientId: 2,
        userAgent: "Mozilla/5.0 (Linux; Android 15; Pixel 9 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Mobile Safari/537.36",
        loginSupported: true,
        useSignatureTimestamp: true,
        useWebPoTokens: true
    )

    static let playback: [FallbackClient] = [
        FallbackClient(client: .visionOS, skipValidation: false),
        FallbackClient(client: .androidVr1_65_10, skipValidation: false),
        FallbackClient(client: .androidVr1_61_48, skipValidation: false),
        FallbackClient(client: .androidVr1_43_32, skipValidation: false),
        FallbackClient(client: .webRemix, skipValidation: false),
        FallbackClient(client: .web, skipValidation: false),
        FallbackClient(client: mobileWeb, skipValidation: false),
        // IOS gives HLS only (no Range check possible), TVHTML5 needs a login.
        FallbackClient(client: .iOS, skipValidation: true),
        FallbackClient(client: .tvHtml5, skipValidation: false),
        FallbackClient(client: .mobile, skipValidation: false)
    ]

    static func key(_ client: YouTubeClient) -> String { "\(client.clientName) \(client.clientVersion)" }

    /// A result only names its client; the chain gives the version (first match).
    static func key(for clientName: String) -> String {
        playback.first { $0.client.clientName == clientName }.map { key($0.client) } ?? clientName
    }
}

/// One line of the error log. Never cookies, tokens, account names or full stream URLs.
struct PlaybackLogEntry: Codable, Equatable, Sendable {
    enum Stage: String, Codable, Sendable {
        case resolve, validate, player, success, download
    }

    var time: Date
    var videoId: String
    var client: String
    var stage: Stage
    var httpStatus: Int?
    var message: String

    var line: String {
        let stamp = ISO8601DateFormatter.string(from: time, timeZone: .current, formatOptions: [.withInternetDateTime])
        let status = httpStatus.map { "HTTP \($0)" } ?? "-"
        return "\(stamp)  \(videoId)  \(client)  \(stage.rawValue)  \(status)  \(message)"
    }
}

enum PlaybackLogRedaction {
    /// URLs → host (+ itag), key=value secrets, long tokens and e-mail addresses removed.
    static func redact(_ text: String) -> String {
        var out = text
        out = replace(#"https?://[^\s"'<>]+"#, in: out) { match in
            guard let url = URL(string: match), let host = url.host else { return "<url>" }
            let itag = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "itag" }?.value
            return itag.map { "\(host) itag=\($0)" } ?? host
        }
        out = replace(#"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, in: out) { _ in "<email>" }
        out = replace(#"(?i)\b(cookie|sapisid|authorization|token|potoken|key|sig|signature|visitor_?data|session)\b\s*[=:]\s*[^\s,;&]+"#, in: out) { match in
            let name = match.prefix { $0 != "=" && $0 != ":" }.trimmingCharacters(in: .whitespaces)
            return "\(name)=<hidden>"
        }
        out = replace(#"[A-Za-z0-9_\-+/=]{32,}"#, in: out) { _ in "<hidden>" }
        return String(out.prefix(300))
    }

    private static func replace(_ pattern: String, in text: String, with transform: (String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            result += transform(ns.substring(with: match.range))
            last = match.range.location + match.range.length
        }
        result += ns.substring(from: last)
        return result
    }
}

/// The last 200 attempts and failures, kept on disk, shareable from Settings → About.
actor PlaybackErrorLog {
    static let shared = PlaybackErrorLog(file: PlaybackErrorLog.defaultFile)
    static let limit = 200

    private let file: URL?
    private var entries: [PlaybackLogEntry]

    init(file: URL?) {
        self.file = file
        if let file, let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([PlaybackLogEntry].self, from: data) {
            entries = saved
        } else {
            entries = []
        }
    }

    private static var defaultFile: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("playback-errors.json")
    }

    func record(_ entry: PlaybackLogEntry) {
        var clean = entry
        clean.message = PlaybackLogRedaction.redact(entry.message)
        entries.append(clean)
        if entries.count > Self.limit { entries.removeFirst(entries.count - Self.limit) }
        save()
    }

    func all() -> [PlaybackLogEntry] { entries }

    func clear() {
        entries = []
        save()
    }

    private func save() {
        guard let file else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(entries).write(to: file, options: .atomic)
    }

    /// Plain text for the share sheet: app version, device class, then one line per entry.
    func exportText(appVersion: String, system: String) -> String {
        var lines = [
            "Resona \(appVersion) · \(system)",
            "Playback error log (\(entries.count) entries): time  video  client  stage  status  message",
            ""
        ]
        lines += entries.map(\.line)
        return lines.joined(separator: "\n") + "\n"
    }
}

/// Clients that failed for a song are skipped for that song for a while.
actor StreamClientBlocklist {
    static let shared = StreamClientBlocklist()
    static let duration: TimeInterval = 10 * 60

    private var until: [String: [String: Date]] = [:]

    func block(videoId: String, client: String, now: Date = Date()) {
        until[videoId, default: [:]][client] = now.addingTimeInterval(Self.duration)
    }

    func isBlocked(videoId: String, client: String, now: Date = Date()) -> Bool {
        guard let date = until[videoId]?[client] else { return false }
        return date > now
    }

    func reset(videoId: String) {
        until.removeValue(forKey: videoId)
    }
}

enum StreamAttemptError {
    /// HTTP status behind a SwiftyTube error, when there is one.
    static func httpStatus(_ error: Error) -> Int? {
        if let error = error as? InnerTubeError, case .httpError(let status, _) = error { return status }
        if let error = error as? HttpError, case .status(let status, _) = error { return status }
        return nil
    }
}

/// The loop itself, with the network parts passed in (tests use fakes).
enum StreamClientFallback {
    struct Failure: Error, LocalizedError {
        let lastError: Error?
        let tried: Int
        var errorDescription: String? {
            lastError.map { String(describing: $0) } ?? "All clients failed to resolve a valid stream URL"
        }
    }

    static func run(
        videoId: String,
        chain: [FallbackClient],
        isBlocked: (String) async -> Bool,
        resolve: (FallbackClient) async throws -> PlaybackResult,
        probe: (String) async -> Int?,
        log: (PlaybackLogEntry) async -> Void,
        block: (String) async -> Void,
        now: () -> Date = Date.init
    ) async throws -> PlaybackResult {
        var lastError: Error?
        var tried = 0
        for entry in chain {
            try Task.checkCancellation()
            let key = ResonaStreamChain.key(entry.client)
            if await isBlocked(key) { continue }
            tried += 1
            do {
                let result = try await resolve(entry)
                if !entry.skipValidation {
                    let status = await probe(result.streamUrl)
                    guard let status, (200 ... 299).contains(status) else {
                        await log(PlaybackLogEntry(time: now(), videoId: videoId, client: key, stage: .validate,
                                                   httpStatus: status, message: status == nil ? "no answer to the range request" : "range request rejected"))
                        await block(key)
                        lastError = StreamError.validationFailed(entry.client.clientName)
                        continue
                    }
                }
                await log(PlaybackLogEntry(time: now(), videoId: videoId, client: key, stage: .success,
                                           httpStatus: nil, message: "itag \(result.itag) \(result.mimeType)"))
                return result
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                await log(PlaybackLogEntry(time: now(), videoId: videoId, client: key, stage: .resolve,
                                           httpStatus: StreamAttemptError.httpStatus(error), message: String(describing: error)))
                await block(key)
                lastError = error
            }
        }
        throw Failure(lastError: lastError, tried: tried)
    }

    /// Range request on the first KB, like SwiftyTube's check, but keeping the status code.
    static func probeStatus(_ urlString: String) async -> Int? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }
        return http.statusCode
    }
}
