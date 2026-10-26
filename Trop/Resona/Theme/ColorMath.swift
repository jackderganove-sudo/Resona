//
//  ColorMath.swift
//  Resona
//
//  Colour-space helpers for the Material 3 tonal system.
//
//  Material's HCT space combines CAM16 hue/chroma with CIELAB L* ("tone").
//  Resona approximates it with OKLCH hue/chroma (perceptually even hues, no
//  blue→purple drift) while solving lightness so that every colour hits the
//  exact CIELAB L* tone Material prescribes. Tone is what drives contrast in
//  the M3 role mapping, so contrast behaves like the real thing.
//

import SwiftUI
import UIKit

/// Linear-light or gamma-encoded sRGB triple, components nominally in 0...1.
struct RGB: Equatable, Hashable, Sendable {
    var r: Double
    var g: Double
    var b: Double

    static let black = RGB(r: 0, g: 0, b: 0)
    static let white = RGB(r: 1, g: 1, b: 1)

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    init(hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    init(_ uiColor: UIColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(r: Double(r), g: Double(g), b: Double(b))
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }
    var uiColor: UIColor { UIColor(red: r, green: g, blue: b, alpha: 1) }

    var clamped: RGB {
        RGB(r: min(max(r, 0), 1), g: min(max(g, 0), 1), b: min(max(b, 0), 1))
    }

    func mix(_ other: RGB, _ t: Double) -> RGB {
        RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    // MARK: Transfer functions

    private static func toLinear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private static func toGamma(_ c: Double) -> Double {
        c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
    }

    var linear: RGB { RGB(r: Self.toLinear(r), g: Self.toLinear(g), b: Self.toLinear(b)) }
    var gamma: RGB { RGB(r: Self.toGamma(r), g: Self.toGamma(g), b: Self.toGamma(b)) }

    /// Relative luminance Y (0...1) of a gamma-encoded colour.
    var luminance: Double {
        let l = linear
        return 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b
    }

    /// CIELAB L* (0...100) — Material's "tone".
    var tone: Double { ColorMath.lstar(fromY: luminance) }

    // MARK: HSV (used by the artwork gradient tuning, mirrors Android's Color.colorToHSV)

    var hsv: (h: Double, s: Double, v: Double) {
        let maxC = max(r, g, b), minC = min(r, g, b)
        let delta = maxC - minC
        var h = 0.0
        if delta > 0 {
            if maxC == r {
                h = 60 * (((g - b) / delta).truncatingRemainder(dividingBy: 6))
            } else if maxC == g {
                h = 60 * (((b - r) / delta) + 2)
            } else {
                h = 60 * (((r - g) / delta) + 4)
            }
        }
        if h < 0 { h += 360 }
        let s = maxC == 0 ? 0 : delta / maxC
        return (h, s, maxC)
    }

    init(h: Double, s: Double, v: Double) {
        let c = v * s
        let hp = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        var rgb: (Double, Double, Double)
        switch hp {
        case 0..<1: rgb = (c, x, 0)
        case 1..<2: rgb = (x, c, 0)
        case 2..<3: rgb = (0, c, x)
        case 3..<4: rgb = (0, x, c)
        case 4..<5: rgb = (x, 0, c)
        default: rgb = (c, 0, x)
        }
        let m = v - c
        self.init(r: rgb.0 + m, g: rgb.1 + m, b: rgb.2 + m)
    }
}

/// OKLCH colour (lightness 0...1, chroma ~0...0.37, hue in degrees).
struct OKLCH: Equatable, Sendable {
    var l: Double
    var c: Double
    var h: Double
}

enum ColorMath {
    private static let epsilon = 216.0 / 24389.0
    private static let kappa = 24389.0 / 27.0

    static func lstar(fromY y: Double) -> Double {
        y > epsilon ? 116 * cbrt(y) - 16 : kappa * y
    }

    static func y(fromLstar l: Double) -> Double {
        l > kappa * epsilon ? pow((l + 16) / 116, 3) : l / kappa
    }

    // MARK: OKLab

    static func oklch(_ rgb: RGB) -> OKLCH {
        let lin = rgb.linear
        let l = cbrt(0.4122214708 * lin.r + 0.5363325363 * lin.g + 0.0514459929 * lin.b)
        let m = cbrt(0.2119034982 * lin.r + 0.6806995451 * lin.g + 0.1073969566 * lin.b)
        let s = cbrt(0.0883024619 * lin.r + 0.2817188376 * lin.g + 0.6299787005 * lin.b)
        let L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        var h = atan2(b, a) * 180 / .pi
        if h < 0 { h += 360 }
        return OKLCH(l: L, c: sqrt(a * a + b * b), h: h)
    }

    /// Linear (unclamped) sRGB for an OKLCH colour.
    static func linearRGB(_ c: OKLCH) -> RGB {
        let hr = c.h * .pi / 180
        let a = c.c * cos(hr), b = c.c * sin(hr)
        let l_ = c.l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = c.l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = c.l - 0.0894841775 * a - 1.2914855480 * b
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        return RGB(
            r: 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            g: -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            b: -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        )
    }

    private static func inGamut(_ lin: RGB) -> Bool {
        let e = 1e-4
        return lin.r >= -e && lin.r <= 1 + e && lin.g >= -e && lin.g <= 1 + e && lin.b >= -e && lin.b <= 1 + e
    }

    private static func luminance(linear lin: RGB) -> Double {
        0.2126 * lin.r + 0.7152 * lin.g + 0.0722 * lin.b
    }

    /// OKLab lightness that yields the requested luminance for a hue/chroma.
    private static func solveLightness(hue: Double, chroma: Double, targetY: Double) -> Double {
        var lo = 0.0, hi = 1.0
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            let y = luminance(linear: linearRGB(OKLCH(l: mid, c: chroma, h: hue)))
            if y < targetY { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    /// A gamma-encoded sRGB colour with the given OKLCH hue, the requested
    /// chroma (reduced until it fits the sRGB gamut) and exact L* tone.
    static func solve(hue: Double, chroma: Double, tone: Double) -> RGB {
        if tone <= 0.0001 { return .black }
        if tone >= 99.9999 { return .white }
        let targetY = y(fromLstar: tone)

        func candidate(_ c: Double) -> RGB {
            let l = solveLightness(hue: hue, chroma: c, targetY: targetY)
            return linearRGB(OKLCH(l: l, c: c, h: hue))
        }

        let full = candidate(chroma)
        if inGamut(full) { return full.clamped.gamma }

        var lo = 0.0, hi = chroma
        var best = candidate(0)
        for _ in 0..<18 {
            let mid = (lo + hi) / 2
            let lin = candidate(mid)
            if inGamut(lin) {
                lo = mid
                best = lin
            } else {
                hi = mid
            }
        }
        return best.clamped.gamma
    }
}

/// A Material tonal palette: one hue/chroma, any tone 0...100.
struct TonalPalette: Sendable {
    let hue: Double
    let chroma: Double

    func tone(_ t: Double) -> RGB {
        ColorMath.solve(hue: hue, chroma: chroma, tone: t)
    }

    func callAsFunction(_ t: Double) -> Color { tone(t).color }
}
