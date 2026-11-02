//
//  PlayerStyles.swift
//  Resona
//
//  Pieces of the round 10 player styles (after ArchiveTune 15):
//  - Editorial: flat cover colour, the cover as a die-cut shape that
//    morphs from a squircle (paused) to a scalloped disc (playing), a large
//    italic serif headline and a bento control cluster.
//  - Immersive: the canvas (or the slowly turning cover) fills the screen,
//    controls sit on a scrim at the bottom.
//  Plus the artwork placeholder and the codec line used by every layout.
//

import SwiftUI

// MARK: - Die-cut shape

/// Squircle (morph 0) ↔ scalloped disc with `lobes` bumps (morph 1).
struct DieCutShape: Shape {
    var morph: Double
    var lobes: Int = 12

    var animatableData: Double {
        get { morph }
        set { morph = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let steps = 240
        var path = Path()
        for step in 0...steps {
            let theta = Double(step) / Double(steps) * 2 * .pi
            let r = radius * Self.radiusFactor(theta: theta, morph: morph, lobes: lobes)
            let point = CGPoint(x: center.x + r * cos(theta), y: center.y + r * sin(theta))
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    /// Radius relative to half the side: squircle |x|⁴+|y|⁴=1 blended with
    /// a scalloped circle 0.94 + 0.06·cos(n·θ). Always within (0, 1].
    static func radiusFactor(theta: Double, morph: Double, lobes: Int) -> Double {
        let c = abs(cos(theta)), s = abs(sin(theta))
        let squircle = 1 / pow(pow(c, 4) + pow(s, 4), 0.25)
        let scallop = 0.94 + 0.06 * cos(Double(lobes) * theta)
        // The squircle reaches √2^½ in the corners; scale it to fit.
        let fitted = squircle / pow(2, 0.25)
        let t = min(max(morph, 0), 1)
        return fitted * (1 - t) + scallop * t
    }
}

// MARK: - Rotating cover

/// Turns its content slowly while playing (one turn in `period` seconds);
/// stops where it is when paused. Respects Reduce Motion.
struct RotatingWhilePlaying: ViewModifier {
    let isPlaying: Bool
    var enabled: Bool = true
    var period: Double = 28

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var baseAngle: Double = 0
    @State private var startedAt: Date?

    func body(content: Content) -> some View {
        let active = enabled && isPlaying && !reduceMotion
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !active)) { context in
            content.rotationEffect(.degrees(angle(at: context.date, active: active)))
        }
        .onChange(of: active, initial: true) { _, running in
            if running {
                startedAt = Date()
            } else if let startedAt {
                baseAngle = angle(at: Date(), from: startedAt)
                self.startedAt = nil
            }
        }
    }

    private func angle(at date: Date, active: Bool) -> Double {
        guard active, let startedAt else { return baseAngle }
        return angle(at: date, from: startedAt)
    }

    private func angle(at date: Date, from start: Date) -> Double {
        (baseAngle + date.timeIntervalSince(start) / period * 360).truncatingRemainder(dividingBy: 360)
    }
}

extension View {
    func rotatingWhilePlaying(_ isPlaying: Bool, enabled: Bool = true, period: Double = 28) -> some View {
        modifier(RotatingWhilePlaying(isPlaying: isPlaying, enabled: enabled, period: period))
    }
}

// MARK: - Artwork placeholder

/// No cover (yet): a tonal gradient from the theme with the title's first
/// letter instead of a grey box.
struct ArtworkPlaceholder: View {
    var title: String = ""
    @Environment(\.m3) private var m3

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                LinearGradient(colors: [m3.primaryContainer, m3.tertiaryContainer],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .fill(m3.onPrimaryContainer.opacity(0.08))
                    .frame(width: side * 0.9)
                    .offset(x: side * 0.35, y: -side * 0.3)
                if let initial = Self.initial(of: title) {
                    Text(initial)
                        .font(.system(size: side * 0.42, weight: .bold, design: .serif))
                        .foregroundStyle(m3.onPrimaryContainer.opacity(0.85))
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: side * 0.3, weight: .medium))
                        .foregroundStyle(m3.onPrimaryContainer.opacity(0.7))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityHidden(true)
    }

    /// First letter or digit of the title, uppercased.
    static func initial(of title: String) -> String? {
        title.first(where: { $0.isLetter || $0.isNumber }).map { String($0).uppercased() }
    }
}

// MARK: - Editorial controls

struct EditorialCircleButton<Label: View>: View {
    let size: CGFloat
    let accent: Color
    let field: Color
    var filled = false
    let accessibility: LocalizedStringKey
    let action: () -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .foregroundStyle(filled ? field : accent)
                .frame(width: size, height: size)
                .background {
                    if filled {
                        Circle().fill(accent)
                    } else {
                        Circle().strokeBorder(accent.opacity(0.55), lineWidth: 2)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.expressive(scale: 0.88))
        .accessibilityLabel(Text(accessibility))
    }
}

/// Headline size by title length, as in ArchiveTune's editorial player.
enum EditorialType {
    static func headlineSize(for title: String, compact: Bool) -> CGFloat {
        let base: CGFloat = title.count <= 12 ? 56 : (title.count <= 24 ? 44 : 34)
        return compact ? base * 0.8 : base
    }
}

// MARK: - Blurred cover background

/// Player background style "Blurred cover" and the Immersive backdrop
/// without a canvas: the cover, heavily blurred and dimmed for white text.
struct BlurredCoverBackground: View {
    let image: UIImage?
    var dimmed: Bool = false

    var body: some View {
        ZStack {
            Color.black
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 70, opaque: true)
                    .scaleEffect(1.25)
                    .opacity(0.9)
                    .transition(.opacity)
                    .id(ObjectIdentifier(image))
            }
            Color.black.opacity(dimmed ? 0.6 : 0.38)
        }
        .animation(M3Motion.colorChange, value: image.map { ObjectIdentifier($0) })
        .animation(M3Motion.defaultEffects, value: dimmed)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
