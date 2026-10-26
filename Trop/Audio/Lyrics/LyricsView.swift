//
//  LyricsView.swift
//  Trop / Resona
//
//  Karaoke lyrics in the "BetterLyrics" style of the reference app:
//  the current line is large, bright and glowing with a gradient fill that
//  sweeps across it over the line's duration; other lines dim and blur with
//  their distance; the list auto-scrolls smoothly so the active line sits at
//  35 % of the height; tapping a line seeks to it. Data handling (instrumental
//  gaps, romanization, offsets, provider refresh) is unchanged from Trop.
//

import SwiftUI

struct LyricsView<ProgressSlider: View>: View {
    private let np = NowPlaying.shared
    private let player = PlayerController.shared
    @Environment(SettingsStore.self) private var settings
    @Environment(\.m3) private var m3

    @Binding var showLyrics: Bool
    let pendingRoute: Binding<DetailRoute?>
    /// Kept for source compatibility; the lyrics screen draws its own slider.
    @ViewBuilder var progressSlider: () -> ProgressSlider

    @State private var lines: [LyricLine] = []
    @State private var activeIndex: Int = 0
    @State private var displayTime: TimeInterval = 0
    @State private var showLyricsMenu = false
    @State private var instrumentalGaps: [InstrumentalGap] = []
    @State private var romanizedLines: [String?] = []
    @State private var isLoading = false

    // Scrolling
    @State private var isManualScrolling = false
    @State private var resumeTask: Task<Void, Never>?
    @State private var scrollProxy: ScrollViewProxy?
    @State private var hasPositionedInitialLyrics = false

    // Bottom controls
    @State private var editingProgress: Double = 0
    @State private var isEditingSlider = false

    struct InstrumentalGap {
        let afterIndex: Int
        let start: TimeInterval
        let end: TimeInterval
    }

