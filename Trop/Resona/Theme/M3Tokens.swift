//
//  M3Tokens.swift
//  Resona
//
//  Material 3 Expressive design tokens: type scale (Poppins), shape scale,
//  spacing, motion springs and the fixed dimensions of the reference app.
//

import CoreText
import SwiftUI

// MARK: - Typography

enum M3TypeStyle: CaseIterable {
    case displayLarge, displayMedium, displaySmall
    case headlineLarge, headlineMedium, headlineSmall
    case titleLarge, titleMedium, titleSmall
    case bodyLarge, bodyMedium, bodySmall
    case labelLarge, labelMedium, labelSmall

    /// (size, lineHeight, weight, tracking) — Material 3 baseline type scale.
    var spec: (size: CGFloat, lineHeight: CGFloat, weight: Font.Weight, tracking: CGFloat) {
        switch self {
        case .displayLarge: (57, 64, .regular, 0)
        case .displayMedium: (45, 52, .regular, 0)
        case .displaySmall: (36, 44, .regular, 0)
        case .headlineLarge: (32, 40, .regular, 0)
        case .headlineMedium: (28, 36, .regular, 0)
        case .headlineSmall: (24, 32, .regular, 0)
        case .titleLarge: (22, 28, .regular, 0)
        case .titleMedium: (16, 24, .medium, 0.15)
        case .titleSmall: (14, 20, .medium, 0.1)
        case .bodyLarge: (16, 24, .regular, 0.5)
        case .bodyMedium: (14, 20, .regular, 0.25)
        case .bodySmall: (12, 16, .regular, 0.4)
        case .labelLarge: (14, 20, .medium, 0.1)
        case .labelMedium: (12, 16, .medium, 0.5)
        case .labelSmall: (11, 16, .medium, 0.5)
        }
    }

    var textStyle: Font.TextStyle {
        switch self {
        case .displayLarge, .displayMedium, .displaySmall: .largeTitle
        case .headlineLarge, .headlineMedium: .title
        case .headlineSmall, .titleLarge: .title2
        case .titleMedium: .headline
        case .titleSmall: .subheadline
        case .bodyLarge: .body
        case .bodyMedium: .callout
        case .bodySmall: .footnote
        case .labelLarge: .subheadline
        case .labelMedium: .caption
        case .labelSmall: .caption2
        }
    }
}

enum M3Font {
    private static var registered = false

    /// Registers the bundled Poppins faces. Call once at launch.
    static func registerFonts() {
        guard !registered else { return }
        registered = true
        for name in ["Poppins-Regular", "Poppins-Medium", "Poppins-SemiBold", "Poppins-Bold"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func name(for weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black: "Poppins-Bold"
        case .semibold: "Poppins-SemiBold"
        case .medium: "Poppins-Medium"
        default: "Poppins-Regular"
        }
    }
}

extension Font {
    /// Material 3 type style rendered in Poppins, scaling with Dynamic Type.
    static func m3(_ style: M3TypeStyle, weight: Font.Weight? = nil) -> Font {
        let spec = style.spec
        return .custom(M3Font.name(for: weight ?? spec.weight), size: spec.size, relativeTo: style.textStyle)
    }

    /// Poppins at an explicit size.
    static func poppins(_ size: CGFloat, weight: Font.Weight = .regular, relativeTo: Font.TextStyle = .body) -> Font {
        .custom(M3Font.name(for: weight), size: size, relativeTo: relativeTo)
    }
}

extension View {
    /// Font + tracking + approximate line height of an M3 type style.
    func m3Text(_ style: M3TypeStyle, weight: Font.Weight? = nil) -> some View {
        let spec = style.spec
        return font(.m3(style, weight: weight))
            .tracking(spec.tracking)
            .lineSpacing(max(0, spec.lineHeight - spec.size * 1.5))
    }
}

// MARK: - Shapes

enum M3Shape {
    static let extraSmall: CGFloat = 8
    static let small: CGFloat = 12
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
    static let largeIncreased: CGFloat = 20
    static let extraLarge: CGFloat = 28
    static let extraLargeIncreased: CGFloat = 32
    static let extraExtraLarge: CGFloat = 48

