//
//  PlayerParts.swift
//  Resona
//
//  Building blocks of the full player: artwork-driven background, playback
//  button group with expressive press/shape morphing, round toggles, the
//  stream info line and the bottom action row.
//

import AVKit
import SwiftUI

// MARK: - Background

/// Vibrant, slowly flowing mesh gradient from the shared CoverPalette (seed
/// hue + vivid cover tones — the same colour the mini player's glass is
/// tinted with). Control points drift on incommensurate sine waves
/// (17–23 s), colours cross-fade in 0.9 s on song change. Static with Reduce
/// Motion, when the setting is off or when the app is not active; the
/// player only exists while open, so nothing runs otherwise.
///
/// Brightness follows the user setting; if the brightest colour would drop
/// white text below WCAG AA (4.5:1), a uniform dark layer brings it back.
struct PlayerBackground: View {
    @Environment(\.coverPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SettingsStore.self) private var settings
    var dimmed: Bool = false

    @State private var from: [RGB] = []
    @State private var to: [RGB] = []
    @State private var changedAt = Date.distantPast

    private static let fadeDuration = 0.9
    /// Brightest pulse of a mesh blob (see `shade`).
    private static let pulse = 1.07

    var body: some View {
        let animate = settings.animatedPlayerBackground && !reduceMotion && scenePhase == .active
        ZStack {
            if animate {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    let date = context.date
                    mesh(colors: blended(at: date), time: date.timeIntervalSinceReferenceDate)
                }
            } else {
                mesh(colors: target, time: 0)
                    .animation(.easeInOut(duration: Self.fadeDuration), value: target)
            }

            // WCAG AA guard for white text (uniform, only when needed).
            Color.black.opacity(contrastDimming)
                .animation(.easeInOut(duration: Self.fadeDuration), value: contrastDimming)

            // Slightly darker behind title, times and controls (lower part).
            LinearGradient(colors: [.black.opacity(0.08), .clear, .black.opacity(0.3)], startPoint: .top, endPoint: .bottom)

            if dimmed {
                Color.black.opacity(0.35)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            to = target
            from = target
        }
        .onChange(of: target) { _, new in
            let now = Date()
            from = blended(at: now)
            to = new
            changedAt = now
        }
    }

    /// Palette with the user's brightness applied.
    private var target: [RGB] {
        let factor = settings.playerBackgroundBrightness
        return palette.colors.map { rgb in
            let hsv = rgb.hsv
            return RGB(h: hsv.h, s: hsv.s, v: min(0.95, hsv.v * factor))
        }
    }

    /// Black overlay needed so white text keeps ≥ 4.5:1 on the brightest
    /// colour: L(white)=1 → background luminance must stay ≤ 0.1833.
    private var contrastDimming: Double {
        let brightest = target.map { rgb -> Double in
            let hsv = rgb.hsv
            return RGB(h: hsv.h, s: hsv.s, v: min(1, hsv.v * Self.pulse)).relativeLuminance
        }.max() ?? 0
        let limit = 1.05 / 4.5 - 0.05
        guard brightest > limit else { return 0 }
        return min(0.6, 1 - limit / brightest)
    }

    /// Cross-fade between the previous and the new palette.
    private func blended(at date: Date) -> [RGB] {
        guard from.count == to.count, !to.isEmpty else { return to.isEmpty ? target : to }
        let raw = min(1, max(0, date.timeIntervalSince(changedAt) / Self.fadeDuration))
        let f = raw * raw * (3 - 2 * raw)
        guard f < 1 else { return to }
        return zip(from, to).map { $0.mix($1, f) }
    }