    private var isSynced: Bool { lines.contains { $0.startTime != nil } }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 8)

            lyricsBody
                .layoutPriority(1)

            controls
                .padding(.horizontal, 28)
                .padding(.bottom, 8)
        }
        .simultaneousGesture(swipeBackGesture)
        .sheet(isPresented: $showLyricsMenu) { LyricsMenuSheet() }
        .task(id: np.videoId) { await loadLyrics() }
        .onChange(of: np.currentTime) { _, _ in updateActiveLine() }
        .onChange(of: settings.lyricsOffsetSeconds) { _, _ in updateActiveLine() }
        .onChange(of: settings.romanizeCurrentTrack) { _, _ in
            Task { await rebuildRomanization() }
        }
        .onChange(of: LyricsState.shared.refreshToken) { _, _ in
            Task { await loadLyrics() }
        }
        .task { await runDisplayTimer() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            Group {
                if let image = np.thumbnailUIImage {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Color.white.opacity(0.12)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 0) {
                MarqueeText(text: np.title, font: .poppins(17, weight: .medium), frameHeight: 26, textColor: .white)
                Text(np.displayArtist)
                    .font(.poppins(16))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            M3IconButton(systemName: "xmark", kind: .onDark, size: 40, iconSize: 15, accessibility: "Close lyrics") {
                withAnimation(M3Motion.defaultSpatial) { showLyrics = false }
            }
            M3IconButton(systemName: "ellipsis", kind: .onDark, size: 40, iconSize: 15, accessibility: "Lyrics options") {
                showLyricsMenu = true
            }
        }
    }

    private var swipeBackGesture: some Gesture {
        DragGesture(minimumDistance: 16)
            .onEnded { value in
                let isHorizontal = abs(value.translation.width) > abs(value.translation.height)
                guard value.startLocation.x <= 28, isHorizontal, value.translation.width > 80 else { return }
                withAnimation(M3Motion.defaultSpatial) { showLyrics = false }
            }
    }

    // MARK: - Lyrics body

    @ViewBuilder
    private var lyricsBody: some View {
        if lines.isEmpty {
            VStack(spacing: 14) {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "text.quote")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("No lyrics found")
                        .font(.poppins(17, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            lyricsList
        }
    }

    private var lyricsList: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: settings.lyricsAlignment.textAlignment.horizontal, spacing: 0) {
                            Color.clear.frame(height: geo.size.height * 0.3)

                            if let provider = LyricsState.shared.providerName {
                                Text("Lyrics from \(provider)")
                                    .font(.poppins(12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .frame(maxWidth: .infinity, alignment: settings.lyricsAlignment.textAlignment)
                                    .padding(.horizontal, 28)
                                    .padding(.bottom, 12)
                            }

                            ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                                lineRow(index: index, line: line)
                                    .id(line.id)
                            }

                            Color.clear.frame(height: geo.size.height * 0.6)
                        }
                    }
                    .scrollIndicators(.hidden)
                    .mask(edgeFade)
                    .onScrollPhaseChange { _, phase in
                        if phase == .tracking || phase == .interacting {
                            beginManualScroll()
                        } else if phase == .idle, isManualScrolling {
                            scheduleResume()
                        }
                    }
                    .onAppear {
                        scrollProxy = proxy
                        scrollToActive(animated: false)
                    }
                    .onChange(of: activeIndex) { _, _ in
                        guard !isManualScrolling else { return }
                        scrollToActive(animated: hasPositionedInitialLyrics)
                        hasPositionedInitialLyrics = true
                    }
                }

                if isManualScrolling && isSynced {
                    Button {
                        resumeAutoScroll()
                    } label: {
                        Label("Re-sync", systemImage: "arrow.triangle.2.circlepath")
                            .font(.poppins(14, weight: .medium))
                            .foregroundStyle(m3.onPrimaryContainer)
                            .padding(.horizontal, 18)
                            .frame(height: 40)
                            .background(m3.primaryContainer, in: Capsule())
                    }
                    .buttonStyle(.expressive)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(M3Motion.defaultSpatial, value: isManualScrolling)
        }
    }

    /// Soft fade at the top and bottom of the scrolling lyrics.
    private var edgeFade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.08),
                .init(color: .black, location: 0.86),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Line

    private func lineRow(index: Int, line: LyricLine) -> some View {
        let gap = instrumentalGaps.last(where: { $0.afterIndex == index })
        let showRing = settings.showIntervalIndicator && gap.map(isVisibleInGap) == true
        let distance = abs(index - activeIndex)
        let isActive = isSynced && index == activeIndex

        return VStack(alignment: settings.lyricsAlignment.textAlignment.horizontal, spacing: 0) {
            KaraokeLine(
                text: line.text.isEmpty ? "\u{266A}" : line.text,
                romanized: romanization(for: index),
                isActive: isActive,
                timing: isActive ? timing(for: index) : nil,
                fontSize: settings.lyricsFontSize,
                alignment: settings.lyricsAlignment
            )
            .opacity(lineOpacity(distance: distance))
            .blur(radius: lineBlur(distance: distance))
            .scaleEffect(isActive || !isSynced ? 1 : 0.95, anchor: scaleAnchor)
            .animation(.easeOut(duration: isActive ? 0.33 : 0.5), value: activeIndex)
            .animation(.easeOut(duration: 0.3), value: isManualScrolling)
            .padding(.horizontal, 28)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture { seek(to: line) }
            .accessibilityAddTraits(.isButton)

            if showRing, let gap {
                IntervalIndicatorView(
                    start: gap.start,
                    end: gap.end - 0.65,
                    now: displayTime + settings.lyricsOffsetSeconds,
                    color: .white
                )
                .padding(.horizontal, 28)
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showRing)
    }

    private var scaleAnchor: UnitPoint {
        switch settings.lyricsAlignment {
        case .left: .leading
        case .center: .center
        case .right: .trailing
        }
    }

    /// Reference V2 values: 1 / 0.52 / 0.30 / 0.18 / 0.10 (brighter while
    /// the user scrolls by hand).
    private func lineOpacity(distance: Int) -> Double {
        guard isSynced else { return 0.92 }
        if distance == 0 { return 1 }
        if isManualScrolling {
            return [0.72, 0.56, 0.40][safe: distance - 1] ?? 0.28
        }
        return [0.52, 0.30, 0.18][safe: distance - 1] ?? 0.10
    }

    /// Reference V2 blur: 0 / 2 / 5 / 12, off while scrolling manually.
    private func lineBlur(distance: Int) -> CGFloat {
        guard isSynced, !isManualScrolling, distance > 0 else { return 0 }
        return [2, 5][safe: distance - 1] ?? 12
    }

    /// Start/end of a line for the fill sweep (end = next timestamp).
    private func timing(for index: Int) -> (start: TimeInterval, end: TimeInterval)? {
        guard let start = lines[index].startTime else { return nil }
        let next = lines[(index + 1)...].compactMap(\.startTime).first ?? (start + 5)
        return (start, max(start + 0.4, min(next, start + 12)))
    }

    // MARK: - Bottom controls

    private var controls: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                ExpressiveSlider(
                    value: Binding(
                        get: { isEditingSlider ? editingProgress : Double(np.progress) },
                        set: { editingProgress = $0 }
                    ),
                    trackHeight: 7,
                    handleHeight: 7,
                    activeColor: .white.opacity(0.9),
                    inactiveColor: .white.opacity(0.25),
                    handleColor: .clear,
                    showsStopIndicator: false,
                    onEditingChanged: { editing in
                        if editing {
                            editingProgress = Double(np.progress)
                        } else {
                            let target = editingProgress * np.duration
                            player.seek(to: target)
                            np.currentTime = target
                            player.updateNowPlayingProgress()
                        }
                        isEditingSlider = editing
                    }
                )
                .frame(height: 16)

                HStack {
                    Text(DurationFormat.playbackTime(isEditingSlider ? editingProgress * np.duration : np.currentTime))
                    Spacer()
                    Text("-" + DurationFormat.playbackTime(max(0, np.duration - (isEditingSlider ? editingProgress * np.duration : np.currentTime))))
                }
                .font(.poppins(14, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
            }

            HStack {
                transportButton("backward.fill", label: "Previous", enabled: np.hasPrevious) { np.playPrevious() }
                Spacer()
                transportButton(np.isPlaying ? "pause.fill" : "play.fill", label: np.isPlaying ? "Pause" : "Play", enabled: true, size: 42) {
                    player.togglePlayPause()
                }
                Spacer()
                transportButton("forward.fill", label: "Next", enabled: np.hasNext) { np.playNext() }
            }
            .padding(.horizontal, 40)

            HStack(spacing: 14) {
                Image(systemName: "speaker.slash.fill")
                ExpressiveSlider(
                    value: Binding(
                        get: { settings.playerVolume },
                        set: { newValue in
                            settings.playerVolume = newValue.clamped01
                            player.applyPlayerVolume()
                        }
                    ),
                    trackHeight: 7,
                    handleHeight: 7,
                    activeColor: .white.opacity(0.9),
                    inactiveColor: .white.opacity(0.25),
                    handleColor: .clear,
                    showsStopIndicator: false
                )
                .frame(height: 16)
                Image(systemName: "speaker.wave.2.fill")
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.top, 8)
    }

    private func transportButton(_ icon: String, label: LocalizedStringKey, enabled: Bool, size: CGFloat = 32, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(.white.opacity(enabled ? 1 : 0.35))
                .contentTransition(.symbolEffect(.replace.downUp))
                .frame(width: 64, height: 56)
                .contentShape(Rectangle())
        }
        .buttonStyle(.expressive(scale: 0.84))
        .disabled(!enabled)
        .accessibilityLabel(Text(label))
    }

    // MARK: - Scrolling

    private func scrollToActive(animated: Bool) {
        guard lines.indices.contains(activeIndex), isSynced else { return }
        let id = lines[activeIndex].id
        if animated {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.86)) {
                scrollProxy?.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.35))
            }
        } else {
            scrollProxy?.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.35))
        }
    }

    private func beginManualScroll() {
        resumeTask?.cancel()
        guard !isManualScrolling else { return }
        isManualScrolling = true
    }

    /// Like the reference's MANUAL_SCROLL_TIMEOUT: return to the active line
    /// a few seconds after the user stops scrolling.
    private func scheduleResume() {
        resumeTask?.cancel()
        resumeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            resumeAutoScroll()
        }
    }

    private func resumeAutoScroll() {
        resumeTask?.cancel()
        isManualScrolling = false
        scrollToActive(animated: true)
    }

    private func seek(to line: LyricLine) {
        guard let t = line.startTime else { return }
        let target = max(0, t - settings.lyricsOffsetSeconds)
        player.seek(to: target)
        np.currentTime = target
        updateActiveLine()
        resumeAutoScroll()
    }

    // MARK: - Romanization

    private func romanization(for index: Int) -> String? {
        guard settings.romanizeCurrentTrack, romanizedLines.indices.contains(index) else { return nil }
        return romanizedLines[index]
    }

    private func rebuildRomanization() async {
        guard settings.romanizeCurrentTrack, !lines.isEmpty else {
            romanizedLines = []
            return
        }
        let texts = lines.map(\.text)
        romanizedLines = await Task.detached(priority: .userInitiated) {
            texts.map { LyricsRomanizer.romanize($0) }
        }.value
    }

    // MARK: - Instrumental gaps (unchanged from Trop)

    private static func isInstrumentalMarker(_ line: LyricLine) -> Bool {
        line.text.trimmingCharacters(in: CharacterSet(charactersIn: "♪*· ")).isEmpty
    }

    private func detectGaps(in all: [LyricLine]) -> [InstrumentalGap] {
        var displayIndices = [Int?](repeating: nil, count: all.count)
        var displayCount = 0
        for (i, line) in all.enumerated() where !Self.isInstrumentalMarker(line) {
            displayIndices[i] = displayCount
            displayCount += 1
        }

        var gaps: [InstrumentalGap] = []
        for (i, marker) in all.enumerated() {
            guard Self.isInstrumentalMarker(marker), let gapStart = marker.startTime else { continue }
            var afterIndex: Int?
            var j = i - 1
            while j >= 0, afterIndex == nil {
                afterIndex = displayIndices[j]
                j -= 1
            }
            guard let afterIndex else { continue }
            var nextStart: TimeInterval?
            var k = i + 1
            while k < all.count, nextStart == nil {
                nextStart = all[k].startTime
                k += 1
            }
            guard let gapEnd = nextStart, gapEnd - gapStart > 4 else { continue }
            gaps.append(InstrumentalGap(afterIndex: afterIndex, start: gapStart, end: gapEnd))
        }
        return gaps
    }

    private func isVisibleInGap(_ gap: InstrumentalGap) -> Bool {
        let t = displayTime + settings.lyricsOffsetSeconds
        return t >= gap.start && t <= gap.end - 0.65
    }

    // MARK: - Data

    private func runDisplayTimer() async {
        while !Task.isCancelled {
            let interval: UInt64 = (np.isPlaying && isSynced) ? 120_000_000 : 500_000_000
            let t = np.currentTime
            if t != displayTime { displayTime = t }
            try? await Task.sleep(nanoseconds: interval)
        }
    }

    private func loadLyrics() async {
        guard let videoId = np.videoId else {
            lines = []
            return
        }
        lines = []
        instrumentalGaps = []
        activeIndex = 0
        hasPositionedInitialLyrics = false
        isManualScrolling = false
        isLoading = true
        LyricsState.shared.providerName = nil
        defer { isLoading = false }

        guard !Task.isCancelled else { return }
        do {
            let result = try await LyricsService.shared.fetchLyrics(videoId: videoId)
            guard !result.isEmpty else { return }
            let withoutMarkers = result.filter { !Self.isInstrumentalMarker($0) }
            withAnimation(M3Motion.defaultEffects) {
                lines = withoutMarkers.isEmpty ? result : withoutMarkers
            }
            instrumentalGaps = detectGaps(in: result)
            updateActiveLine()
            await rebuildRomanization()
        } catch {}
    }

    private func updateActiveLine() {
        guard !lines.isEmpty else { return }
        let t = np.currentTime + settings.lyricsOffsetSeconds
        var idx = 0
        for (i, line) in lines.enumerated() {
            guard let start = line.startTime else { continue }
            if start <= t { idx = i } else { break }
        }
        if idx != activeIndex { activeIndex = idx }
    }
}