    /// Outer radius of grouped list sections, inner radius between rows.
    static let groupOuter: CGFloat = 28
    static let groupInner: CGFloat = 6
}

// MARK: - Spacing / dimensions (reference app values, in points)

enum M3Metrics {
    static let screenPadding: CGFloat = 16
    /// Maximum width of lists and forms on wide screens (iPad landscape).
    static let contentMaxWidth: CGFloat = 900
    static let sectionSpacing: CGFloat = 24

    static let navigationBarHeight: CGFloat = 78
    static let navigationBarHorizontalPadding: CGFloat = 12
    static let navigationBarBottomPadding: CGFloat = 10
    static let navigationBarMaxWidth: CGFloat = 420
    static let navigationRailWidth: CGFloat = 96

    static let miniPlayerHeight: CGFloat = 70
    static let miniPlayerBottomSpacing: CGFloat = 4

    static let floatingBarStandaloneRadius: CGFloat = 32
    static let floatingBarOuterRadius: CGFloat = 28
    static let floatingBarJunctionRadius: CGFloat = 12

    static let listItemHeight: CGFloat = 72
    static let listThumbnail: CGFloat = 56
    static let thumbnailRadius: CGFloat = 10
    static let gridThumbnail: CGFloat = 128
    static let gridThumbnailRadius: CGFloat = 8
    static let playerHorizontalPadding: CGFloat = 32

    /// Space content must leave at the bottom so the floating bars don't
    /// cover it.
    static func bottomChrome(miniPlayerVisible: Bool, usesRail: Bool) -> CGFloat {
        var total: CGFloat = 0
        if !usesRail { total += navigationBarHeight + navigationBarBottomPadding }
        if miniPlayerVisible { total += miniPlayerHeight + miniPlayerBottomSpacing }
        return total + 12
    }
}

// MARK: - Motion (Material 3 Expressive motion scheme)

enum M3Motion {
    private static func spring(damping ratio: Double, stiffness: Double) -> Animation {
        .interpolatingSpring(mass: 1, stiffness: stiffness, damping: 2 * ratio * stiffness.squareRoot(), initialVelocity: 0)
    }

    // Response of a spring ≈ 2π / √stiffness. Interaction motion stays in
    // the 0.22–0.35 s range so every tap feels immediate.

    /// Expressive spatial springs (overshoot a little).
    /// fast ≈ 0.22 s · default ≈ 0.31 s · slow ≈ 0.35 s
    static let fastSpatial = spring(damping: 0.6, stiffness: 800)
    static let defaultSpatial = spring(damping: 0.8, stiffness: 400)
    static let slowSpatial = spring(damping: 0.82, stiffness: 320)

    /// Effects springs (no overshoot) for colour/opacity.
    static let fastEffects = spring(damping: 1, stiffness: 3800)
    static let defaultEffects = spring(damping: 1, stiffness: 1600)
    static let slowEffects = spring(damping: 1, stiffness: 800)

    /// Navigation bar / mini player show-hide (no bounce, ≈ 0.33 s).
    static let navigationBar = spring(damping: 1, stiffness: 360)
    /// Player sheet expand/collapse (no bounce, ≈ 0.3 s).
    static let bottomSheet = spring(damping: 0.92, stiffness: 440)
    /// Lyrics glide to the next line (reference video: ~0.55 s, soft settle).
    /// Lyrics glide to the next line: soft spring with a slight bounce
    /// (response 0.5 s, damping 0.75).
    static let lyricsScroll = Animation.spring(response: 0.5, dampingFraction: 0.75)
    /// Theme colour cross-fade when the artwork changes.
    static let colorChange = Animation.easeInOut(duration: 0.4)
    /// Short fades (images appearing, small state changes).
    static let quickFade = Animation.easeOut(duration: 0.18)
}
