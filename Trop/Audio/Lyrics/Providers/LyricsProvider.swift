//
//  LyricsProvider.swift
//  Trop
//
//  Created by 686udjie on 16/07/2026.
//

import Foundation

/// A normalized query used to look up lyrics across providers
struct LyricsQuery: Sendable {
    let title: String
    let artist: String
    let album: String?
    let duration: TimeInterval
    /// YouTube video id (YouTube Music's own lyrics tab).
    var videoId: String? = nil
    /// Slowed / sped-up / nightcore upload: lyrics come from the original
    /// and their timestamps are scaled to this version's length.
    var isSpeedVariant: Bool = false

    var durationSeconds: Int { Int(duration) }
}

/// Common interface implemented by every lyrics source.
protocol LyricsProvider: Sendable {
    var id: String { get }
    var name: String { get }
    func fetch(query: LyricsQuery) async throws -> [LyricLine]
}

enum LyricsParsing {
    private static let tagRegex = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#)
    private static let leadingTagsRegex = try! NSRegularExpression(pattern: #"^\s*(?:\[\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?\]\s*)+"#)
    private static let wordTagRegex = try! NSRegularExpression(pattern: #"<(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?>"#)
    private static let offsetRegex = try! NSRegularExpression(pattern: #"^\s*\[offset:\s*([+-]?\d+)\s*\]"#, options: .caseInsensitive)

    /// mm, ss and an optional fraction ("5" = 0.5 s, "50" = 0.50 s,
    /// "500" = 0.500 s) → seconds.
    private static func seconds(_ ns: NSString, _ m: NSTextCheckingResult) -> TimeInterval {
        let mins = Double(ns.substring(with: m.range(at: 1))) ?? 0
        let secs = Double(ns.substring(with: m.range(at: 2))) ?? 0
        var frac = 0.0
        if m.range(at: 3).location != NSNotFound {
            let digits = ns.substring(with: m.range(at: 3))
            frac = (Double(digits) ?? 0) / pow(10, Double(digits.count))
        }
        return mins * 60 + secs + frac
    }

    /// Parses the leading `[mm:ss.xx]` tags of a line. Returns every tag's
    /// time (repeated choruses share one text line) and the remaining text.
    static func parseLrcTimestamps(_ line: String) -> (times: [TimeInterval], text: String)? {
        let ns = line as NSString
        guard let lead = leadingTagsRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let tags = tagRegex.matches(in: line, range: lead.range)
        guard !tags.isEmpty else { return nil }
        let times = tags.map { seconds(ns, $0) }
        let text = ns.substring(from: lead.range.location + lead.range.length)
        return (times, text)
    }

    /// Single-timestamp variant kept for existing callers.
    static func parseLrcTimestamp(_ line: String) -> (time: TimeInterval, text: String)? {
        guard let parsed = parseLrcTimestamps(line), let last = parsed.times.last else { return nil }
        return (last, parsed.text.trimmingCharacters(in: .whitespaces))
    }

    /// Enhanced LRC: `<mm:ss.xx>word <mm:ss.xx>word` → clean text + words.
    static func parseWordTags(_ text: String, lineStart: TimeInterval) -> (text: String, words: [LyricWord]?) {
        let ns = text as NSString
        let matches = wordTagRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return (text.trimmingCharacters(in: .whitespaces), nil) }

        var words: [LyricWord] = []
        var clean = ""
        // Text before the first tag belongs to the line start.
        let head = ns.substring(to: matches[0].range.location)
        if !head.trimmingCharacters(in: .whitespaces).isEmpty {
            words.append(LyricWord(text: head, start: lineStart, end: lineStart))
            clean += head
        }
        for (i, m) in matches.enumerated() {
            let start = seconds(ns, m)
            let from = m.range.location + m.range.length
            let to = i + 1 < matches.count ? matches[i + 1].range.location : ns.length
            let chunk = ns.substring(with: NSRange(location: from, length: max(0, to - from)))
            if !words.isEmpty, words[words.count - 1].end <= words[words.count - 1].start {
                words[words.count - 1].end = start
            }
            // A trailing tag with no text marks the end of the last word.
            if chunk.trimmingCharacters(in: .whitespaces).isEmpty {
                if let last = words.indices.last { words[last].end = start }
                clean += chunk
                continue
            }
            words.append(LyricWord(text: chunk, start: start, end: start))
            clean += chunk
        }
        if let last = words.indices.last, words[last].end <= words[last].start {
            words[last].end = words[last].start + 0.6
        }
        let trimmed = clean.trimmingCharacters(in: .whitespaces)
        return (trimmed, words.isEmpty ? nil : words)
    }

    /// Split a raw LRC string into lines, sorted by time. Blank timestamped
    /// lines are kept — they mark instrumental spans. Supports repeated
    /// timestamps, the `[offset:±ms]` header and enhanced word tags.
    static func parseLrc(_ raw: String) -> [LyricLine] {
        var offset: TimeInterval = 0
        var timed: [(time: TimeInterval, line: LyricLine)] = []
        for line in raw.split(whereSeparator: \.isNewline).map(String.init) {
            let ns = line as NSString
            if let m = offsetRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                // LRC spec: a positive offset makes lyrics appear sooner.
                offset = (Double(ns.substring(with: m.range(at: 1))) ?? 0) / 1000
                continue
            }
            guard let (times, rest) = parseLrcTimestamps(line) else { continue }
            for t in times {
                let (text, words) = parseWordTags(rest, lineStart: t)
                timed.append((t, LyricLine(text: text, startTime: t, words: words)))
            }
        }
        guard !timed.isEmpty else { return [] }
        return timed
            .enumerated()
            .sorted { a, b in
                a.element.time != b.element.time ? a.element.time < b.element.time : a.offset < b.offset
            }
            .map { pair -> LyricLine in
                let l = pair.element.line
                guard offset != 0, let start = l.startTime else { return l }
                let shifted = l.words?.map { LyricWord(text: $0.text, start: max(0, $0.start - offset), end: max(0, $0.end - offset)) }
                return LyricLine(text: l.text, startTime: max(0, start - offset), words: shifted)
            }
    }

    /// Parses stored lyrics text — LRC if timestamped, otherwise plain lines.
    static func parseStoredText(_ raw: String) -> [LyricLine] {
        let lrc = parseLrc(raw)
        if !lrc.isEmpty { return lrc }
        return raw
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { LyricLine(text: $0, startTime: nil) }
    }

    /// Serializes lines back to LRC/plain text for storage and editing.
    static func serializeLines(_ lines: [LyricLine]) -> String {
        func stamp(_ t: TimeInterval) -> String {
            let minutes = Int(t) / 60
            let seconds = Int(t) % 60
            let centis = Int(((t - floor(t)) * 100).rounded(.down))
            return String(format: "%02d:%02d.%02d", minutes, seconds, centis)
        }
        let synced = lines.contains { $0.startTime != nil }
        return lines.map { line in
            guard synced, let t = line.startTime else { return line.text }
            // Keep word timings (enhanced LRC) so edits/refetches survive.
            if let words = line.words, !words.isEmpty {
                let body = words.map { "<\(stamp($0.start))>\($0.text)" }.joined()
                    + "<\(stamp(words[words.count - 1].end))>"
                return "[\(stamp(t))]" + body
            }
            return "[\(stamp(t))]" + line.text
        }
        .joined(separator: "\n")
    }

    /// Plain text without timestamps — what "Copy" puts on the clipboard.
    static func plainText(_ lines: [LyricLine]) -> String {
        lines.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