// MARK: - Karaoke line

/// One lyric line. The active line is drawn twice: a dim base and a bright
/// glowing copy revealed by a soft gradient mask that sweeps across the line
/// (top-leading → bottom-trailing, following reading order on wrapped lines).
private struct KaraokeLine: View {
    let text: String
    let romanized: String?
    let isActive: Bool
    let timing: (start: TimeInterval, end: TimeInterval)?
    let fontSize: Double
    let alignment: LyricsAlignment

    var body: some View {
        VStack(alignment: alignment.textAlignment.horizontal, spacing: 4) {
            if isActive, let timing {
                LyricsClockView { now in
                    let raw = (now - timing.start) / max(0.01, timing.end - timing.start)
                    let p = min(max(raw, 0), 1)
                    lineText
                        .foregroundStyle(.white.opacity(0.42))
                        .overlay {
                            lineText
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.white, Color(white: 0.92)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .shadow(color: .white.opacity(0.45 * min(1, p * 2)), radius: 12 * min(1, p * 2))
                                .mask(sweepMask(progress: p))
                        }
                }
            } else {
                lineText
                    .foregroundStyle(.white.opacity(isActive ? 1 : 0.95))
                    .shadow(color: .white.opacity(isActive ? 0.4 : 0), radius: isActive ? 10 : 0)
            }

            if let romanized, !romanized.isEmpty {
                Text(romanized)
                    .font(.system(size: max(12, fontSize * 0.55), weight: .semibold))
                    .foregroundStyle(.white.opacity(isActive ? 0.76 : 0.6))
                    .multilineTextAlignment(alignment.multilineTextAlignment)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment.textAlignment)
    }

    private var lineText: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .bold))
            .tracking(-0.4)
            .lineSpacing(fontSize * 0.08)
            .multilineTextAlignment(alignment.multilineTextAlignment)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func sweepMask(progress p: Double) -> some View {
        // Feathered edge; starts slightly before 0 and ends after 1 so the
        // line is fully lit well before it ends.
        let edge = 0.18
        let head = -edge + p * (1 + edge * 2) * 1.15
        return LinearGradient(
            stops: [
                .init(color: .black, location: max(0, min(1, head - edge))),
                .init(color: .clear, location: max(0.0001, min(1, head)))
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// Re-renders its content every frame with an extrapolated playback time
/// (NowPlaying only ticks every ~250 ms), so the fill sweep is smooth.
private struct LyricsClockView<Content: View>: View {
    @ViewBuilder let content: (TimeInterval) -> Content
    private let np = NowPlaying.shared
    @Environment(SettingsStore.self) private var settings
    @State private var anchor: (time: TimeInterval, date: Date) = (0, .now)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !np.isPlaying)) { context in
            let elapsed = np.isPlaying ? context.date.timeIntervalSince(anchor.date) : 0
            content(anchor.time + min(elapsed, 1) + settings.lyricsOffsetSeconds)
        }
        .onAppear { anchor = (np.currentTime, .now) }
        .onChange(of: np.currentTime) { _, t in anchor = (t, .now) }
    }
}

