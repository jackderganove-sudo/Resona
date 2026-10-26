//
//  ArtworkColorExtractor.swift
//  Resona
//
//  Pulls two things out of an album cover:
//   • a seed colour for the M3 scheme (Material's "Score" ranking: hue
//     population smoothed over ±15°, rewarded for chroma), and
//   • a small set of vivid, distinct colours for the player / mini-player
//     gradients (same idea as the reference app's PlayerColorExtractor).
//

import SwiftUI
import UIKit

struct ArtworkColors: Equatable, Sendable {
    var seed: RGB
    /// 1–6 colours ordered by visual weight, already tuned for backgrounds.
    var gradient: [RGB]
    var isGreyscale: Bool

    static let fallback = ArtworkColors(
        seed: M3Scheme.defaultSeed,
        gradient: [RGB(hex: 0x1D5D7A), RGB(hex: 0x0B3A55), RGB(hex: 0x14506B)],
        isGreyscale: false
    )
}

enum ArtworkColorExtractor {
    private struct Bucket {
        var rgb: RGB
        var count: Int
        var lch: OKLCH
    }

    /// Approximate conversion from OKLCH chroma to HCT chroma for scoring.
    private static func hctChroma(_ okChroma: Double) -> Double { okChroma / 0.0024 }

    static func extract(from image: UIImage) -> ArtworkColors {
        guard let buckets = quantize(image), !buckets.isEmpty else { return .fallback }
        let total = Double(buckets.reduce(0) { $0 + $1.count })

        // MARK: Seed (Material Score)

        var huePopulation = [Double](repeating: 0, count: 360)
        for b in buckets {
            huePopulation[Int(b.lch.h.rounded()) % 360] += Double(b.count)
        }
        var excited = [Double](repeating: 0, count: 360)
        for hue in 0..<360 {
            let proportion = huePopulation[hue] / total
            guard proportion > 0 else { continue }
            for offset in -14...15 {
                excited[(hue + offset + 360) % 360] += proportion
            }
        }

        var bestSeed: RGB?
        var bestScore = -Double.infinity
        for b in buckets {
            let chroma = hctChroma(b.lch.c)
            let proportion = excited[Int(b.lch.h.rounded()) % 360]
            guard chroma >= 5, proportion > 0.01 else { continue }
            let proportionScore = proportion * 100 * 0.7
            let chromaScore = (chroma - 48) * (chroma < 48 ? 0.1 : 0.3)
            let score = proportionScore + chromaScore
            if score > bestScore {
                bestScore = score
                bestSeed = b.rgb
            }
        }
        let dominant = buckets.max { $0.count < $1.count }?.rgb ?? M3Scheme.defaultSeed
        let seed = bestSeed ?? dominant

        // MARK: Gradient colours

        let ranked = buckets.sorted { weight($0) > weight($1) }
        let weightedSaturation = buckets.reduce(0.0) { $0 + $1.rgb.hsv.s * Double($1.count) } / total
        let isGreyscale = weightedSaturation < 0.22 || isNearGray(ranked.first?.rgb ?? dominant)

        var colors: [RGB] = []
        if isGreyscale {
            let base = dominant.hsv.v
            let stops = [
                min(max(base * 1.2, 0.06), 0.40),
                min(max(base * 0.9, 0.04), 0.28),
                min(max(base * 0.6, 0.02), 0.16),
                min(max(base * 1.4, 0.08), 0.44)
            ]
            colors = stops.map { RGB(h: 0, s: 0, v: $0) }
        } else {
            for b in ranked where colors.count < 6 {
                let hsv = b.rgb.hsv
                guard hsv.v > 0.08 else { continue }
                if !colors.contains(where: { similar($0, b.rgb) }) {
                    colors.append(enhance(b.rgb, saturationFactor: hsv.s > 0.3 ? 1.25 : 1.05))
                }
            }
            if colors.count < 3 {
                let base = colors.first ?? seed
                for shift in [25.0, -25.0, 55.0, -55.0] where colors.count < 3 {
                    let hsv = base.hsv
                    let derived = RGB(h: hsv.h + shift, s: min(max(hsv.s, 0.62) * 1.08, 1), v: min(max(hsv.v * 0.85 + 0.11, 0.38), 0.9))
                    if !colors.contains(where: { similar($0, derived) }) { colors.append(derived) }
                }
            }
        }

        return ArtworkColors(seed: seed, gradient: colors.isEmpty ? ArtworkColors.fallback.gradient : colors, isGreyscale: isGreyscale)
    }

    // MARK: Helpers

    /// Clamp a colour into a range that is comfortable as a large background
    /// behind white text (reference: PlayerBackgroundColorUtils).
    static func comfortable(_ c: RGB, minV: Double = 0.15, maxV: Double = 0.58, minS: Double = 0.32) -> RGB {
        let hsv = c.hsv
        if hsv.s < 0.05 { return RGB(h: 0, s: 0, v: min(max(hsv.v, minV), maxV)) }
        return RGB(h: hsv.h, s: max(hsv.s, minS), v: min(max(hsv.v, minV), maxV))
    }

    static func darken(_ c: RGB, _ factor: Double) -> RGB {
        let hsv = c.hsv
        return RGB(h: hsv.h, s: hsv.s, v: max(hsv.v * factor, 0))
    }

    private static func weight(_ b: Bucket) -> Double {
        let hsv = b.rgb.hsv
        let bonus = (hsv.s > 0.3 && hsv.v > 0.2 && hsv.v < 0.9) ? 1.3 : 1.0
        return Double(b.count) * bonus
    }

    private static func enhance(_ c: RGB, saturationFactor: Double) -> RGB {
        let hsv = c.hsv
        return RGB(h: hsv.h, s: min(hsv.s * saturationFactor, 1), v: min(max(hsv.v * 1.02, 0.32), 0.88))
    }

    private static func isNearGray(_ c: RGB) -> Bool {
        let hsv = c.hsv
        return hsv.s < 0.15 || hsv.v < 0.08
    }

    private static func similar(_ a: RGB, _ b: RGB) -> Bool {
        let ha = a.hsv, hb = b.hsv
        let rawHue = abs(ha.h - hb.h)
        let hueDiff = min(rawHue, 360 - rawHue)
        if hueDiff < 12, abs(ha.s - hb.s) < 0.12, abs(ha.v - hb.v) < 0.12 { return true }
        let t = 28.0 / 255.0
        return abs(a.r - b.r) < t && abs(a.g - b.g) < t && abs(a.b - b.b) < t
    }

    /// Downsamples to 48×48 and groups pixels into 5-bit-per-channel buckets.
    private static func quantize(_ image: UIImage) -> [Bucket]? {
        guard let cgImage = image.cgImage else { return nil }
        let side = 48
        var data = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(
            data: &data,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        var counts: [Int: (r: Int, g: Int, b: Int, n: Int)] = [:]
        for i in stride(from: 0, to: data.count, by: 4) where data[i + 3] > 200 {
            let r = Int(data[i]), g = Int(data[i + 1]), b = Int(data[i + 2])
            let key = (r >> 3) << 10 | (g >> 3) << 5 | (b >> 3)
            var entry = counts[key] ?? (0, 0, 0, 0)
            entry.r += r
            entry.g += g
            entry.b += b
            entry.n += 1
            counts[key] = entry
        }
        return counts.values.map { e in
            let rgb = RGB(r: Double(e.r) / Double(e.n) / 255, g: Double(e.g) / Double(e.n) / 255, b: Double(e.b) / Double(e.n) / 255)
            return Bucket(rgb: rgb, count: e.n, lch: ColorMath.oklch(rgb))
        }
    }
}