    private func mesh(colors palette: [RGB], time t: Double) -> some View {
        let c = palette.count == 4 ? palette : CoverPalette.fallback.colors
        func w(_ period: Double, _ phase: Double) -> Float {
            Float(sin(t * 2 * .pi / period + phase))
        }
        func shade(_ rgb: RGB, _ factor: Double, _ period: Double, _ phase: Double) -> Color {
            // Blobs breathe slightly in brightness as they move.
            let hsv = rgb.hsv
            let breathe = 1 + (Self.pulse - 1) * Double(w(period, phase))
            return RGB(h: hsv.h, s: hsv.s, v: min(0.95, hsv.v * factor * breathe)).color
        }
        let points: [SIMD2<Float>] = [
            [0, 0], [0.5 + 0.2 * w(19, 0), 0], [1, 0],
            [0, 0.45 + 0.2 * w(23, 1.1)], [0.5 + 0.22 * w(17, 2.3), 0.5 + 0.2 * w(21, 0.4)], [1, 0.5 + 0.2 * w(18, 3.0)],
            [0, 1], [0.5 + 0.2 * w(22, 4.2), 1], [1, 1]
        ]
        let meshColors: [Color] = [
            shade(c[1], 0.85, 20, 0), shade(c[0], 1, 17, 1), shade(c[2], 0.9, 23, 2),
            shade(c[2], 1, 19, 3), shade(c[0], 1, 21, 4), shade(c[1], 1, 18, 5),
            shade(c[3], 0.9, 22, 6), shade(c[0], 0.8, 16, 7), shade(c[3], 0.8, 24, 8)
        ]
        return MeshGradient(width: 3, height: 3, points: points, colors: meshColors, smoothsColors: true)
    }
}

// MARK: - Playback button group

/// Previous / play-pause / next inside a translucent container. The pressed
/// button widens while its neighbours compress; play-pause morphs between a
/// rounded square (playing) and a pill (paused).
struct PlaybackButtonGroup: View {
    @Environment(\.m3) private var m3
    @Environment(\.playerAccent) private var playerAccent
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
            .foregroundStyle(playerAccent.on.opacity(enabled ? 1 : 0.4))
            .frame(width: max(0, width), height: max(0, height))
            .background(playerAccent.container, in: RoundedRectangle(cornerRadius: pressed == slot ? 14 : 24, style: .continuous))
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
    @Environment(\.playerAccent) private var playerAccent
    let systemName: String
    let isOn: Bool
    var label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isOn ? playerAccent.on : .white.opacity(0.6))
                .frame(width: 44, height: 44)
                .background(isOn ? playerAccent.container : .white.opacity(0.1), in: Circle())
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
    @Environment(\.playerAccent) private var playerAccent

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
            .foregroundStyle(highlighted ? playerAccent.on : .white.opacity(0.92))
            .padding(.horizontal, title == nil ? 0 : 14)
            .frame(maxWidth: title == nil ? 48 : .infinity)
            .frame(width: title == nil ? 48 : nil, height: 48)
            .background(highlighted ? playerAccent.container : .white.opacity(0.12), in: Capsule())
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
            // Same type as the rest of the player (Poppins, small, dimmed).
            .font(.poppins(12))
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

/// Tonal accent for player controls. Comes from the SAME dynamic scheme as
/// the rest of the app (dark primaryContainer / onPrimaryContainer of the
/// current cover's seed), injected by `M3ThemeProvider` — so previous/next,
/// toggles and pills can never fall back to a stale or unrelated colour.
struct PlayerAccent: Equatable {
    let container: Color
    let on: Color
}

extension M3Scheme {
    var playerAccent: PlayerAccent {
        PlayerAccent(container: primaryContainer, on: onPrimaryContainer)
    }
}

// MARK: - AirPlay

/// AirPlay / output picker (AVRoutePickerView) in the round player style;
/// the glyph lights up in the cover accent while a route is active.
struct PlayerAirPlayButton: View {
    @Environment(\.playerAccent) private var playerAccent

    var body: some View {
        RoutePicker(activeTint: UIColor(playerAccent.on))
            .frame(width: 48, height: 48)
            .background(.white.opacity(0.1), in: Circle())
            .accessibilityLabel(Text("AirPlay"))
    }

    private struct RoutePicker: UIViewRepresentable {
        let activeTint: UIColor

        func makeUIView(context: Context) -> AVRoutePickerView {
            let view = AVRoutePickerView()
            view.tintColor = UIColor.white.withAlphaComponent(0.85)
            view.activeTintColor = activeTint
            view.prioritizesVideoDevices = false
            view.backgroundColor = .clear
            return view
        }

        func updateUIView(_ view: AVRoutePickerView, context: Context) {
            view.activeTintColor = activeTint
        }
    }
}
