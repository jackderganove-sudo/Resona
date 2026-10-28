//
//  LyricsAligner.swift
//  Resona
//
//  Forced alignment of recognized words (with timestamps) onto the known
//  lyrics: both sides are normalized (case, diacritics, punctuation,
//  apostrophes), then a global alignment (Needleman–Wunsch / DTW-style)
//  with fuzzy word similarity maps lyric words to recognized words. Lyric
//  words without a match are interpolated between their matched
//  neighbours; line starts come from the first word.
//

import Foundation

struct RecognizedWord: Sendable {
    let text: String
    let start: Double
    let end: Double
}

enum LyricsAligner {
    struct Result {
        let lines: [LyricLine]
        /// Share of lyric words that were matched to a recognized word.
        let matchedRatio: Double
    }

    /// Sung / informal spellings → the written form (single tokens only).
    private static let canonical: [String: String] = [
        "cause": "because", "cuz": "because", "coz": "because", "bc": "because",
        "til": "until", "till": "until", "ya": "you", "yah": "you", "u": "you",
        "em": "them", "tho": "though", "thru": "through", "ur": "your", "yall": "youall",
        "nothin": "nothing", "somethin": "something", "everythin": "everything",
        "lovin": "loving", "goin": "going", "feelin": "feeling", "tryin": "trying",
        "ok": "okay", "imma": "ima", "oh": "o", "ooh": "o", "yeah": "yea", "yea": "yea"
    ]

