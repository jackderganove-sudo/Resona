//
//  TTMLLyricsParser.swift
//  Resona
//
//  Apple-style TTML (BetterLyrics, YouLyPlus) → word-synced lines.
//  <p begin=… end=…> is a line, timed <span>s inside it are words; text
//  between spans (spaces) belongs to the preceding word so the words join
//  back into the exact line text. Spans with ttm:role="x-bg" are background
//  vocals; translation/romanization spans and the <head> are ignored.
//  Lines without word spans become line-synced.
//

import Foundation

enum TTMLLyricsParser {
    static func parse(_ ttml: String) -> [LyricLine] {
        guard let data = ttml.data(using: .utf8) else { return [] }
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse() || !delegate.lines.isEmpty else { return [] }
        return delegate.lines.sorted { ($0.startTime ?? 0) < ($1.startTime ?? 0) }
    }

    /// "1:02.345", "00:01:02.345", "62.3s", "62345ms", "1.5m" → seconds.
    static func time(_ raw: String?) -> TimeInterval? {
        guard let value = raw?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        let units: [(String, Double)] = [("ms", 0.001), ("h", 3600), ("m", 60), ("s", 1)]
        for (suffix, factor) in units where value.hasSuffix(suffix) {
            if let amount = Double(value.dropLast(suffix.count)) { return amount * factor }
        }
        let parts = value.replacingOccurrences(of: ";", with: ":").split(separator: ":").compactMap { Double($0) }
        switch parts.count {
        case 1: return parts[0]
        case 2: return parts[0] * 60 + parts[1]
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        default: return nil
        }
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var lines: [LyricLine] = []

        private struct SpanFrame {
            var role: String?
            var begin: TimeInterval?
            var end: TimeInterval?
            var text = ""
            var hasChildSpans = false
        }

        private var inBody = false
        private var inLine = false
        private var lineBegin: TimeInterval?
        private var lineText = ""
        private var background = ""
        private var words: [LyricWord] = []
        private var spans: [SpanFrame] = []

        private func local(_ name: String) -> String {
            name.split(separator: ":").last.map(String.init)?.lowercased() ?? name.lowercased()
        }

        private func role(_ attributes: [String: String]) -> String? {
            attributes.first { local($0.key) == "role" }?.value.lowercased()
        }

        private var inBackground: Bool { spans.contains { $0.role == "x-bg" } }
        private var inIgnored: Bool {
            spans.contains { ["x-translation", "x-roman", "x-romanization", "x-transliteration"].contains($0.role ?? "") }
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes: [String: String] = [:]) {
            switch local(elementName) {
            case "body":
                inBody = true
            case "p" where inBody:
                inLine = true
                lineBegin = TTMLLyricsParser.time(attributes["begin"])
                lineText = ""
                background = ""
                words = []
                spans = []
            case "span" where inLine:
                if !spans.isEmpty { spans[spans.count - 1].hasChildSpans = true }
                spans.append(SpanFrame(
                    role: role(attributes),
                    begin: TTMLLyricsParser.time(attributes["begin"]),
                    end: TTMLLyricsParser.time(attributes["end"])
                ))
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard inLine, !inIgnored else { return }
            if inBackground {
                background += string
                return
            }
            if let last = spans.indices.last, spans[last].begin != nil {
                spans[last].text += string
                return
            }
            // Text between word spans (usually a space) joins the previous word.
            let cleaned = string.replacingOccurrences(of: "\n", with: " ")
            lineText += cleaned
            if let last = words.indices.last {
                words[last] = LyricWord(text: words[last].text + cleaned, start: words[last].start, end: words[last].end)
            }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            switch local(elementName) {
            case "span" where inLine:
                guard let frame = spans.popLast() else { return }
                guard !inBackground, !inIgnored, frame.role != "x-bg",
                      let begin = frame.begin, !frame.text.isEmpty, !frame.hasChildSpans else { return }
                words.append(LyricWord(text: frame.text, start: begin, end: frame.end ?? begin))
                lineText += frame.text
            case "p" where inLine:
                inLine = false
                let text = lineText.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { return }
                let start = lineBegin ?? words.first?.start
                let bg = background.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "()")))
                lines.append(LyricLine(
                    text: text,
                    startTime: start,
                    words: words.count > 1 ? trimmedWords() : nil,
                    backgroundText: bg.isEmpty ? nil : bg
                ))
            case "body":
                inBody = false
            default:
                break
            }
        }

        /// Collapses whitespace inside words the same way as the line text,
        /// so the words concatenate to exactly the displayed line.
        private func trimmedWords() -> [LyricWord] {
            var result = words.map { word in
                LyricWord(
                    text: word.text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression),
                    start: word.start,
                    end: word.end
                )
            }
            if let first = result.first {
                result[0] = LyricWord(text: String(first.text.drop { $0 == " " }), start: first.start, end: first.end)
            }
            if let last = result.indices.last {
                let w = result[last]
                result[last] = LyricWord(text: w.text.trimmingCharacters(in: .whitespaces), start: w.start, end: w.end)
            }
            return result
        }
    }
}
