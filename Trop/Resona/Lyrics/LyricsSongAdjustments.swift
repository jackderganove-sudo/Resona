//
//  LyricsSongAdjustments.swift
//  Resona
//
//  Per-song manual corrections from the lyrics menu: tempo (scales all
//  line/word timestamps, nil = automatic) and offset. Stored by video id.
//

import Foundation
import Observation

@MainActor
@Observable
final class LyricsSongAdjustments {
    static let shared = LyricsSongAdjustments()

    private(set) var tempos: [String: Double]
    private(set) var offsets: [String: Double]

    private enum Keys {
        static let tempos = "resona.lyrics.tempoBySong"
        static let offsets = "resona.lyrics.offsetBySong"
    }

    private init() {
        let d = UserDefaults.standard
        tempos = d.dictionary(forKey: Keys.tempos) as? [String: Double] ?? [:]
        offsets = d.dictionary(forKey: Keys.offsets) as? [String: Double] ?? [:]
    }

    func tempo(for videoId: String?) -> Double? {
        videoId.flatMap { tempos[$0] }
    }

    func setTempo(_ value: Double?, for videoId: String?) {
        guard let videoId else { return }
        tempos[videoId] = value.map { min(1.5, max(0.6, $0)) }
        UserDefaults.standard.set(tempos, forKey: Keys.tempos)
    }

    func offset(for videoId: String?) -> Double {
        videoId.flatMap { offsets[$0] } ?? 0
    }

    func setOffset(_ value: Double, for videoId: String?) {
        guard let videoId else { return }
        offsets[videoId] = value == 0 ? nil : value
        UserDefaults.standard.set(offsets, forKey: Keys.offsets)
    }
}
