//
//  LyricsStage.swift
//  Resona
//
//  Word-synced karaoke lyrics, modelled on reference/lyrics-original.mp4.
//
//  Scrolling: the whole list is ONE view moved by ONE animated offset
//  (spring with a light bounce) per line change, so lines glide together and
//  never cross or re-jitter. Row positions are measured in the list's own
//  coordinate space, i.e. unaffected by that offset (measuring inside the
//  offset fed every scroll back into the next target — the list oscillated
//  and settled near the top).
//
//  Timing: the list scrolls to `scrollIndex`, which the caller computes from
//  the same PlaybackClock as the word highlight but `LyricsTiming.scrollLead`
//  earlier, so the glide finishes as the line is sung; highlighting
//  (`activeIndex`, words) stays exactly on the timestamps.
//
//  Manual drag scrolls freely; 3 s after the last touch the list snaps back.
//  The resume is scheduled on every drag change too, so a drag cancelled by
//  another gesture (no onEnded) can't leave the stage stuck in manual mode.
//

import SwiftUI

/// Central lyric timing constants.
enum LyricsTiming {
    /// The list starts gliding to the next line this long before its
    /// timestamp (user-adjustable by ±0.5 s in the lyrics settings).
    static let scrollLead: TimeInterval = 0.25
    /// Line-change glide: one spring with a light bounce.
    static let scrollAnimation = Animation.spring(response: 0.5, dampingFraction: 0.78)
    /// Back to the current line after manual scrolling.
    static let resumeDelay: Duration = .seconds(3)
}

struct LyricsStage<Accessory: View>: View {
    let lines: [LyricLine]
    /// Line being sung (highlight) — exactly on the timestamps.
    let activeIndex: Int
    /// Line the list is scrolled to — runs slightly ahead of `activeIndex`.
    let scrollIndex: Int
    let romanized: (Int) -> String?
    let fontSize: Double
    let alignment: LyricsAlignment
    let onSeek: (LyricLine) -> Void
    /// Extra view under a line (instrumental gap indicator).
    @ViewBuilder let accessory: (Int) -> Accessory

    /// Natural top of every row inside the list (independent of scrolling).
    @State private var lineTops: [Int: CGFloat] = [:]
    @State private var scrollY: CGFloat = 0
    @State private var stageHeight: CGFloat = 0
    @State private var hasPositioned = false
    @State private var manualOffset: CGFloat = 0
    @State private var dragStart: CGFloat?
    @State private var isManual = false
    @GestureState private var isTouching = false
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
                        .modifier(RowMeasure(index: -1, lineTops: $lineTops))
                }
                ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                    row(index: index, line: line)
                        .modifier(RowMeasure(index: index, lineTops: $lineTops))
                }
                Color.clear.frame(height: geo.size.height)
            }
            // Measured BEFORE the offset: positions stay natural.
            .coordinateSpace(.named(Self.space))
            .frame(width: geo.size.width, alignment: Alignment(horizontal: horizontalAlignment, vertical: .top))
            .offset(y: -scrollY)
            .animation(LyricsTiming.scrollAnimation, value: scrollY)
            .offset(y: manualOffset)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .contentShape(Rectangle())
            .gesture(dragGesture)
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
            .onAppear { stageHeight = geo.size.height }
            .onChange(of: geo.size.height) { _, h in stageHeight = h }
        }
        .clipped()
        .mask(edgeFade)
        .animation(M3Motion.fastSpatial, value: isManual)
        .onChange(of: scrollIndex) { _, _ in updateScrollTarget() }
        .onChange(of: lineTops) { _, _ in updateScrollTarget() }
        .onChange(of: stageHeight) { _, _ in updateScrollTarget() }
        .onChange(of: lines.map(\.id)) { _, _ in hasPositioned = false }
        .onDisappear { resumeTask?.cancel() }
    }

    /// Row the list centres on: the scroll index, or the intro dots/first
    /// line before the first timestamp.
    private var targetKey: Int {
        if scrollIndex >= 0, lineTops[scrollIndex] != nil { return scrollIndex }
        return introGap != nil ? -1 : 0
    }

    /// One offset change per line change (animated by the single
    /// `.animation` on the list). The first placement — opening the lyrics
    /// mid-song — is instant.
    private func updateScrollTarget() {
        guard !isManual else { return }
        guard let top = lineTops[targetKey], stageHeight > 0 else { return }
        let target = max(0, top - stageHeight * anchorFraction)
        if !hasPositioned {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { scrollY = target }
            hasPositioned = true
            return
        }
        guard abs(target - scrollY) > 0.5 else { return }
        scrollY = target
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

    /// Romanization/translation that only repeats the line (Latin script) is
    /// not shown — it appeared as a small duplicate under the line.
    static func sameText(_ a: String, _ b: String) -> Bool {
        func norm(_ s: String) -> String {
            s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
                .filter { $0.isLetter || $0.isNumber }
        }
        return norm(a) == norm(b)
    }

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
            // Same view and layout for every row; becoming active only
            // switches the renderer on (no identity or height change).
            KaraokeLine(line: line, nextStart: nextStart(after: index), isActive: isActive, fontSize: fontSize, alignment: alignment)
            if let roman = romanized(index), !roman.isEmpty, !Self.sameText(roman, line.text) {
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
        // Scoped: only opacity/blur animate here. Positions are moved
        // exclusively by the stage's single offset spring.
        .animation(.easeOut(duration: isActive ? 0.18 : 0.42)) { content in
            content
                .opacity(isActive ? 1 : opacity(distance: distance))
                .blur(radius: isActive || isManual || distance > 10 ? 0 : blur(rel: rel))
        }
        .contentShape(Rectangle())
        .onTapGesture { onSeek(line); resume() }
        .accessibilityAddTraits(.isButton)
    }

    /// Reference: just-finished and upcoming lines ≈ 35 %, fading further out.
    private func opacity(distance: Int) -> Double {
        if isManual { return 0.5 }
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

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .updating($isTouching) { _, touching, _ in touching = true }
            .onChanged { value in
                if dragStart == nil {
                    dragStart = manualOffset
                    isManual = true
                }
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                    manualOffset = (dragStart ?? 0) + value.translation.height
                }
                // Also scheduled here: if another gesture cancels this one,
                // onEnded never runs — the stage must still snap back.
                scheduleResume()
            }
            .onEnded { value in
                let base = dragStart ?? 0
                dragStart = nil
                let current = lineTops[targetKey] ?? 0
                let maxUp = current
                let maxDown = max(0, (lineTops[lines.count - 1] ?? 0) - current)
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
            try? await Task.sleep(for: LyricsTiming.resumeDelay)
            guard !Task.isCancelled else { return }
            if isTouching {
                scheduleResume()   // finger still down: wait for release
            } else {
                resume()
            }
        }
    }

    private func resume() {
        resumeTask?.cancel()
        dragStart = nil
        guard isManual || manualOffset != 0 else { return }
        isManual = false
        // Back to the current line as one glide: release the manual offset
        // and catch up with the scroll target in the same animation.
        withAnimation(LyricsTiming.scrollAnimation) {
            manualOffset = 0
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

// MARK: - Row measuring

/// Records a row's natural top inside the list (the list's own coordinate
/// space, which moves with the scroll offset — so values never feed back).
private struct RowMeasure: ViewModifier {
    let index: Int
    @Binding var lineTops: [Int: CGFloat]

    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .named("lyricsStage")).minY
        } action: { top in
            lineTops[index] = top
        }
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
        // Inactive rows: paused timeline, renderer without words = plain.
        TimelineView(.animation(paused: !isActive || !np.isPlaying)) { _ in
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

private struct KaraokeLine: View {
    let line: LyricLine
    let nextStart: TimeInterval?
    let isActive: Bool
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
                    time: isActive ? PlaybackClock.shared.now() + settings.lyricsOffsetSeconds : 0,
                    words: isActive ? words : []
                ))
        }
    }
}

