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
    /// Where the list is scrolled to (top of the active row − anchor).
    /// Every change animates with the staggered spring, so the list never
    /// jumps — not on line changes, not when row positions shift.
    @State private var scrollTarget: CGFloat = 0
    @State private var stageHeight: CGFloat = 0
    @State private var hasPositioned = false
    @State private var manualOffset: CGFloat = 0
    @State private var dragStart: CGFloat?
    @State private var isManual = false
    @State private var resumeTask: Task<Void, Never>?

    /// Active line sits at this fraction of the stage height (reference ≈ 22 %).
    private let anchorFraction: CGFloat = 0.22

    var body: some View {
        GeometryReader { geo in
            VStack(alignment: horizontalAlignment, spacing: 0) {
                if let intro = introGap {
                    InterludeDots(gap: intro, alignment: alignment)
                        .padding(.horizontal, 28)
                        .padding(.vertical, fontSize * 0.36)
                        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: horizontalAlignment, vertical: .center))
                        .modifier(StageRow(index: -1, activeIndex: activeIndex, scrollTarget: scrollTarget, manualOffset: manualOffset, lineTops: $lineTops))
                }
                ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                    row(index: index, line: line)
                        .modifier(StageRow(index: index, activeIndex: activeIndex, scrollTarget: scrollTarget, manualOffset: manualOffset, lineTops: $lineTops))
                }
                Color.clear.frame(height: geo.size.height)
            }
            .onAppear { stageHeight = geo.size.height }
            .onChange(of: geo.size.height) { _, h in stageHeight = h }
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
        .onChange(of: activeIndex) { _, _ in updateScrollTarget() }
        .onChange(of: lineTops) { _, _ in updateScrollTarget() }
        .onChange(of: stageHeight) { _, _ in updateScrollTarget() }
    }

    /// Recomputes the scroll target; the very first placement is instant.
    private func updateScrollTarget() {
        let key = lineTops[activeIndex] != nil ? activeIndex : (introGap != nil ? -1 : 0)
        guard let top = lineTops[key], stageHeight > 0 else { return }
        let target = top - stageHeight * anchorFraction
        guard abs(target - scrollTarget) > 0.5 else { return }
        if hasPositioned {
            scrollTarget = target          // animated per row (StageRow)
        } else {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { scrollTarget = target }
            hasPositioned = true
        }
    }

    // MARK: Interludes

    /// Intro before the first line (≥ 3 s of music without words).
    private var introGap: InterludeGap? {
        guard let first = lines.lazy.compactMap(\.startTime).first, first >= 3 else { return nil }
        return InterludeGap(start: 0, end: first)
    }

    /// Pause after a line: from its estimated end to the next line, ≥ 3 s.
    private func gap(after index: Int) -> InterludeGap? {
        guard let next = nextStart(after: index) else { return nil }
        let words = KaraokeTiming.words(for: lines[index], nextStart: next)
        guard let end = words.last?.end, next - end >= 3 else { return nil }
        return InterludeGap(start: end, end: next)
    }

    private static var space: String { "lyricsStage" }

    private var horizontalAlignment: HorizontalAlignment {
        switch alignment {
        case .left: .leading
        case .center: .center
        case .right: .trailing
        }
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
            if let pause = gap(after: index) {
                // Space is always reserved so rows never shift when the
                // dots appear; they only draw during the pause.
                InterludeDots(gap: pause, alignment: alignment)
                    .padding(.top, fontSize * 0.5)
            }
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
        updateScrollTarget()
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

// MARK: - Row positioning

/// Measures a row's natural position and offsets it by the scroll target.
/// The offset animates with a bouncy spring whose start is staggered: rows
/// at and below the active line follow slightly later the further down
/// they are, so the list ripples instead of moving as one block.
private struct StageRow: ViewModifier {
    let index: Int
    let activeIndex: Int
    let scrollTarget: CGFloat
    let manualOffset: CGFloat
    @Binding var lineTops: [Int: CGFloat]

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .named("lyricsStage")).minY
            } action: { top in
                lineTops[index] = top
            }
            .offset(y: -scrollTarget)
            .animation(M3Motion.lyricsScroll.delay(delay), value: scrollTarget)
            .offset(y: manualOffset)
    }

    private var delay: Double {
        let rel = index - activeIndex
        guard rel >= -1 else { return 0 }
        return min(Double(rel + 1), 8) * 0.04
    }
}

