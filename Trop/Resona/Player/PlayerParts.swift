//
//  PlayerParts.swift
//  Resona
//
//  Building blocks of the full player: artwork-driven background, playback
//  button group with expressive press/shape morphing, round toggles, the
//  stream info line and the bottom action row.
//

import SwiftUI

// MARK: - Background

/// Soft gradient from the artwork colours with a heavily blurred copy of the
/// cover glowing through (reference: player background).
struct PlayerBackground: View {
    @Environment(\.artworkColors) private var colors
    var image: UIImage?
    var dimmed: Bool = false

    var body: some View {
        let tuned = colors.gradient.map { ArtworkColorExtractor.comfortable($0, minV: 0.2, maxV: 0.62, minS: colors.isGreyscale ? 0 : 0.35) }
        let first = tuned.first ?? RGB(hex: 0x2C5D62)
        let second = tuned.count > 1 ? tuned[1] : first
        let third = tuned.count > 2 ? tuned[2] : second

        ZStack {
            LinearGradient(
                stops: [
                    .init(color: ArtworkColorExtractor.darken(first, 0.72).color, location: 0),
                    .init(color: first.color, location: 0.42),
                    .init(color: second.mix(third, 0.5).color, location: 0.78),
                    .init(color: ArtworkColorExtractor.darken(second, 0.8).color, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            if let image {
                // Pre-blurred once (Core Image, cached) instead of a live
                // 90 pt blur that was re-rendered every animation frame.
                GeometryReader { geo in
                    BlurredArtwork(image: image, radius: 10)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .opacity(0.5)
                        .clipped()
                }
                .transition(.opacity)
                .id(ObjectIdentifier(image))
            }

            // Top glow + bottom vignette keep white text readable.
            RadialGradient(
                colors: [first.color.opacity(0.55), .clear],
                center: .init(x: 0.5, y: 0.25),
                startRadius: 10,
                endRadius: 420
            )
            .blendMode(.screen)
            LinearGradient(colors: [.black.opacity(0.18), .clear, .black.opacity(0.28)], startPoint: .top, endPoint: .bottom)

            if dimmed {
                Color.black.opacity(0.35)
            }
        }
        .ignoresSafeArea()
        .animation(M3Motion.colorChange, value: colors)
    }
}

// MARK: - Playback button group

/// Previous / play-pause / next inside a translucent container. The pressed
/// button widens while its neighbours compress; play-pause morphs between a
/// rounded square (playing) and a pill (paused).
struct PlaybackButtonGroup: View {
    @Environment(\.m3) private var m3
    @Environment(\.artworkColors) private var artwork
    let isPlaying: Bool
    let hasPrevious: Bool
    let hasNext: Bool
    let onPrevious: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void

    private enum Slot { case previous, play, next }
    @State private var pressed: Slot?

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 8
            let total = geo.size.width - spacing * 2
            let weights = weights()
            let sum = weights.reduce(0, +)
            HStack(spacing: spacing) {
                sideButton(.previous, icon: "backward.fill", enabled: hasPrevious, width: total * weights[0] / sum, height: geo.size.height - 32, action: onPrevious)
                playButton(width: total * weights[1] / sum, height: geo.size.height - 8)
                sideButton(.next, icon: "forward.fill", enabled: hasNext, width: total * weights[2] / sum, height: geo.size.height - 32, action: onNext)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .padding(6)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .animation(M3Motion.fastSpatial, value: pressed)
    }

    private func weights() -> [CGFloat] {
        let base: [CGFloat] = [1.45, 1, 1.45]
        guard let pressed else { return base }
        switch pressed {
        case .previous: return [1.75, 0.9, 1.2]
        case .play: return [1.3, 1.25, 1.3]
        case .next: return [1.2, 0.9, 1.75]
        }
    }

    private func sideButton(_ slot: Slot, icon: String, enabled: Bool, width: CGFloat, height: CGFloat, action: @escaping () -> Void) -> some View {
        Image(systemName: icon)
            .font(.system(size: 26, weight: .bold))
            .foregroundStyle(artwork.accent.on.opacity(enabled ? 1 : 0.4))
            .frame(width: max(0, width), height: max(0, height))
            .background(artwork.accent.container, in: RoundedRectangle(cornerRadius: pressed == slot ? 14 : 24, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .gesture(pressGesture(slot, enabled: enabled, action: action))
            .accessibilityElement()
            .accessibilityLabel(Text(slot == .previous ? "Previous" : "Next"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if enabled { action() } }
    }

    private func playButton(width: CGFloat, height: CGFloat) -> some View {
        let radius: CGFloat = pressed == .play ? 18 : (isPlaying ? 28 : height / 2)
        return Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: 34, weight: .bold))
            .contentTransition(.symbolEffect(.replace.downUp))
            .foregroundStyle(.black)
            .frame(width: max(0, width), height: max(0, height))
            .background(.white, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .animation(M3Motion.defaultSpatial, value: isPlaying)
            .gesture(pressGesture(.play, enabled: true, action: onPlayPause))
            .sensoryFeedback(.impact(weight: .medium), trigger: isPlaying)
            .accessibilityElement()
            .accessibilityLabel(Text(isPlaying ? "Pause" : "Play"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onPlayPause() }
    }

    private func pressGesture(_ slot: Slot, enabled: Bool, action: @escaping () -> Void) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if pressed != slot, enabled { pressed = slot }
            }
            .onEnded { value in
                defer { pressed = nil }
                guard enabled, abs(value.translation.width) < 40, abs(value.translation.height) < 40 else { return }
                action()
            }
    }
}

// MARK: - Round toggle (shuffle / repeat)

struct PlayerRoundToggle: View {
    @Environment(\.m3) private var m3
    @Environment(\.artworkColors) private var artwork
    let systemName: String
    let isOn: Bool
    var label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isOn ? artwork.accent.on : .white.opacity(0.6))
                .frame(width: 44, height: 44)
                .background(isOn ? artwork.accent.container : .white.opacity(0.1), in: Circle())
        }
        .buttonStyle(.expressive(scale: 0.86))
        .animation(M3Motion.defaultEffects, value: isOn)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Title row action

struct PlayerActionButton: View {
    let systemName: String
    var shape: AnyShape = AnyShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    var tint: Color = .white
    var fill: Color = .white.opacity(0.15)
    var label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 44, height: 44)
                .background(fill, in: shape)
                .contentShape(shape)
        }
        .buttonStyle(.expressive(scale: 0.86))
        .accessibilityLabel(Text(label))
    }
}