// MARK: - Interval indicator ring (from Trop)

private struct IntervalIndicatorView: View {
    let start: TimeInterval
    let end: TimeInterval
    let now: TimeInterval
    let color: Color

    @State private var displayedProgress: Double
    @State private var anchorNow: TimeInterval

    init(start: TimeInterval, end: TimeInterval, now: TimeInterval, color: Color) {
        self.start = start
        self.end = end
        self.now = now
        self.color = color
        _displayedProgress = State(initialValue: Self.fraction(at: now, start: start, end: end))
        _anchorNow = State(initialValue: now)
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                let threshold = Double(i + 1) / 3
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                    .opacity(displayedProgress >= threshold - 0.33 ? 0.35 + 0.65 * min(1, (displayedProgress - (threshold - 0.33)) * 3) : 0.25)
                    .scaleEffect(displayedProgress >= threshold - 0.33 ? 1.1 : 0.85)
            }
        }
        .frame(height: 36)
        .padding(.top, 8)
        .onAppear { animateToCompletion() }
        .onChange(of: now) { _, newNow in
            if abs(newNow - anchorNow) > 0.75 {
                anchorNow = newNow
                displayedProgress = Self.fraction(at: newNow, start: start, end: end)
                animateToCompletion(at: newNow)
            } else {
                anchorNow = newNow
            }
        }
    }

    private static func fraction(at t: TimeInterval, start: TimeInterval, end: TimeInterval) -> Double {
        guard end > start else { return 1 }
        return min(1, max(0, (t - start) / (end - start)))
    }

    private func animateToCompletion(at reference: TimeInterval? = nil) {
        let remaining = max(0.15, end - (reference ?? now))
        displayedProgress = min(displayedProgress, 0.999)
        withAnimation(.linear(duration: remaining)) {
            displayedProgress = 1
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
