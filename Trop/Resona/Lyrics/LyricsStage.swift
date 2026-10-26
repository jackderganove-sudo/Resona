//
//  LyricsStage.swift
//  Resona
//
//  Word-synced karaoke lyrics, modelled on reference/lyrics-animation.mp4:
//
//  • All lines share one size (no scaling). The active line is white; words
//    light up one after another with a soft leading edge and a gentle glow,
//    words not yet sung stay at ~38 % opacity.
//  • When the active line changes, every line glides to its new position
//    with a spring whose start is staggered downwards (lines further below
//    follow slightly later), so the list "ripples" like the reference.
//  • Inactive lines dim and blur with their distance (above and below).
//  • Manual drag scrolls freely (no blur while browsing), flings with
//    momentum and returns to the active line after a pause.
//
//  The active line is redrawn every display frame (TimelineView .animation →
//  120 Hz on ProMotion) through a TextRenderer; all other lines are static.
//

import SwiftUI

struct LyricsStage<Accessory: View>: View {
    let lines: [LyricLine]
    let activeIndex: Int
    let romanized: (Int) -> String?
    let fontSize: Double
    let alignment: LyricsAlignment
    let onSeek: (LyricLine) -> Void
    /// Extra view under a line (instrumental gap indicator).
    @ViewBuilder let accessory: (Int) -> Accessory

    @State private var lineTops: [Int: CGFloat] = [:]
    @State private var manualOffset: CGFloat = 0
    @State private var dragStart: CGFloat?
    @State private var isManual = false
    @State private var resumeTask: Task<Void, Never>?

    /// Active line sits at this fraction of the stage height (reference ≈ 22 %).
    private let anchorFraction: CGFloat = 0.22

