//
//  CoverPalette.swift
//  Resona
//
//  The single cover-colour source for everything that should "be" the cover
//  colour: the player's mesh background and the tint of every frosted glass
//  surface (mini player, bars, sheets, menus). Built from the M3 seed hue
//  (same hue as the app scheme) plus 1–2 vivid cover tones, saturation
//  ~25 % above the cover. Brightness and WCAG contrast are applied by the
//  player background itself (user setting).
//

import SwiftUI

struct CoverPalette: Equatable, Sendable {
    /// Mesh colours: [main, vivid 1, vivid 2, deep].
    var colors: [RGB]
    var isGreyscale: Bool

    /// The cover colour as one value (glass tint, mini player).
    var main: RGB { colors.first ?? M3Scheme.defaultSeed }

    static let fallback = CoverPalette.make(from: .fallback)

    static func make(from artwork: ArtworkColors) -> CoverPalette {
        if artwork.isGreyscale {
            // Near black-and-white cover: calm neutral greys.
            let greys = [0.34, 0.27, 0.21, 0.16].map { RGB(h: 0, s: 0, v: $0) }
            return CoverPalette(colors: greys, isGreyscale: true)
        }
        let seed = artwork.seed.hsv
        func vibrant(_ c: RGB, v: Double) -> RGB {
            let hsv = c.hsv
            // Saturation ~25 % above the cover, never muted.
            return RGB(h: hsv.h, s: min(1, max(0.58, hsv.s * 1.25)), v: v)
        }
        func hueShift(_ degrees: Double) -> RGB {
            RGB(h: seed.h + degrees, s: seed.s, v: seed.v)
        }
        // Extra tones: vivid cover colours that differ from the seed hue,
        // otherwise neighbouring hues of the seed.
        let extras = artwork.vivid.filter { c in
            let d = abs(c.hsv.h - seed.h)
            return min(d, 360 - d) > 20
        }
        let tone1 = extras.first ?? artwork.vivid.first ?? hueShift(-18)
        let tone2 = extras.dropFirst().first ?? hueShift(22)
        return CoverPalette(
            colors: [
                vibrant(artwork.seed, v: 0.66),
                vibrant(tone1, v: 0.58),
                vibrant(tone2, v: 0.5),
                vibrant(artwork.seed, v: 0.38)
            ],
            isGreyscale: false
        )
    }
}

extension RGB {
    /// WCAG relative luminance.
    var relativeLuminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }
}

private struct CoverPaletteKey: EnvironmentKey {
    static let defaultValue = CoverPalette.fallback
}

extension EnvironmentValues {
    /// Cover colours shared by the player background and all glass tints.
    var coverPalette: CoverPalette {
        get { self[CoverPaletteKey.self] }
        set { self[CoverPaletteKey.self] = newValue }
    }
}
