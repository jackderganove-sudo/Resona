//
//  TempoCalibration.swift
//  Resona
//
//  "Calibrate with AI": instead of replacing synced lyrics with a Whisper
//  transcription, the existing (provider) lyrics are kept and only mapped
//  onto this recording:  time_here = factor × time_lyrics + offset.
//  Anchors are words Whisper recognized confidently; factor and offset come
//  from a robust line fit (Theil–Sen: median of pairwise slopes, then a
//  least-squares refit on the inliers), so a few wrong matches don't matter
//  and ~10 % recognized words are enough when they are spread over the song.
//

import Foundation
import Observation

struct TimeAnchor: Equatable, Sendable {
    /// Time in the lyrics (seconds).
    let original: Double
    /// Time the word was heard in this recording.
    let observed: Double
}

struct TempoCalibration: Codable, Equatable, Sendable {
    let factor: Double
    let offset: Double
    /// Inlier anchors the fit is based on.
    let anchors: Int
    /// RMS residual of the inliers (s).
    let rms: Double
}

enum TempoCalibrator {
    /// Minimum inliers for a trustworthy fit.
    static let minAnchors = 6

    enum Outcome: Equatable {
        case fitted(TempoCalibration)
        case tooFewAnchors(Int)
        case poorFit(TempoCalibration)
    }

    /// Robust fit of observed = factor × original + offset.
    static func fit(_ anchors: [TimeAnchor]) -> Outcome {
        guard anchors.count >= minAnchors else { return .tooFewAnchors(anchors.count) }
        // Theil–Sen on at most ~400 anchors (evenly thinned).
        let step = max(1, anchors.count / 400)
        let points = stride(from: 0, to: anchors.count, by: step).map { anchors[$0] }
        var slopes: [Double] = []
        slopes.reserveCapacity(points.count * points.count / 2)
        for i in 0..<points.count {
            for j in (i + 1)..<points.count {
                let dx = points[j].original - points[i].original
                guard abs(dx) > 1 else { continue }   // too close for a slope
                slopes.append((points[j].observed - points[i].observed) / dx)
            }
        }
        guard !slopes.isEmpty else { return .tooFewAnchors(anchors.count) }
        let slope = median(slopes)
        let intercept = median(anchors.map { $0.observed - slope * $0.original })

        // Inliers within 1 s, then ordinary least squares on them.
        let inliers = anchors.filter { abs($0.observed - (slope * $0.original + intercept)) <= 1.0 }
        guard inliers.count >= minAnchors else { return .tooFewAnchors(inliers.count) }
        let (factor, offset) = leastSquares(inliers) ?? (slope, intercept)
        let residuals = inliers.map { $0.observed - (factor * $0.original + offset) }
        let rms = sqrt(residuals.map { $0 * $0 }.reduce(0, +) / Double(residuals.count))
        let calibration = TempoCalibration(factor: factor, offset: offset, anchors: inliers.count, rms: rms)

        // Trustworthy: plausible factor, tight fit, anchors spread out.
        let originals = inliers.map(\.original)
        let spread = (originals.max() ?? 0) - (originals.min() ?? 0)
        let total = (anchors.map(\.original).max() ?? 0) - (anchors.map(\.original).min() ?? 0)
        guard (0.6...1.6).contains(factor), rms <= 0.6, spread >= max(20, total * 0.3) else {
            return .poorFit(calibration)
        }
        return .fitted(calibration)
    }

    /// Lines (and word timings) mapped onto the recording.
    static func apply(_ lines: [LyricLine], _ calibration: TempoCalibration) -> [LyricLine] {
        func map(_ t: Double) -> Double { max(0, calibration.factor * t + calibration.offset) }
        return lines.map { line in
            var copy = LyricLine(
                text: line.text,
                startTime: line.startTime.map(map),
                words: line.words?.map { LyricWord(text: $0.text, start: map($0.start), end: map($0.end)) },
                backgroundText: line.backgroundText,
                translation: line.translation
            )
            copy.id = line.id
            return copy
        }
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    private static func leastSquares(_ points: [TimeAnchor]) -> (Double, Double)? {
        let n = Double(points.count)
        let sx = points.reduce(0) { $0 + $1.original }, sy = points.reduce(0) { $0 + $1.observed }
        let sxx = points.reduce(0) { $0 + $1.original * $1.original }
        let sxy = points.reduce(0) { $0 + $1.original * $1.observed }
        let denominator = n * sxx - sx * sx
        guard abs(denominator) > 1e-9 else { return nil }
        let factor = (n * sxy - sx * sy) / denominator
        return (factor, (sy - factor * sx) / n)
    }
}

/// Calibrations per song, relative to the provider's ORIGINAL timestamps
/// (before any automatic slowed/sped-up scaling).
@MainActor
@Observable
final class LyricsCalibrationStore {
    static let shared = LyricsCalibrationStore()

    private(set) var calibrations: [String: TempoCalibration]
    private static let key = "resona.lyrics.aiCalibration"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let stored = try? JSONDecoder().decode([String: TempoCalibration].self, from: data) {
            calibrations = stored
        } else {
            calibrations = [:]
        }
    }

    func calibration(for videoId: String?) -> TempoCalibration? {
        videoId.flatMap { calibrations[$0] }
    }

    func set(_ calibration: TempoCalibration?, for videoId: String) {
        calibrations[videoId] = calibration
        if let data = try? JSONEncoder().encode(calibrations) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

/// Slowed / sped-up songs: calibrate the tempo with AI?
enum AICalibrationMode: String, CaseIterable, Identifiable, SettingsOption {
    case off
    case ask
    case automaticOnWiFi

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .ask: return "Ask"
        case .automaticOnWiFi: return "Automatically on Wi-Fi"
        }
    }
}