    var body: some View {
        GeometryReader { geo in
            let anchor = geo.size.height * anchorFraction
            let target = (lineTops[activeIndex] ?? 0) - anchor

            VStack(alignment: horizontalAlignment, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                    row(index: index, line: line)
                        // Natural layout position (measured before offsets).
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.frame(in: .named(Self.space)).minY
                        } action: { top in
                            lineTops[index] = top
                        }
                        // Staggered glide: lines at/below the new active line
                        // start a little later the further down they are.
                        .offset(y: -target)
                        .animation(M3Motion.lyricsScroll.delay(delay(for: index)), value: activeIndex)
                        .offset(y: manualOffset)
                }
                Color.clear.frame(height: geo.size.height)
            }
            .frame(width: geo.size.width, alignment: Alignment(horizontal: horizontalAlignment, vertical: .top))
            .coordinateSpace(.named(Self.space))
            .contentShape(Rectangle())
            .gesture(dragGesture(height: geo.size.height))
            .overlay(alignment: .bottom) {
                if isManual {
                    Button {
                        resume()
                    } label: {
                        Label("Re-sync", systemImage: "arrow.triangle.2.circlepath")
                            .font(.poppins(14, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .frame(height: 40)
                            .background(.white.opacity(0.18), in: Capsule())
                    }
                    .buttonStyle(.expressive)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .clipped()
        .mask(edgeFade)
        .animation(M3Motion.fastSpatial, value: isManual)
    }

    private static var space: String { "lyricsStage" }

    private var horizontalAlignment: HorizontalAlignment {
        switch alignment {
        case .left: .leading
        case .center: .center
        case .right: .trailing
        }
    }

    private func delay(for index: Int) -> Double {
        let rel = index - activeIndex
        guard rel >= -1 else { return 0 }
        return min(Double(rel + 1), 8) * 0.045
    }

    // MARK: Row

    private func row(index: Int, line: LyricLine) -> some View {
        let rel = index - activeIndex
        let isActive = rel == 0
        let distance = abs(rel)

        return VStack(alignment: horizontalAlignment, spacing: 4) {
            Group {
                if isActive {
                    ActiveKaraokeLine(line: line, nextStart: nextStart(after: index), fontSize: fontSize, alignment: alignment)
                } else {
                    LyricsLineText(text: line.text, fontSize: fontSize, alignment: alignment)
                        .foregroundStyle(.white)
                }
            }
            if let roman = romanized(index), !roman.isEmpty {
                Text(roman)
                    .font(.system(size: max(12, fontSize * 0.55), weight: .semibold))
                    .foregroundStyle(.white.opacity(isActive ? 0.8 : 0.6))
                    .multilineTextAlignment(alignment.multilineTextAlignment)
            }
            accessory(index)
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: horizontalAlignment, vertical: .center))
        .padding(.horizontal, 28)
        .padding(.vertical, fontSize * 0.36)
        .opacity(isActive ? 1 : opacity(distance: distance))
        .blur(radius: isActive || isManual || distance > 10 ? 0 : blur(rel: rel))
        .animation(.easeOut(duration: isActive ? 0.18 : 0.42), value: isActive)
        .animation(.easeOut(duration: 0.25), value: isManual)
        .contentShape(Rectangle())
        .onTapGesture { onSeek(line); resume() }
        .accessibilityAddTraits(.isButton)
    }

    /// Reference: just-finished and upcoming lines ≈ 35 %, fading further out.
    private func opacity(distance: Int) -> Double {
        if isManual { return 0.6 }
        switch distance {
        case 1: return 0.36
        case 2: return 0.3
        case 3: return 0.24
        default: return 0.18
        }
    }

    /// Blur grows with distance; lines above blur a little less than below.
    private func blur(rel: Int) -> CGFloat {
        switch rel {
        case -1: return 1
        case -2: return 2.5
        case ..<(-2): return 3.5
        case 1: return 1.6
        case 2: return 3
        case 3: return 4.5
        default: return 6
        }
    }

    private func nextStart(after index: Int) -> TimeInterval? {
        lines[(index + 1)...].lazy.compactMap(\.startTime).first
    }

    // MARK: Manual scrolling

    private func dragGesture(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                resumeTask?.cancel()
                if dragStart == nil {
                    dragStart = manualOffset
                    isManual = true
                }
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                    manualOffset = (dragStart ?? 0) + value.translation.height
                }
            }
            .onEnded { value in
                let base = dragStart ?? 0
                dragStart = nil
                let maxUp = (lineTops[activeIndex] ?? 0)
                let maxDown = max(0, (lineTops[lines.count - 1] ?? 0) - (lineTops[activeIndex] ?? 0))
                let projected = base + value.predictedEndTranslation.height
                let clamped = min(max(projected, -maxDown), maxUp)
                withAnimation(.interpolatingSpring(mass: 1, stiffness: 140, damping: 24, initialVelocity: 0)) {
                    manualOffset = clamped
                }
                scheduleResume()
            }
    }

    private func scheduleResume() {
        resumeTask?.cancel()
        resumeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            resume()
        }
    }

    private func resume() {
        resumeTask?.cancel()
        guard isManual || manualOffset != 0 else { return }
        withAnimation(M3Motion.lyricsScroll) {
            manualOffset = 0
            isManual = false
        }
    }

    private var edgeFade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.06),
                .init(color: .black, location: 0.86),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Line text

/// Shared typography for every lyric line (SF Pro Display Bold, tight).
struct LyricsLineText: View {
    let text: String
    let fontSize: Double
    let alignment: LyricsAlignment

    var body: some View {
        Text(text.isEmpty ? "\u{266A}" : text)
            .font(.system(size: fontSize, weight: .bold))
            .tracking(-0.4)
            .lineSpacing(fontSize * 0.06)
            .multilineTextAlignment(alignment.multilineTextAlignment)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Active line (word by word)

private struct WordIndexAttribute: TextAttribute {
    let index: Int
}

private struct ActiveKaraokeLine: View {
    let line: LyricLine
    let nextStart: TimeInterval?
    let fontSize: Double
    let alignment: LyricsAlignment

    private let np = NowPlaying.shared
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        let words = KaraokeTiming.words(for: line, nextStart: nextStart)
        let text = words.enumerated().reduce(Text(verbatim: "")) { partial, item in
            partial + Text(verbatim: item.element.text).customAttribute(WordIndexAttribute(index: item.offset))
        }
        TimelineView(.animation(paused: !np.isPlaying)) { _ in
            text
                .font(.system(size: fontSize, weight: .bold))
                .tracking(-0.4)
                .lineSpacing(fontSize * 0.06)
                .multilineTextAlignment(alignment.multilineTextAlignment)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.white)
                .textRenderer(KaraokeRenderer(
                    time: PlaybackClock.shared.now() + settings.lyricsOffsetSeconds,
                    words: words
                ))
        }
    }
}