    private static let numberWords = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
                                      "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
                                      "seventeen", "eighteen", "nineteen", "twenty"]

    static func normalize(_ word: String) -> String {
        let plain = word.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        if let number = Int(plain), number >= 0, number < numberWords.count { return numberWords[number] }
        return canonical[plain] ?? plain
    }

    /// Rough sound key: similar consonants merged, vowels after the first
    /// letter dropped, doubles collapsed ("nite" ~ "night", "luv" ~ "love").
    static func phoneticKey(_ word: String) -> String {
        var s = word
        for (from, to) in [("ght", "t"), ("ph", "f"), ("ck", "k"), ("qu", "kw"), ("wh", "w"), ("th", "t"),
                           ("c", "k"), ("q", "k"), ("z", "s"), ("v", "f"), ("y", "i")] {
            s = s.replacingOccurrences(of: from, with: to)
        }
        guard let first = s.first else { return "" }
        var key = String(first)
        for char in s.dropFirst() where !"aeiou".contains(char) && key.last != char {
            key.append(char)
        }
        return key
    }

    /// 0…1: spelling similarity, or (for words of 4+ letters) sound
    /// similarity capped at 0.9 — sung words are often heard differently.
    static func wordSimilarity(_ a: String, _ b: String) -> Double {
        let spelled = similarity(a, b)
        guard spelled < 0.9, a.count >= 4, b.count >= 4 else { return spelled }
        return max(spelled, min(0.9, similarity(phoneticKey(a), phoneticKey(b))))
    }

    /// Minimum word similarity for a match.
    static let matchThreshold = 0.5

    /// 0…1 similarity (1 - normalized Levenshtein distance).
    static func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return a.isEmpty ? 0 : 1 }
        let x = Array(a), y = Array(b)
        guard !x.isEmpty, !y.isEmpty else { return 0 }
        var previous = Array(0...y.count)
        var current = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            current[0] = i
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return 1 - Double(previous[y.count]) / Double(max(x.count, y.count))
    }

    static func align(lines: [String], recognized: [RecognizedWord], duration: Double) -> Result {
        // Lyric words with their line index.
        var lyric: [(line: Int, text: String, norm: String)] = []
        for (index, line) in lines.enumerated() {
            for word in line.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
                lyric.append((index, String(word), normalize(String(word))))
            }
        }
        let heard = recognized.filter { !normalize($0.text).isEmpty }
        let heardNorm = heard.map { normalize($0.text) }
        let n = lyric.count, m = heard.count
        guard n > 0 else { return Result(lines: [], matchedRatio: 0) }

        let match = matchIndices(lyric.map(\.norm), heardNorm)

        // Times: matched words from recognition, the rest interpolated.
        var starts = [Double?](repeating: nil, count: n)
        var ends = [Double?](repeating: nil, count: n)
        for k in 0..<n {
            if let hit = match[k] {
                starts[k] = heard[hit].start
                ends[k] = heard[hit].end
            }
        }
        let matched = match.compactMap { $0 }.count
        // Outliers (a word matched to a recognition far earlier/later than
        // its neighbours) would make lines jump back and forth: only the
        // longest non-decreasing run of matched times is kept as anchors,
        // the rest is interpolated like unmatched words.
        let anchors = Set(longestNonDecreasing(starts))
        for k in 0..<n where starts[k] != nil && !anchors.contains(k) {
            starts[k] = nil
            ends[k] = nil
        }
        var k = 0
        while k < n {
            guard starts[k] == nil else { k += 1; continue }
            var e = k
            while e < n, starts[e] == nil { e += 1 }
            let from = k > 0 ? (ends[k - 1] ?? starts[k - 1] ?? 0) : 0
            let to = e < n ? (starts[e] ?? duration) : max(from + 0.5, min(duration, from + Double(e - k) * 0.5))
            let weights = (k..<e).map { Double(max(1, lyric[$0].norm.count)) }
            let total = weights.reduce(0, +)
            var t = from
            for (offset, idx) in (k..<e).enumerated() {
                let span = max(0.05, (to - from) * weights[offset] / max(1, total))
                starts[idx] = t
                ends[idx] = t + span
                t += span
            }
            k = e
        }
        // Strictly increasing with a minimum word length; never past the end.
        let minWord = 0.05
        for idx in 1..<max(1, n) where idx < n {
            if let prev = starts[idx - 1], let cur = starts[idx], cur < prev + minWord {
                starts[idx] = min(prev + minWord, max(prev, duration))
            }
        }

        var result: [LyricLine] = []
        for (lineIndex, text) in lines.enumerated() {
            let indices = lyric.indices.filter { lyric[$0].line == lineIndex }
            guard let first = indices.first, let start = starts[first] else {
                result.append(LyricLine(text: text, startTime: nil))
                continue
            }
            let words: [LyricWord] = indices.enumerated().map { position, idx in
                let s = starts[idx] ?? start
                var e = ends[idx] ?? s + 0.3
                if idx + 1 < n, let next = starts[idx + 1] { e = min(e, max(s + 0.05, next)) }
                let word = lyric[idx].text + (position < indices.count - 1 ? " " : "")
                return LyricWord(text: word, start: s, end: max(e, s + 0.05))
            }
            result.append(LyricLine(text: text, startTime: start, words: words.count > 1 ? words : nil))
        }
        return Result(lines: LyricLine.monotonicTiming(result), matchedRatio: Double(matched) / Double(n))
    }

    /// Global alignment (Needleman–Wunsch, maximizing score): for every
    /// lyric word the index of the recognized word it matches, or nil.
    static func matchIndices(_ lyricNorm: [String], _ heardNorm: [String]) -> [Int?] {
        let n = lyricNorm.count, m = heardNorm.count
        guard n > 0 else { return [] }
        let gap = -0.4
        var score = [[Double]](repeating: [Double](repeating: 0, count: m + 1), count: n + 1)
        var move = [[UInt8]](repeating: [UInt8](repeating: 0, count: m + 1), count: n + 1) // 1 diag, 2 up (skip lyric), 3 left (skip heard)
        for i in 1...n { score[i][0] = Double(i) * gap; move[i][0] = 2 }
        if m > 0 { for j in 1...m { score[0][j] = Double(j) * gap * 0.5; move[0][j] = 3 } }
        if m > 0 {
            for i in 1...n {
                for j in 1...m {
                    let sim = wordSimilarity(lyricNorm[i - 1], heardNorm[j - 1])
                    let matchScore = sim >= matchThreshold ? sim * 2 : -0.6
                    let diag = score[i - 1][j - 1] + matchScore
                    let up = score[i - 1][j] + gap
                    let left = score[i][j - 1] + gap * 0.5   // extra recognized words are cheap (ad-libs)
                    if diag >= up && diag >= left {
                        score[i][j] = diag; move[i][j] = 1
                    } else if up >= left {
                        score[i][j] = up; move[i][j] = 2
                    } else {
                        score[i][j] = left; move[i][j] = 3
                    }
                }
            }
        }
        var match = [Int?](repeating: nil, count: n)
        var i = n, j = m
        while i > 0 || j > 0 {
            let step = (i > 0 && j > 0) ? move[i][j] : (i > 0 ? 2 : 3)
            if step == 1 {
                if wordSimilarity(lyricNorm[i - 1], heardNorm[j - 1]) >= matchThreshold { match[i - 1] = j - 1 }
                i -= 1; j -= 1
            } else if step == 2 {
                i -= 1
            } else {
                j -= 1
            }
        }
        return match
    }

    // MARK: Calibration anchors

    /// Pairs (time in the given synced lyrics, time heard in this recording)
    /// from confidently recognized words only: similarity ≥ 0.85, 3+
    /// letters, and a known original time (word timing, or the first word
    /// of a line-synced line). Outliers are left to the robust fit.
    static func anchors(lines: [LyricLine], recognized: [RecognizedWord]) -> [TimeAnchor] {
        var norms: [String] = []
        var times: [Double?] = []
        for line in lines {
            if let words = line.words, !words.isEmpty {
                for word in words {
                    for (k, part) in word.text.split(separator: " ").enumerated() {
                        norms.append(normalize(String(part)))
                        times.append(k == 0 ? word.start : nil)
                    }
                }
            } else {
                for (k, part) in line.text.split(whereSeparator: { $0 == " " || $0 == "\t" }).enumerated() {
                    norms.append(normalize(String(part)))
                    times.append(k == 0 ? line.startTime : nil)
                }
            }
        }
        let heard = recognized.filter { !normalize($0.text).isEmpty }
        let heardNorm = heard.map { normalize($0.text) }
        let match = matchIndices(norms, heardNorm)
        var result: [TimeAnchor] = []
        for (k, hit) in match.enumerated() {
            guard let hit, let original = times[k], norms[k].count >= 3,
                  wordSimilarity(norms[k], heardNorm[hit]) >= 0.85 else { continue }
            result.append(TimeAnchor(original: original, observed: heard[hit].start))
        }
        return result
    }

    // MARK: Partial sync (remixes)

    struct Occurrence: Equatable {
        let lineIndex: Int
        let start: Double
        let words: [LyricWord]
        let matched: Int
    }

    /// Every place in the recording where a lyric line is sung (≥ 70 % of
    /// its words, in order, within a short window) — repeats and reordered
    /// sections included. Non-overlapping, sorted by time.
    static func lineOccurrences(lines: [String], recognized: [RecognizedWord], minShare: Double = 0.7) -> [Occurrence] {
        let heard = recognized.filter { !normalize($0.text).isEmpty }.sorted { $0.start < $1.start }
        let heardNorm = heard.map { normalize($0.text) }
        var candidates: [(occurrence: Occurrence, end: Double)] = []
        for (lineIndex, line) in lines.enumerated() {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            let norms = parts.map(normalize)
            guard norms.count >= 2 else { continue }
            let window = norms.count * 2 + 2
            for startIndex in heardNorm.indices where wordSimilarity(norms[0], heardNorm[startIndex]) >= matchThreshold
                || (norms.count > 1 && wordSimilarity(norms[1], heardNorm[startIndex]) >= matchThreshold) {
                // Greedy in-order match of the line's words inside the window.
                var cursor = startIndex
                var hits: [Int?] = []
                for norm in norms {
                    var found: Int?
                    var probe = cursor
                    while probe < min(heardNorm.count, startIndex + window) {
                        if wordSimilarity(norm, heardNorm[probe]) >= matchThreshold { found = probe; break }
                        probe += 1
                    }
                    hits.append(found)
                    if let found { cursor = found + 1 }
                }
                let matched = hits.compactMap { $0 }.count
                guard Double(matched) / Double(norms.count) >= minShare,
                      let first = hits.compactMap({ $0 }).first, let last = hits.compactMap({ $0 }).last else { continue }
                // Word times: matched from recognition, gaps interpolated.
                var words: [LyricWord] = []
                for (k, part) in parts.enumerated() {
                    let text = part + (k < parts.count - 1 ? " " : "")
                    if let hit = hits[k] {
                        words.append(LyricWord(text: text, start: heard[hit].start, end: max(heard[hit].end, heard[hit].start + 0.05)))
                    } else {
                        let prevEnd = words.last?.end ?? heard[first].start
                        words.append(LyricWord(text: text, start: prevEnd, end: prevEnd + 0.2))
                    }
                }
                for k in 1..<words.count where words[k].start < words[k - 1].start + 0.05 {
                    let start = words[k - 1].start + 0.05
                    words[k] = LyricWord(text: words[k].text, start: start, end: max(words[k].end, start + 0.05))
                }
                candidates.append((Occurrence(lineIndex: lineIndex, start: heard[first].start, words: words, matched: matched),
                                   heard[last].end))
            }
        }
        // Best first; accept when it doesn't overlap an accepted one.
        let ranked = candidates.sorted {
            let a = Double($0.occurrence.matched) / Double(max(1, $0.occurrence.words.count))
            let b = Double($1.occurrence.matched) / Double(max(1, $1.occurrence.words.count))
            return a != b ? a > b : $0.occurrence.matched > $1.occurrence.matched
        }
        var accepted: [(occurrence: Occurrence, end: Double)] = []
        for candidate in ranked where !accepted.contains(where: {
            candidate.occurrence.start < $0.end && $0.occurrence.start < candidate.end
        }) {
            accepted.append(candidate)
        }
        return accepted.map(\.occurrence).sorted { $0.start < $1.start }
    }

    /// Indices of the longest non-decreasing subsequence of the non-nil
    /// values (patience sorting, O(n log n)).
    static func longestNonDecreasing(_ values: [Double?]) -> [Int] {
        var tailValues: [Double] = []
        var tailIndices: [Int] = []
        var previous = [Int](repeating: -1, count: values.count)
        for (index, value) in values.enumerated() {
            guard let value else { continue }
            // First tail strictly greater than value (non-decreasing run).
            var lo = 0, hi = tailValues.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if tailValues[mid] <= value { lo = mid + 1 } else { hi = mid }
            }
            if lo > 0 { previous[index] = tailIndices[lo - 1] }
            if lo == tailValues.count {
                tailValues.append(value); tailIndices.append(index)
            } else {
                tailValues[lo] = value; tailIndices[lo] = index
            }
        }
        var result: [Int] = []
        var cursor = tailIndices.last ?? -1
        while cursor >= 0 {
            result.append(cursor)
            cursor = previous[cursor]
        }
        return result.reversed()
    }
}
