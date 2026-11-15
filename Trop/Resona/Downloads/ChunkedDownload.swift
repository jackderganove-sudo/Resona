//
//  ChunkedDownload.swift
//  Resona
//
//  Downloads in HTTP range blocks (round 12, same as Resona-Android's
//  ChunkedDownloadDataSource). One request per song – ffmpeg's `-i <url>` –
//  is throttled by YouTube to about real time and long ones (a 60-minute DJ
//  mix) break off and start over. Here every request asks for at most 8 MB;
//  the next block starts at the next byte. A failed block (HTTP 403/410 after
//  the link expired, a dropped connection, a short body) is requested again at
//  the same position with a freshly resolved link. Memory: one block at a time.
//

import Foundation

enum ChunkedDownload {
    static let chunkSize: Int64 = 8 * 1024 * 1024

    struct Stats: Equatable, Sendable {
        var bytes: Int64
        var seconds: Double
        var requests: Int
        var retries: Int
    }

    enum Failure: Error, Equatable {
        case http(Int, position: Int64)
        case gaveUp(position: Int64)
    }

    /// The resolved stream changed format (other itag/length): start the file again.
    struct FormatChanged: Error {}

    /// - Parameters:
    ///   - refresh: a fresh stream URL after a refused or broken block.
    ///   - onRetry: position and HTTP status of every failed block (for the error log).
    ///   - progress: bytes so far and the total once known.
    static func run(
        url initialURL: URL,
        to destination: URL,
        session: URLSession = .shared,
        headers: [String: String] = ["User-Agent": "Mozilla/5.0"],
        chunkSize: Int64 = ChunkedDownload.chunkSize,
        maxAttempts: Int = 6,
        backoff: @escaping @Sendable (Int) async -> Void = { attempt in
            try? await Task.sleep(nanoseconds: UInt64(500_000_000) << UInt64(min(attempt, 4)))
        },
        refresh: @escaping @Sendable () async throws -> URL,
        onRetry: @escaping @Sendable (Int64, Int?) -> Void = { _, _ in },
        progress: @escaping @Sendable (Int64, Int64?) -> Void = { _, _ in }
    ) async throws -> Stats {
        let fm = FileManager.default
        try? fm.removeItem(at: destination)
        fm.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        let started = Date()
        var url = initialURL
        var position: Int64 = 0
        var total: Int64?
        var requests = 0
        var retries = 0
        var attempt = 0

        func fail(_ error: Error, status: Int?) async throws {
            onRetry(position, status)
            attempt += 1
            retries += 1
            guard attempt < maxAttempts else {
                throw status.map { Failure.http($0, position: position) } ?? Failure.gaveUp(position: position)
            }
            await backoff(attempt - 1)
            let fresh = try await refresh()
            if itag(of: fresh) != itag(of: url) {
                // Another format: its bytes do not continue this file.
                try handle.truncate(atOffset: 0)
                position = 0
                total = nil
            }
            url = fresh
        }

        while total.map({ position < $0 }) ?? true {
            try Task.checkCancellation()
            let end = min(position + chunkSize, total ?? .max) - 1
            var request = URLRequest(url: url, timeoutInterval: 30)
            for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
            request.setValue("bytes=\(position)-\(end)", forHTTPHeaderField: "Range")
            requests += 1
            let data: Data
            let response: HTTPURLResponse
            do {
                let (body, raw) = try await session.data(for: request)
                guard let http = raw as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                data = body
                response = http
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try await fail(error, status: nil)
                continue
            }
            switch response.statusCode {
            case 206:
                if total == nil { total = totalLength(response) }
                let expected = end - position + 1
                // Short block with a known total: broken, same position again.
                if let total, Int64(data.count) < min(expected, total - position) {
                    try handle.seek(toOffset: UInt64(position))
                    try handle.write(contentsOf: data)
                    position += Int64(data.count)
                    try await fail(URLError(.networkConnectionLost), status: nil)
                    continue
                }
                try handle.seek(toOffset: UInt64(position))
                try handle.write(contentsOf: data)
                position += Int64(data.count)
                attempt = 0
                if total == nil, Int64(data.count) < expected { total = position }
            case 200 where position == 0:
                // The server ignored the range: the whole file in one body.
                try handle.write(contentsOf: data)
                position = Int64(data.count)
                total = position
            case 416:
                total = position
            default:
                try await fail(URLError(.badServerResponse), status: response.statusCode)
                continue
            }
            progress(position, total)
        }
        try handle.truncate(atOffset: UInt64(position))
        return Stats(bytes: position, seconds: Date().timeIntervalSince(started), requests: requests, retries: retries)
    }

    /// "bytes 0-8388607/58123456" → 58123456.
    static func totalLength(_ response: HTTPURLResponse) -> Int64? {
        guard let range = response.value(forHTTPHeaderField: "Content-Range"),
              let slash = range.lastIndex(of: "/") else { return nil }
        return Int64(range[range.index(after: slash)...])
    }

    static func itag(of url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "itag" }?.value
    }
}