// MARK: - Bottom pill (queue / sleep / lyrics)

struct PlayerBottomPill: View {
    let systemName: String
    var title: LocalizedStringKey?
    var highlighted = false
    let action: () -> Void

    @Environment(\.m3) private var m3
    @Environment(\.artworkColors) private var artwork

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemName)
                    .font(.system(size: 19, weight: .medium))
                if let title {
                    // Never truncate the label ("Warteschlange"): shrink a
                    // little before it would be cut.
                    Text(title)
                        .font(.poppins(16, weight: .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .layoutPriority(1)
                }
            }
            .foregroundStyle(highlighted ? artwork.accent.on : .white.opacity(0.92))
            .padding(.horizontal, title == nil ? 0 : 14)
            .frame(maxWidth: title == nil ? 48 : .infinity)
            .frame(width: title == nil ? 48 : nil, height: 48)
            .background(highlighted ? artwork.accent.container : .white.opacity(0.12), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.expressive)
    }
}

// MARK: - Stream info ("WEBM • 134 kbps • 3.5 MB")

struct StreamInfoLine: View {
    let videoId: String?
    @State private var text: String = ""

    var body: some View {
        Text(text.isEmpty ? " " : text)
            .font(.system(size: 13, weight: .regular, design: .monospaced))
            .foregroundStyle(.white.opacity(0.55))
            .lineLimit(1)
            .task(id: videoId) { await load() }
    }

    private func load() async {
        text = ""
        guard let videoId else { return }
        // Give the resolver a moment so a freshly started song has its stream.
        for attempt in 0..<6 {
            let stream = await StreamCache.shared.get(videoId: videoId)
            let format = try? await DatabaseService.shared.fetchOne(FormatEntity.self, key: videoId)
            var parts: [String] = []
            if let mime = stream?.mimeType ?? format?.mimeType {
                parts.append(Self.container(from: mime))
            }
            let bitrate = (stream?.bitrate).flatMap { $0 > 0 ? $0 : nil } ?? format?.bitrate ?? 0
            if bitrate > 0 { parts.append("\(bitrate / 1000) kbps") }
            if let length = format?.contentLength, length > 0 {
                parts.append(String(format: "%.1f MB", Double(length) / 1_048_576))
            }
            if !parts.isEmpty {
                text = parts.joined(separator: " • ")
                return
            }
            if attempt < 5 { try? await Task.sleep(nanoseconds: 1_500_000_000) }
            if Task.isCancelled { return }
        }
    }

    /// "audio/webm; codecs=\"opus\"" → "WEBM"
    static func container(from mime: String) -> String {
        let main = mime.split(separator: ";").first.map(String.init) ?? mime
        let sub = main.split(separator: "/").last.map(String.init) ?? main
        return sub.uppercased()
    }
}

// MARK: - Player accent

/// Tonal accent for player controls taken from the artwork's dominant
/// colour — the same source as the player background, so buttons always
/// match the cover (the app-wide scheme seed can pick a different,
/// more chromatic hue).
struct PlayerAccent {
    let container: Color
    let on: Color
}

extension ArtworkColors {
    var accent: PlayerAccent {
        let base = gradient.first ?? seed
        let hsv = base.hsv
        if isGreyscale || hsv.s < 0.12 {
            return PlayerAccent(container: RGB(h: 0, s: 0, v: 0.3).color, on: .white)
        }
        return PlayerAccent(
            container: RGB(h: hsv.h, s: min(0.85, max(0.45, hsv.s)), v: 0.36).color,
            on: RGB(h: hsv.h, s: 0.16, v: 0.98).color
        )
    }
}
