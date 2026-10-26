//
//  M3Components.swift
//  Resona
//
//  Small Material 3 Expressive building blocks shared by all screens:
//  press-morphing buttons, icon buttons, chips, tonal cards and section
//  headers.
//

import SwiftUI

// MARK: - Press feedback

/// Expressive press: the element squishes slightly and its corners tighten,
/// then springs back with a small overshoot.
struct ExpressivePressStyle: ButtonStyle {
    var scale: CGFloat = 0.94
    var haptic: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(configuration.isPressed ? M3Motion.fastEffects : M3Motion.fastSpatial, value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: configuration.isPressed) { _, pressed in
                haptic && pressed
            }
    }
}

extension ButtonStyle where Self == ExpressivePressStyle {
    static var expressive: ExpressivePressStyle { ExpressivePressStyle() }
    static func expressive(scale: CGFloat) -> ExpressivePressStyle { ExpressivePressStyle(scale: scale) }
}

/// A rounded rectangle whose radius shrinks while pressed (M3 shape morph).
struct MorphingShapeButtonStyle: ButtonStyle {
    var radius: CGFloat
    var pressedRadius: CGFloat
    var fill: Color
    var foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        let r = configuration.isPressed ? pressedRadius : radius
        configuration.label
            .foregroundStyle(foreground)
            .background(fill, in: RoundedRectangle(cornerRadius: r, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: r, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(M3Motion.fastSpatial, value: configuration.isPressed)
    }
}

// MARK: - Icon buttons

enum M3IconButtonKind {
    case standard, tonal, filled, onDark
}

struct M3IconButton: View {
    @Environment(\.m3) private var m3
    let systemName: String
    var kind: M3IconButtonKind = .standard
    var size: CGFloat = 48
    var iconSize: CGFloat = 20
    var tint: Color?
    var accessibility: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(tint ?? foreground)
                .frame(width: size, height: size)
                .background(background, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.expressive(scale: 0.88))
        .accessibilityLabel(accessibility ?? systemName)
    }

    private var foreground: Color {
        switch kind {
        case .standard: m3.onSurfaceVariant
        case .tonal: m3.onSecondaryContainer
        case .filled: m3.onPrimary
        case .onDark: .white
        }
    }

    private var background: Color {
        switch kind {
        case .standard: .clear
        case .tonal: m3.surfaceContainerHigh
        case .filled: m3.primary
        case .onDark: .white.opacity(0.16)
        }
    }
}

// MARK: - Chips

/// Pill chip used for filters / mood chips. Selected chips become primary
/// filled like in the reference library screen.
struct M3Chip: View {
    @Environment(\.m3) private var m3
    let title: String
    var systemImage: String?
    var isSelected: Bool = false
    var height: CGFloat = 40
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(title)
                    .font(.m3(.labelLarge, weight: .regular))
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .frame(height: height)
            .foregroundStyle(isSelected ? m3.onPrimary : m3.onSurfaceVariant)
            .background(isSelected ? m3.primary : m3.surfaceContainerHigh, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.expressive)
        .animation(M3Motion.defaultEffects, value: isSelected)
    }
}

/// Small rounded label like "Persönlich" / "Mit YouTube synchronisiert".
struct M3Badge: View {
    @Environment(\.m3) private var m3
    let text: String

    var body: some View {
        Text(text)
            .font(.m3(.labelLarge, weight: .regular))
            .foregroundStyle(m3.primary)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .background(m3.primaryContainer.opacity(0.45), in: Capsule())
    }
}

// MARK: - Surfaces

extension View {
    /// Tonal surface card with a continuous rounded shape.
    func m3Card(_ color: Color, radius: CGFloat = M3Shape.extraLarge) -> some View {
        background(color, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// Screen background in the current scheme's surface colour.
    func m3ScreenBackground() -> some View {
        modifier(M3ScreenBackground())
    }
}

private struct M3ScreenBackground: ViewModifier {
    @Environment(\.m3) private var m3

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(m3.surface.ignoresSafeArea())
    }
}

/// Position of a row inside a grouped section; drives the M3 "segmented"
/// corner radii (large outside, small between rows).
enum M3GroupPosition {
    case single, first, middle, last

    static func of(index: Int, count: Int) -> M3GroupPosition {
        if count <= 1 { return .single }
        if index == 0 { return .first }
        if index == count - 1 { return .last }
        return .middle
    }

    var radii: RectangleCornerRadii {
        let outer = M3Shape.groupOuter, inner = M3Shape.groupInner
        switch self {
        case .single: return .init(topLeading: outer, bottomLeading: outer, bottomTrailing: outer, topTrailing: outer)
        case .first: return .init(topLeading: outer, bottomLeading: inner, bottomTrailing: inner, topTrailing: outer)
        case .middle: return .init(topLeading: inner, bottomLeading: inner, bottomTrailing: inner, topTrailing: inner)
        case .last: return .init(topLeading: inner, bottomLeading: outer, bottomTrailing: outer, topTrailing: inner)
        }
    }

    var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(cornerRadii: radii, style: .continuous)
    }
}

// MARK: - Section header

struct M3SectionHeader: View {
    @Environment(\.m3) private var m3
    let title: String
    var subtitle: String?
    var accent: Bool = false
    var trailing: (() -> AnyView)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                if let subtitle {
                    Text(subtitle)
                        .font(.m3(.bodyMedium))
                        .foregroundStyle(m3.onSurfaceVariant)
                }
                Text(title)
                    .font(.m3(.headlineSmall))
                    .foregroundStyle(accent ? m3.primary : m3.onSurface)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if let trailing { trailing() }
        }
        .padding(.horizontal, M3Metrics.screenPadding)
    }
}
