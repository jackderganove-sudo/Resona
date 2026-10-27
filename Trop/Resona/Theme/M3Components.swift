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

/// List rows: instant tonal highlight + tiny squish + light haptic on touch
/// down (the action runs on release; nothing waits for it).
struct M3RowPressStyle: ButtonStyle {
    @Environment(\.m3) private var m3

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: M3Shape.medium, style: .continuous)
                    .fill(m3.onSurface.opacity(configuration.isPressed ? 0.08 : 0))
                    .padding(.horizontal, 6)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(configuration.isPressed ? nil : M3Motion.fastSpatial, value: configuration.isPressed)
            .sensoryFeedback(.selection, trigger: configuration.isPressed) { _, pressed in pressed }
    }
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
            .background(isSelected ? m3.primary : m3.surfaceContainerHighest, in: Capsule())
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

// MARK: - Buttons (replace system .bordered / .borderedProminent)

enum M3ButtonVariant {
    case filled, tonal, outlined, text
}

/// Material 3 common button: capsule, 40 pt high, press morph + squish.
struct M3ButtonStyle: ButtonStyle {
    var variant: M3ButtonVariant = .filled
    @Environment(\.m3) private var m3
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let radius: CGFloat = configuration.isPressed ? 10 : 20
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        configuration.label
            .font(.m3(.labelLarge, weight: .medium))
            .foregroundStyle(foreground.opacity(isEnabled ? 1 : 0.38))
            .padding(.horizontal, variant == .text ? 12 : 24)
            .frame(minHeight: 40)
            .background(background.opacity(isEnabled ? 1 : 0.12), in: shape)
            .overlay {
                if variant == .outlined {
                    shape.strokeBorder(m3.outline, lineWidth: 1)
                }
            }
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(M3Motion.fastSpatial, value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: configuration.isPressed) { _, pressed in pressed }
    }

    private var foreground: Color {
        switch variant {
        case .filled: m3.onPrimary
        case .tonal: m3.onSecondaryContainer
        case .outlined, .text: m3.primary
        }
    }

    private var background: Color {
        switch variant {
        case .filled: m3.primary
        case .tonal: m3.secondaryContainer
        case .outlined, .text: .clear
        }
    }
}

extension ButtonStyle where Self == M3ButtonStyle {
    static var m3Filled: M3ButtonStyle { M3ButtonStyle(variant: .filled) }
    static var m3Tonal: M3ButtonStyle { M3ButtonStyle(variant: .tonal) }
    static var m3Outlined: M3ButtonStyle { M3ButtonStyle(variant: .outlined) }
    static var m3Text: M3ButtonStyle { M3ButtonStyle(variant: .text) }
}

// MARK: - Back button (replaces the system navigation back button)

private struct M3BackButtonModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.m3) private var m3

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(m3.onSurface)
                            .frame(width: 40, height: 40)
                            .background(m3.surfaceContainerHigh.opacity(0.92), in: Circle())
                    }
                    .buttonStyle(.expressive(scale: 0.88))
                    .accessibilityLabel(Text("Back"))
                }
            }
    }
}

extension View {
    /// Round Material back button instead of the system chevron. The
    /// edge-swipe back gesture is provided by ContentView.
    func m3BackButton() -> some View { modifier(M3BackButtonModifier()) }
}

/// Pressed feedback for rows that must stay tap gestures (inside Lists
/// with swipe actions / drag-to-reorder, or containing other buttons):
/// highlights on touch-down without delaying scrolling.
struct M3TapHighlight: ViewModifier {
    @Environment(\.m3) private var m3
    @GestureState private var pressed = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: M3Shape.medium, style: .continuous)
                    .fill(m3.onSurface.opacity(pressed ? 0.08 : 0))
            }
            .scaleEffect(pressed ? 0.985 : 1)
            .animation(pressed ? nil : M3Motion.fastSpatial, value: pressed)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5, maximumDistance: 8)
                    .updating($pressed) { value, state, _ in state = value }
            )
            .sensoryFeedback(.selection, trigger: pressed) { _, isPressed in isPressed }
    }
}

// MARK: - Switch

/// Material 3 switch. On: track in the accent colour, larger handle with a
/// check mark. Off: dark track with an outline and a small outlined handle.
/// The handle grows while pressed. Use via `.toggleStyle(.m3)`.
struct M3SwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        M3SwitchBody(configuration: configuration)
    }
}

private struct M3SwitchBody: View {
    @Environment(\.m3) private var m3
    @Environment(\.isEnabled) private var isEnabled
    let configuration: ToggleStyleConfiguration
    @GestureState private var pressed = false

    var body: some View {
        let on = configuration.isOn
        HStack(spacing: 16) {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule()
                    .fill(on ? m3.primary : m3.surfaceContainerHighest)
                    .overlay(Capsule().strokeBorder(on ? .clear : m3.outline, lineWidth: 2))
                Circle()
                    .fill(on ? m3.onPrimary : m3.outline)
                    .frame(width: pressed ? 28 : (on ? 24 : 16), height: pressed ? 28 : (on ? 24 : 16))
                    .overlay {
                        if on {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(m3.primary)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, on ? 4 : 8)
            }
            .frame(width: 52, height: 32)
            .opacity(isEnabled ? 1 : 0.38)
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($pressed) { _, state, _ in state = true }
                    .onEnded { _ in
                        withAnimation(M3Motion.fastSpatial) { configuration.isOn.toggle() }
                    }
            )
            .animation(M3Motion.fastSpatial, value: on)
            .animation(M3Motion.fastSpatial, value: pressed)
            .sensoryFeedback(.selection, trigger: on)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(Text(on ? "On" : "Off"))
        .accessibilityAction { configuration.isOn.toggle() }
    }
}

extension ToggleStyle where Self == M3SwitchToggleStyle {
    static var m3: M3SwitchToggleStyle { M3SwitchToggleStyle() }
}
