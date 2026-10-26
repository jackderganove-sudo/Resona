//
//  M3Scheme.swift
//  Resona
//
//  Material 3 colour roles generated from a single seed colour, following the
//  "Tonal Spot" scheme (the Android default and what the reference app uses).
//  Chroma constants are calibrated so a blue seed reproduces the reference
//  screenshots (surface #101418, surfaceContainer #1C2024, primary #99CCF9,
//  primaryContainer #064B72).
//

import SwiftUI

struct M3Scheme: Equatable, Sendable {
    var isDark: Bool

    var primary: Color
    var onPrimary: Color
    var primaryContainer: Color
    var onPrimaryContainer: Color
    var inversePrimary: Color

    var secondary: Color
    var onSecondary: Color
    var secondaryContainer: Color
    var onSecondaryContainer: Color

    var tertiary: Color
    var onTertiary: Color
    var tertiaryContainer: Color
    var onTertiaryContainer: Color

    var error: Color
    var onError: Color
    var errorContainer: Color
    var onErrorContainer: Color

    var background: Color
    var onBackground: Color
    var surface: Color
    var onSurface: Color
    var surfaceVariant: Color
    var onSurfaceVariant: Color
    var surfaceDim: Color
    var surfaceBright: Color
    var surfaceContainerLowest: Color
    var surfaceContainerLow: Color
    var surfaceContainer: Color
    var surfaceContainerHigh: Color
    var surfaceContainerHighest: Color
    var inverseSurface: Color
    var inverseOnSurface: Color

    var outline: Color
    var outlineVariant: Color
    var scrim: Color

    /// The seed the scheme was generated from (gamma sRGB).
    var seed: RGB
}

/// How colourful the generated palettes are, chosen from the seed's chroma
/// exactly like the reference (Monochrome < Neutral < Tonal Spot).
enum M3PaletteStyle: Sendable {
    case tonalSpot
    case neutral
    case monochrome

    static func forSeed(chroma: Double) -> M3PaletteStyle {
        if chroma < 0.012 { return .monochrome }
        if chroma < 0.035 { return .neutral }
        return .tonalSpot
    }
}

struct M3CorePalettes: Sendable {
    let primary: TonalPalette
    let secondary: TonalPalette
    let tertiary: TonalPalette
    let neutral: TonalPalette
    let neutralVariant: TonalPalette

    init(seed: RGB) {
        let lch = ColorMath.oklch(seed)
        let hue = lch.h
        switch M3PaletteStyle.forSeed(chroma: lch.c) {
        case .tonalSpot:
            primary = TonalPalette(hue: hue, chroma: 0.086)
            secondary = TonalPalette(hue: hue, chroma: 0.038)
            tertiary = TonalPalette(hue: (hue + 60).truncatingRemainder(dividingBy: 360), chroma: 0.057)
            neutral = TonalPalette(hue: hue, chroma: 0.0100)
            neutralVariant = TonalPalette(hue: hue + 8, chroma: 0.0125)
        case .neutral:
            primary = TonalPalette(hue: hue, chroma: 0.030)
            secondary = TonalPalette(hue: hue, chroma: 0.020)
            tertiary = TonalPalette(hue: (hue + 60).truncatingRemainder(dividingBy: 360), chroma: 0.038)
            neutral = TonalPalette(hue: hue, chroma: 0.0040)
            neutralVariant = TonalPalette(hue: hue, chroma: 0.0050)
        case .monochrome:
            primary = TonalPalette(hue: hue, chroma: 0)
            secondary = TonalPalette(hue: hue, chroma: 0)
            tertiary = TonalPalette(hue: hue, chroma: 0)
            neutral = TonalPalette(hue: hue, chroma: 0)
            neutralVariant = TonalPalette(hue: hue, chroma: 0)
        }
    }
}

extension M3Scheme {
    /// Default seed used before any artwork is available — the blue from the
    /// reference screenshots.
    static let defaultSeed = RGB(hex: 0x2E7DB5)

    static let fallbackDark = M3Scheme.generate(seed: defaultSeed, dark: true)

    static func generate(seed: RGB, dark: Bool, pureBlack: Bool = false) -> M3Scheme {
        let p = M3CorePalettes(seed: seed)
        if dark {
            var scheme = M3Scheme(
                isDark: true,
                primary: p.primary(80),
                onPrimary: p.primary(20),
                primaryContainer: p.primary(30),
                onPrimaryContainer: p.primary(90),
                inversePrimary: p.primary(40),
                secondary: p.secondary(80),
                onSecondary: p.secondary(20),
                secondaryContainer: p.secondary(30),
                onSecondaryContainer: p.secondary(90),
                tertiary: p.tertiary(80),
                onTertiary: p.tertiary(20),
                tertiaryContainer: p.tertiary(30),
                onTertiaryContainer: p.tertiary(90),
                error: RGB(hex: 0xFFB4AB).color,
                onError: RGB(hex: 0x690005).color,
                errorContainer: RGB(hex: 0x93000A).color,
                onErrorContainer: RGB(hex: 0xFFDAD6).color,
                background: p.neutral(6),
                onBackground: p.neutral(90),
                surface: p.neutral(6),
                onSurface: p.neutral(90),
                surfaceVariant: p.neutralVariant(30),
                onSurfaceVariant: p.neutralVariant(80),
                surfaceDim: p.neutral(6),
                surfaceBright: p.neutral(24),
                surfaceContainerLowest: p.neutral(4),
                surfaceContainerLow: p.neutral(10),
                surfaceContainer: p.neutral(12),
                surfaceContainerHigh: p.neutral(17),
                surfaceContainerHighest: p.neutral(22),
                inverseSurface: p.neutral(90),
                inverseOnSurface: p.neutral(20),
                outline: p.neutralVariant(60),
                outlineVariant: p.neutralVariant(30),
                scrim: .black,
                seed: seed
            )
            if pureBlack {
                scheme.background = .black
                scheme.surface = .black
                scheme.surfaceDim = .black
                scheme.surfaceContainerLowest = .black
            }
            return scheme
        }
        return M3Scheme(
            isDark: false,
            primary: p.primary(40),
            onPrimary: p.primary(100),
            primaryContainer: p.primary(90),
            onPrimaryContainer: p.primary(10),
            inversePrimary: p.primary(80),
            secondary: p.secondary(40),
            onSecondary: p.secondary(100),
            secondaryContainer: p.secondary(90),
            onSecondaryContainer: p.secondary(10),
            tertiary: p.tertiary(40),
            onTertiary: p.tertiary(100),
            tertiaryContainer: p.tertiary(90),
            onTertiaryContainer: p.tertiary(10),
            error: RGB(hex: 0xBA1A1A).color,
            onError: .white,
            errorContainer: RGB(hex: 0xFFDAD6).color,
            onErrorContainer: RGB(hex: 0x410002).color,
            background: p.neutral(98),
            onBackground: p.neutral(10),
            surface: p.neutral(98),
            onSurface: p.neutral(10),
            surfaceVariant: p.neutralVariant(90),
            onSurfaceVariant: p.neutralVariant(30),
            surfaceDim: p.neutral(87),
            surfaceBright: p.neutral(98),
            surfaceContainerLowest: p.neutral(100),
            surfaceContainerLow: p.neutral(96),
            surfaceContainer: p.neutral(94),
            surfaceContainerHigh: p.neutral(92),
            surfaceContainerHighest: p.neutral(90),
            inverseSurface: p.neutral(20),
            inverseOnSurface: p.neutral(95),
            outline: p.neutralVariant(50),
            outlineVariant: p.neutralVariant(80),
            scrim: .black,
            seed: seed
        )
    }
}
