//
//  CtcAligner.swift
//  Resona
//
//  Forced alignment (round 12, same as Resona-Android): the lyrics are known,
//  so instead of transcribing, find where their letters lie in a CTC model's
//  per-frame probabilities (Viterbi path blank → letter → letter …). The words
//  go through the same LyricsAligner/TempoCalibrator as Whisper's. Model:
//  wav2vec2-base-960h int8 (ONNX), vocabulary 0 = blank, 4 = word separator.
//  Measured on Android (Pixel, 169 s song): 10 s, median line error 0.07 s.
//

import Foundation

enum CtcAligner {
    static let blank = 0
    static let separator = 4
    static let frameSeconds = 0.02
    // Unicode scalars, not Characters: "Ü" decomposed is one Character but "U" + "◌̈" as scalars.
    private static let alphabet = Array("ETAONIHSRDLUMWCFGYPBVK'XJQZ".unicodeScalars)
    private static let firstLetter = 5

    struct Token: Equatable {
        let id: Int
        let word: Int
    }

    /// Letters of the model's alphabet; umlauts and accents fold to the plain letter.
    static func letters(_ word: String) -> [Int] {
        let folded = word.replacingOccurrences(of: "ß", with: "ss")
            .replacingOccurrences(of: "’", with: "'")
            .decomposedStringWithCanonicalMapping
            .uppercased(with: Locale(identifier: "en_US_POSIX"))
        return folded.unicodeScalars.compactMap { c in alphabet.firstIndex(of: c).map { firstLetter + $0 } }
    }

    static func tokens(_ words: [String]) -> [Token] {
        var out: [Token] = []
        for (index, word) in words.enumerated() {
            let ids = letters(word)
            if ids.isEmpty { continue }
            if !out.isEmpty { out.append(Token(id: separator, word: index)) }
            out += ids.map { Token(id: $0, word: index) }
        }
        return out
    }

    /// First frame of each token on the best path (monotonic); [emissions] = log probabilities per frame.
    static func path(_ emissions: [[Float]], tokens: [Int]) -> [Int] {
        let frames = emissions.count
        let count = tokens.count
        if count == 0 { return [] }
        if frames < count { return (0..<count).map { $0 * frames / count } }
        var advanced = [Bool](repeating: false, count: (frames + 1) * (count + 1))
        var scores = [Float](repeating: -.infinity, count: count + 1)
        var next = [Float](repeating: 0, count: count + 1)
        scores[0] = 0
        for t in 0..<frames {
            let row = emissions[t]
            next[0] = scores[0] + row[blank]
            for j in 1...count {
                // Stay: blank, or the letter just entered held on.
                let stay = scores[j] + max(row[blank], row[tokens[j - 1]])
                let enter = scores[j - 1] + row[tokens[j - 1]]
                if enter > stay {
                    next[j] = enter
                    advanced[t * (count + 1) + j] = true
                } else {
                    next[j] = stay
                }
            }
            swap(&scores, &next)
        }
        var starts = [Int](repeating: 0, count: count)
        var j = count
        var t = frames - 1
        while j > 0, t >= 0 {
            if advanced[t * (count + 1) + j] {
                starts[j - 1] = t
                j -= 1
            }
            t -= 1
        }
        return starts
    }

    /// Words on the best path; words the model doesn't really hear (mean letter
    /// probability below [minConfidence]) are left out, as with Whisper's gaps.
    static func words(_ emissions: [[Float]], lyricWords: [String], minConfidence: Double) -> [RecognizedWord] {
        let toks = tokens(lyricWords)
        let starts = path(emissions, tokens: toks.map(\.id))
        var out: [RecognizedWord] = []
        var i = 0
        while i < toks.count {
            let word = toks[i].word
            if toks[i].id == separator { i += 1; continue }
            var last = i
            var sum = 0.0
            var letters = 0
            while last < toks.count, toks[last].word == word, toks[last].id != separator {
                sum += exp(Double(emissions[starts[last]][toks[last].id]))
                letters += 1
                last += 1
            }
            let next = last < starts.count ? starts[last] : nil
            let endFrame = (next != nil && next! > starts[last - 1]) ? next! : starts[last - 1] + 1
            if sum / Double(letters) >= minConfidence {
                out.append(RecognizedWord(text: lyricWords[word], start: Double(starts[i]) * frameSeconds, end: Double(endFrame) * frameSeconds))
            }
            i = last
        }
        return out
    }
}

/// The CTC model: download once, only for lyrics in Latin script.
enum CtcModel {
    static let url = URL(string: "https://huggingface.co/onnx-community/wav2vec2-base-960h-ONNX/resolve/main/onnx/model_int8.onnx")!
    static let approxBytes: Int64 = 95_000_000
    static let threads = 4
    static let minConfidence = 0.05

    static var file: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("aisync/wav2vec2-base-960h-int8.onnx")
    }

    static var isDownloaded: Bool {
        ((try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? 0) > approxBytes * 9 / 10
    }

    /// Mostly letters the model knows (≥ 80 %, umlauts fold to a/o/u).
    static func suits(_ texts: [String]) -> Bool {
        let letters = texts.joined().filter(\.isLetter)
        guard letters.count >= 20 else { return false }
        return Double(CtcAligner.letters(String(letters)).count) >= Double(letters.count) * 0.8
    }

    static func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        let target = file
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let (temp, response) = try await URLSession.shared.download(from: url, delegate: nil)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: temp, to: target)
        progress(1)
    }
}