/// Draws each word dim, then the sung part bright with a feathered leading
/// edge and a glow that builds while the word is sung and settles after.
private struct KaraokeRenderer: TextRenderer {
    var time: TimeInterval
    var words: [LyricWord]
    var dimOpacity: Double = 0.38

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        for line in layout {
            for run in line {
                guard let index = run[WordIndexAttribute.self]?.index, words.indices.contains(index) else {
                    ctx.draw(run)
                    continue
                }
                let word = words[index]
                let duration = max(0.05, word.end - word.start)
                let p = min(max((time - word.start) / duration, 0), 1)
                let rect = run.typographicBounds.rect

                if p >= 1 {
                    // Sung: bright, glow fading out over 0.6 s.
                    let since = time - word.end
                    let glow = max(0, 1 - since / 0.6)
                    var lit = ctx
                    if glow > 0.01 {
                        lit.addFilter(.shadow(color: .white.opacity(0.45 * glow), radius: 9 * glow))
                    }
                    lit.draw(run)
                    continue
                }

                var base = ctx
                base.opacity = dimOpacity
                base.draw(run)
                guard p > 0 else { continue }

                // Leading edge travels from left to right with a soft feather.
                let feather = max(10, rect.width * 0.35)
                let edge = rect.minX - feather + (rect.width + feather) * p
                var lit = ctx
                lit.clipToLayer { mask in
                    let area = CGRect(x: rect.minX - 2, y: rect.minY - 16, width: rect.width + 4, height: rect.height + 32)
                    mask.fill(
                        Path(area),
                        with: .linearGradient(
                            Gradient(stops: [
                                .init(color: .white, location: 0),
                                .init(color: .white, location: 0.001),
                                .init(color: .clear, location: 1)
                            ]),
                            startPoint: CGPoint(x: edge, y: rect.midY),
                            endPoint: CGPoint(x: edge + feather, y: rect.midY)
                        )
                    )
                }
                lit.addFilter(.shadow(color: .white.opacity(0.45 * min(1, p * 2)), radius: 9))
                lit.draw(run)
            }
        }
    }
}

// MARK: - Word timing

enum KaraokeTiming {
    private static let wordRegex = try! NSRegularExpression(pattern: #"\S+\s*"#)

    /// Real word timings when available; otherwise words are spread over the
    /// line's singing time, weighted by length (vowel-heavy words take longer).
    static func words(for line: LyricLine, nextStart: TimeInterval?) -> [LyricWord] {
        if let words = line.words, !words.isEmpty { return words }
        let text = line.text.isEmpty ? "\u{266A}" : line.text
        let ns = text as NSString
        let tokens = wordRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range) }
        guard let start = line.startTime, !tokens.isEmpty else {
            return [LyricWord(text: text, start: line.startTime ?? 0, end: (line.startTime ?? 0) + 1)]
        }
        let available = (nextStart ?? start + 6) - start
        let letters = tokens.reduce(0) { $0 + $1.trimmingCharacters(in: .whitespaces).count }
        // Natural singing pace (~13 chars/s), never longer than ~90 % of the
        // gap so the line finishes before the next one starts.
        let singing = min(max(0.4, available * 0.9), max(0.6, Double(letters) / 13))
        var t = start
        return tokens.map { token in
            let weight = Double(max(1, token.trimmingCharacters(in: .whitespaces).count)) / Double(max(1, letters))
            let d = singing * weight
            defer { t += d }
            return LyricWord(text: token, start: t, end: t + d)
        }
    }
}