/// Word-by-word karaoke, matched to reference/lyrics-original.mp4:
/// • unsung words at 40 %, sung words full white without glow
/// • the word being sung fills left→right with a ~1-character soft edge,
///   is full opacity, glows strongly (stacked shadows r 4 + 12 + 24), grows
///   to 1.08× and lifts 2.5 pt; after it ends it settles back in 0.25 s
/// The glow is generated from an already-masked layer, so it radiates freely
/// instead of being cut off at the word's box (the old bug), and the
/// renderer reserves display padding larger than the glow radius.
private struct KaraokeRenderer: TextRenderer {
    var time: TimeInterval
    var words: [LyricWord]
    var dimOpacity: Double = 0.4

    var displayPadding: EdgeInsets { EdgeInsets(top: 40, leading: 40, bottom: 40, trailing: 40) }

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

                // Emphasis: rises fast at the start of the word, settles back
                // over 0.25 s after it ends.
                let emphasis: Double
                if p > 0 && p < 1 {
                    emphasis = Self.easeOut(min(1, p * 4))
                } else if p >= 1 {
                    emphasis = Self.easeOut(max(0, 1 - (time - word.end) / 0.25))
                } else {
                    emphasis = 0
                }

                var c = ctx
                if emphasis > 0.001 {
                    let scale = 1 + 0.08 * emphasis
                    c.translateBy(x: rect.midX, y: rect.midY - 2.5 * emphasis)
                    c.scaleBy(x: scale, y: scale)
                    c.translateBy(x: -rect.midX, y: -rect.midY)
                }

                if p >= 1 && emphasis <= 0.001 {
                    // Sung and settled: bright, no glow.
                    c.draw(run)
                    continue
                }

                // Unsung part (or whole word before it starts): dimmed.
                if p < 1 {
                    var base = c
                    base.opacity = dimOpacity
                    base.draw(run)
                }
                guard p > 0 else { continue }

                // Bright part: masked inside its own layer…
                let feather = max(8, min(rect.width * 0.3, rect.height * 0.55))
                let edge = rect.minX - feather + (rect.width + feather) * p
                let litLayer: (inout GraphicsContext) -> Void = { layer in
                    if p < 1 {
                        layer.clipToLayer { mask in
                            let area = rect.insetBy(dx: -6, dy: -rect.height)
                            mask.fill(
                                Path(area),
                                with: .linearGradient(
                                    Gradient(stops: [
                                        .init(color: .white, location: 0),
                                        .init(color: .clear, location: 1)
                                    ]),
                                    startPoint: CGPoint(x: edge, y: rect.midY),
                                    endPoint: CGPoint(x: edge + feather, y: rect.midY)
                                )
                            )
                        }
                    }
                    layer.draw(run)
                }
                // …then the glow is derived from that layer (unclipped):
                // three stacked shadows for a tight core and a wide halo.
                if emphasis > 0.01 {
                    for (radius, alpha) in [(4.0, 0.9), (12.0, 0.6), (24.0, 0.35)] {
                        var glow = c
                        glow.addFilter(.shadow(color: .white.opacity(alpha * emphasis), radius: radius))
                        glow.drawLayer(content: litLayer)
                    }
                }
                c.drawLayer(content: litLayer)
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