// MARK: - Interlude dots

struct InterludeGap: Equatable {
    let start: TimeInterval
    let end: TimeInterval
}

/// Three dots shown while no words are sung (intro, pauses ≥ 3 s). They
/// fill one after another with the remaining time, breathe gently and
/// shrink away just before the next line starts.
private struct InterludeDots: View {
    let gap: InterludeGap
    let alignment: LyricsAlignment

    private let np = NowPlaying.shared
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        TimelineView(.animation(paused: !np.isPlaying)) { _ in
            let t = PlaybackClock.shared.now() + settings.lyricsOffsetSeconds
            let visible = t >= gap.start - 0.1 && t < gap.end
            let duration = max(0.5, gap.end - gap.start)
            let p = min(max((t - gap.start) / duration, 0), 1)
            // Fade/shrink in over the first 0.3 s, out over the last 0.45 s.
            let enter = min(1, max(0, (t - gap.start) / 0.3))
            let exit = min(1, max(0, (gap.end - t) / 0.45))
            let presence = visible ? min(enter, exit) : 0

            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { i in
                    let fill = min(1, max(0, p * 3 - Double(i)))
                    let breathe = 1 + 0.12 * sin(t * 2 * .pi / 1.6 + Double(i) * 0.6)
                    Circle()
                        .fill(.white)
                        .frame(width: 11, height: 11)
                        .opacity(0.28 + 0.72 * fill)
                        .scaleEffect((0.85 + 0.25 * fill) * breathe)
                        .shadow(color: .white.opacity(0.5 * fill), radius: 6 * fill)
                }
            }
            .scaleEffect(0.6 + 0.4 * presence)
            .opacity(presence)
            .frame(height: 22)
        }
        .accessibilityHidden(true)
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
/// edge. The word being sung glows strongly, grows to ~1.07× and lifts by
/// ~2.5 pt; afterwards it eases back over 0.35 s and its glow fades.
private struct KaraokeRenderer: TextRenderer {
    var time: TimeInterval
    var words: [LyricWord]
    var dimOpacity: Double = 0.38

    /// Room for the glow and the scaled/lifted word outside the text frame.
    var displayPadding: EdgeInsets { EdgeInsets(top: 14, leading: 12, bottom: 14, trailing: 12) }

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

                // Emphasis 0…1: rises quickly while the word is sung, settles
                // smoothly after it ends.
                let emphasis: Double
                if p > 0 && p < 1 {
                    emphasis = Self.easeOut(min(1, p * 3))
                } else if p >= 1 {
                    emphasis = Self.easeOut(max(0, 1 - (time - word.end) / 0.35))
                } else {
                    emphasis = 0
                }

                var c = ctx
                if emphasis > 0.001 {
                    let scale = 1 + 0.07 * emphasis
                    c.translateBy(x: rect.midX, y: rect.midY - 2.5 * emphasis)
                    c.scaleBy(x: scale, y: scale)
                    c.translateBy(x: -rect.midX, y: -rect.midY)
                }

                if p >= 1 {
                    // Sung: bright; glow strong while emphasised, then fades.
                    let since = time - word.end
                    let glow = max(emphasis, max(0, 1 - since / 0.6) * 0.5)
                    var lit = c
                    if glow > 0.01 {
                        lit.addFilter(.shadow(color: .white.opacity(0.75 * glow), radius: 4 + 10 * glow))
                    }
                    lit.draw(run)
                    continue
                }

                var base = c
                base.opacity = dimOpacity
                base.draw(run)
                guard p > 0 else { continue }

                // Leading edge travels from left to right with a soft feather.
                let feather = max(10, rect.width * 0.35)
                let edge = rect.minX - feather + (rect.width + feather) * p
                var lit = c
                lit.clipToLayer { mask in
                    let area = CGRect(x: rect.minX - 4, y: rect.minY - 18, width: rect.width + 8, height: rect.height + 36)
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
                lit.addFilter(.shadow(color: .white.opacity(0.8 * emphasis), radius: 4 + 10 * emphasis))
                lit.draw(run)
            }
        }
    }

    private static func easeOut(_ x: Double) -> Double {
        1 - pow(1 - min(max(x, 0), 1), 3)
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
