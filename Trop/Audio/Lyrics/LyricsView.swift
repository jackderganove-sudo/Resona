//
//  LyricsView.swift
//  Trop / Resona
//
//  Lyrics screen: header, the karaoke stage (Resona/Lyrics/LyricsStage) and
//  the bottom transport. Data handling (instrumental gaps, romanization,
//  offsets, provider refresh) is unchanged from Trop.
//

import SwiftUI
import Translation

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
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// iPad landscape split layout (own, larger lyrics size).
    @State private var isSplit = false
    @State private var chromeResting = false
    @State private var chromeWakeToken = 0
    /// Swipe-down-to-close: how far the view follows the finger.
    @State private var dismissOffset: CGFloat = 0
    @State private var isDismissDragging = false
    @State private var viewHeight: CGFloat = 800
    /// Cover morph with the player (matchedGeometryEffect).
    var coverNamespace: Namespace.ID?

    private var lyricsFontSize: Double {
        settings.lyricsFontSize * (isSplit ? 1.35 : 1)
    }
    @State private var loadedVideoId: String?
    /// Index of the line being sung; -1 before the first line (intro).
    @State private var activeIndex: Int = -1
    /// Line the list glides to — `LyricsTiming.scrollLead` ahead (same clock).
    @State private var scrollIndex: Int = -1
    @State private var displayTime: TimeInterval = 0
    @State private var showLyricsMenu = false
    @State private var showManualSearch = false
    @State private var showSyncSheet = false
    /// On-device translation job (nil = idle).
    @State private var translationConfig: TranslationSession.Configuration?
    @State private var instrumentalGaps: [InstrumentalGap] = []
    @State private var romanizedLines: [String?] = []
    @State private var isLoading = false
    @State private var frameDriver: DisplayLinkDriver?
    @State private var lastGapRefresh: CFTimeInterval = 0


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
        GeometryReader { geo in
            // iPad landscape: cover + controls left, big lyrics right.
            let split = sizeClass == .regular && geo.size.width > geo.size.height && geo.size.width > 700
            Group {
                if split {
                    splitLayout(size: geo.size)
                } else {
                    stackLayout
                }
            }
            .onChange(of: split, initial: true) { _, value in
                isSplit = value
                // The iPad can stand on a desk showing the lyrics.
                UIApplication.shared.isIdleTimerDisabled = value
                wakeChrome()
            }
            .onChange(of: geo.size.height, initial: true) { _, height in viewHeight = height }
            .overlay(alignment: .top) { dismissHandle }
            .offset(y: dismissOffset)
            .opacity(1 - min(0.35, Double(dismissOffset / max(1, viewHeight)) * 0.8))
        }
        .simultaneousGesture(swipeBackGesture)
        .simultaneousGesture(TapGesture().onEnded { wakeChrome() }, including: .all)
        .task(id: chromeWakeToken) { await scheduleRest() }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .sheet(isPresented: Binding(get: { showLyricsMenu && !isSplit }, set: { showLyricsMenu = $0 })) { LyricsMenuSheet() }
        .sheet(isPresented: $showSyncSheet) {
            LyricsSyncSheet(videoId: np.videoId ?? "", songTitle: np.title)
        }
        .sheet(isPresented: $showManualSearch) {
            SearchLyricsSheet(
                videoId: np.videoId ?? "",
                defaultTitle: np.title,
                defaultArtist: np.displayArtist,
                duration: np.duration
            )
        }
        .task(id: np.videoId) { await loadLyrics() }
        .translationTask(translationConfig) { session in
            await translate(with: session)
        }
        .onChange(of: settings.lyricsTranslationMode) { _, _ in prepareTranslation() }
        .onChange(of: LyricsTranslationState.shared.requested) { _, _ in prepareTranslation() }
        .onAppear { startFrameDriver() }
        .onDisappear { stopFrameDriver() }
        .onChange(of: settings.lyricsOffsetSeconds) { _, _ in updateActiveLine() }
        .onChange(of: settings.lyricsLineChangeAdjustMs) { _, _ in updateActiveLine() }
        .onChange(of: settings.romanizeCurrentTrack) { _, _ in
            Task { await rebuildRomanization() }
        }
        .onChange(of: LyricsState.shared.refreshToken) { _, _ in
            Task { await loadLyrics() }
        }
        .onChange(of: LyricsSongAdjustments.shared.tempo(for: np.videoId)) { _, _ in
            Task { await loadLyrics() }
        }
        .onChange(of: LyricsCalibrationStore.shared.calibration(for: np.videoId)) { _, _ in
            Task { await loadLyrics() }
        }
    }

    // MARK: - Layouts

    /// iPhone / portrait: header, lyrics, transport.
    private var stackLayout: some View {
        VStack(spacing: 0) {
            header
                .padding(8)
                .background {
                    ResonaGlassBackground(shape: RoundedRectangle(cornerRadius: M3Shape.extraLarge, style: .continuous))
                }
                .contentShape(Rectangle())
                .gesture(dismissGesture)
                .padding(.horizontal, 12)
                .padding(.top, 14)

            lyricsBody
                .layoutPriority(1)

            controls
                .padding(.horizontal, 28)
                .padding(.bottom, 8)
        }
    }

    /// iPad landscape: large cover with title, progress and transport on the
    /// left, lyrics in a larger size on the right. Controls stay visible;
    /// only with "Hide controls automatically" (off by default) they rest
    /// after 5 s without touch and a tap brings them back.
    private func splitLayout(size: CGSize) -> some View {
        let column = min(size.width * 0.38, 520)
        let cover = min(column - 16, size.height * 0.52)
        return HStack(alignment: .center, spacing: 44) {
            VStack(spacing: 22) {
                Group {
                    if let image = np.thumbnailUIImage {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        Color.white.opacity(0.12)
                    }
                }
                .frame(width: cover, height: cover)
                .clipShape(RoundedRectangle(cornerRadius: M3Shape.extraLarge, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 22, y: 10)
                .modifier(CoverMatch(namespace: coverNamespace))

                VStack(alignment: .leading, spacing: 4) {
                    MarqueeText(text: np.title, font: .poppins(24, weight: .semibold), frameHeight: 34, textColor: .white)
                    Text(np.displayArtist)
                        .font(.poppins(18))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: cover, alignment: .leading)

                controls
                    .frame(width: cover)
                    .opacity(chromeResting ? 0 : 1)
                    .allowsHitTesting(!chromeResting)
            }
            .frame(width: column)

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Spacer()
                    M3IconButton(systemName: "ellipsis", kind: .onDark, size: 44, iconSize: 16, accessibility: "Lyrics options") {
                        showLyricsMenu = true
                    }
                    M3IconButton(systemName: "xmark", kind: .onDark, size: 44, iconSize: 16, accessibility: "Close lyrics") {
                        Log.player.info("UI lyrics close tapped (split)")
                        withAnimation(M3Motion.defaultSpatial) { showLyrics = false }
                    }
                    .accessibilityIdentifier("lyrics.close")
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(dismissGesture)
                .opacity(chromeResting ? 0 : 1)
                .allowsHitTesting(!chromeResting)
                lyricsBody
                    .frame(maxHeight: .infinity)
            }

            // iPad landscape: lyrics options as a side panel.
            if showLyricsMenu {
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        M3IconButton(systemName: "xmark", kind: .onDark, size: 40, iconSize: 14, accessibility: "Close") {
                            withAnimation(M3Motion.defaultSpatial) { showLyricsMenu = false }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    LyricsMenuSheet()
                }
                .frame(width: 400)
                .background(ResonaGlassBackground(shape: RoundedRectangle(cornerRadius: M3Shape.extraLarge, style: .continuous)))
                .clipShape(RoundedRectangle(cornerRadius: M3Shape.extraLarge, style: .continuous))
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(M3Motion.defaultSpatial, value: showLyricsMenu)
        .padding(.horizontal, 40)
        .padding(.vertical, 24)
        .animation(.easeInOut(duration: 0.6), value: chromeResting)
    }

    private func wakeChrome() {
        if chromeResting {
            withAnimation(.easeInOut(duration: 0.35)) { chromeResting = false }
        }
        chromeWakeToken &+= 1
    }

    /// Rest mode after 5 s without touch (split layout, opt-in setting).
    private func scheduleRest() async {
        guard isSplit, settings.lyricsAutoHideControls else {
            if chromeResting { chromeResting = false }
            return
        }
        try? await Task.sleep(for: .seconds(5))
        guard !Task.isCancelled, isSplit, !showLyricsMenu else { return }
        chromeResting = true
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
                Log.player.info("UI lyrics close tapped (stack)")
                withAnimation(M3Motion.defaultSpatial) { showLyrics = false }
            }
            .accessibilityIdentifier("lyrics.close")
            M3IconButton(systemName: "ellipsis", kind: .onDark, size: 40, iconSize: 15, accessibility: "Lyrics options") {
                showLyricsMenu = true
            }
        }
    }

    // MARK: Swipe down to close

    /// Grab handle at the top edge; dragging it (or the header / top bar,
    /// never the scrolling lyrics) pulls the view down.
    private var dismissHandle: some View {
        Capsule()
            .fill(.white.opacity(isDismissDragging ? 0.6 : 0.35))
            .frame(width: 40, height: 5)
            .padding(.top, 5)
            .frame(maxWidth: .infinity)
            .frame(height: 22, alignment: .top)
            .contentShape(Rectangle())
            .gesture(dismissGesture)
            .accessibilityHidden(true)
    }

    /// Follows the finger; closes beyond 25 % of the height or on a fast
    /// downward flick, otherwise springs back.
    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                if !isDismissDragging {
                    guard value.translation.height > 0,
                          value.translation.height > abs(value.translation.width) * 1.3 else { return }
                    isDismissDragging = true
                }
                dismissOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                guard isDismissDragging else { return }
                isDismissDragging = false
                let flick = value.predictedEndTranslation.height - value.translation.height > 220
                if dismissOffset > viewHeight * 0.25 || (flick && dismissOffset > 30) {
                    Log.player.info("UI lyrics closed by swipe (\(Int(dismissOffset)) pt)")
                    withAnimation(M3Motion.defaultSpatial) { showLyrics = false }
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { dismissOffset = 0 }
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
                        .font(.poppins(18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("None of the lyrics sources has this song yet.")
                        .font(.poppins(14))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Button {
                        showManualSearch = true
                    } label: {
                        Label("Search manually", systemImage: "magnifyingglass")
                            .font(.poppins(15, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .frame(height: 44)
                            .background(.white.opacity(0.18), in: Capsule())
                    }
                    .buttonStyle(.expressive)
                    .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            lyricsList
        }
    }

    @ViewBuilder
    private var lyricsList: some View {
        if isSynced {
            VStack(spacing: 0) {
                if let provider = LyricsState.shared.providerName {
                    providerLabel(provider)
                }
                LyricsStage(
                    lines: lines,
                    activeIndex: activeIndex,
                    scrollIndex: scrollIndex,
                    romanized: { romanization(for: $0) },
                    fontSize: lyricsFontSize,
                    alignment: settings.lyricsAlignment,
                    onSeek: { seek(to: $0) }
                ) { _ in
                    // Pauses are shown by the stage's interlude dots.
                    EmptyView()
                }
            }
        } else {
            // Unsynced lyrics: readable text, "Not synced" note, follows
            // the song slowly; no highlight that could run wrong.
            UnsyncedLyricsView(lines: lines, fontSize: lyricsFontSize, alignment: settings.lyricsAlignment, onSync: { showSyncSheet = true }) {
                if let provider = LyricsState.shared.providerName {
                    providerLabel(provider)
                }
            }
        }
    }

    private func providerLabel(_ provider: String) -> some View {
        VStack(alignment: settings.lyricsAlignment.textAlignment.horizontal, spacing: 2) {
            Text(provider == AILyricsSync.transcribedProviderName ? String(localized: "Lyrics transcribed with AI") : String(format: String(localized: "Lyrics from %@"), provider))
            if let note = tempoNote {
                Text(note)
            }
            calibrationOffer
        }
        .font(.poppins(12, weight: .medium))
        .foregroundStyle(.white.opacity(0.5))
        .frame(maxWidth: .infinity, alignment: settings.lyricsAlignment.textAlignment)
        .padding(.horizontal, 28)
        .padding(.top, 8)
    }

    /// Lyrics made for this recording (AI-synced, self-synced, edited,
    /// transcribed): never calibrated.
    private var isUserMadeLyrics: Bool {
        LyricsService.userMadeProviders.contains(LyricsState.shared.providerName ?? "")
    }

    /// Slowed / sped-up song without AI calibration yet: offer it (or show
    /// its state while it runs / when it failed).
    @ViewBuilder
    private var calibrationOffer: some View {
        if let id = np.videoId, isSynced, !isUserMadeLyrics,
           LyricsState.shared.tempoInfo[id]?.isVariant == true,
           LyricsCalibrationStore.shared.calibration(for: id) == nil,
           LyricsSongAdjustments.shared.tempo(for: id) == nil,
           settings.aiCalibrationMode != .off {
            let engine = AILyricsSync.shared
            if engine.videoId == id, engine.isRunning {
                Text("Calibrating the tempo with AI…")
            } else if engine.videoId == id, case .calibrationFailed(let anchors) = engine.phase {
                Text(String(format: String(localized: "AI calibration: only %d reliable anchor points — the calculated tempo stays."), anchors))
            } else {
                Button {
                    engine.start(videoId: id, lines: lines, duration: np.duration, mode: .calibrate)
                } label: {
                    Label("Calibrate tempo with AI", systemImage: "wand.and.stars")
                        .font(.poppins(12, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.top, 4)
                .disabled(engine.isRunning)
            }
        }
    }

    /// "Automatically on Wi-Fi": calibrate a detected slowed / sped-up song
    /// once per session.
    private func autoCalibrateIfWanted(videoId: String) {
        let engine = AILyricsSync.shared
        guard settings.aiCalibrationMode == .automaticOnWiFi, isSynced, !isUserMadeLyrics,
              LyricsState.shared.tempoInfo[videoId]?.isVariant == true,
              LyricsCalibrationStore.shared.calibration(for: videoId) == nil,
              LyricsSongAdjustments.shared.tempo(for: videoId) == nil,
              !engine.isRunning, !engine.autoCalibrated.contains(videoId),
              DownloadManager.shared.isOnWiFi else { return }
        Log.player.info("AISYNC automatic tempo calibration for \(videoId)")
        engine.start(videoId: videoId, lines: lines, duration: np.duration, mode: .calibrate)
    }

    /// Tempo check result for slowed / sped-up versions (or when the timing
    /// didn't fit), e.g. "Tempo adjusted ×1.15 (original 3:12)" or "Tempo not
    /// adjusted: original length not found". Factor > 1 = slowed.
    private var tempoNote: String? {
        let id = np.videoId
        if let manual = LyricsSongAdjustments.shared.tempo(for: id), abs(manual - 1) > 0.005 {
            return String(format: String(localized: "Tempo set manually (%@)"), String(format: "%.2f×", manual))
        }
        if let calibration = LyricsCalibrationStore.shared.calibration(for: id), !isUserMadeLyrics {
            return String(format: String(localized: "Tempo calibrated with AI: %@, %@ (%d anchor points)"),
                          String(format: "%.3f×", calibration.factor),
                          String(format: "%+.1f s", calibration.offset),
                          calibration.anchors)
        }
        guard let id, let info = LyricsState.shared.tempoInfo[id], info.isRelevant else { return nil }
        func clock(_ seconds: Double?) -> String {
            guard let seconds, seconds > 0 else { return "?" }
            let total = Int(seconds.rounded())
            return String(format: "%d:%02d", total / 60, total % 60)
        }
        let factor = info.factor.map { String(format: "%.2f×", $0) } ?? "–"
        switch info.outcome {
        case .applied:
            return String(format: String(localized: "Tempo adjusted %@ (original %@, this version %@)"), factor, clock(info.original), clock(info.played))
        case .sameLength:
            return String(localized: "Tempo not adjusted: same length as the original")
        case .noOriginal:
            return String(localized: "Tempo not adjusted: original length not found")
        case .implausible:
            return String(format: String(localized: "Tempo not adjusted: lengths too different (original %@, this version %@)"), clock(info.original), clock(info.played))
        case .unknownLength:
            return String(localized: "Tempo not checked: song length unknown")
        case .notNeeded:
            return String(localized: "Tempo not adjusted")
        }
    }

    @ViewBuilder
    private func gapIndicator(after index: Int) -> some View {
        let gap = instrumentalGaps.last(where: { $0.afterIndex == index })
        if settings.showIntervalIndicator, let gap, isVisibleInGap(gap) {
            IntervalIndicatorView(
                start: gap.start,
                end: gap.end - 0.65,
                now: displayTime + settings.lyricsOffsetSeconds,
                color: .white
            )
            .transition(.opacity.combined(with: .scale(scale: 0.6)))
        }
    }

    // MARK: - Bottom controls

    private var controls: some View {
        VStack(spacing: 18) {
            PlaybackProgressReader { time, progress in
                VStack(spacing: 8) {
                    ExpressiveSlider(
                        value: Binding(
                            get: { isEditingSlider ? editingProgress : progress },
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
                                editingProgress = progress
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
                        Text(DurationFormat.playbackTime(isEditingSlider ? editingProgress * np.duration : time))
                        Spacer()
                        Text("-" + DurationFormat.playbackTime(max(0, np.duration - (isEditingSlider ? editingProgress * np.duration : time))))
                    }
                    .font(.poppins(14, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
                }
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

    private func seek(to line: LyricLine) {
        guard let t = line.startTime else { return }
        let target = max(0, t - settings.lyricsOffsetSeconds)
        player.seek(to: target)
        np.currentTime = target
        updateActiveLine()
    }

    // MARK: - Translation (on-device, German)

    /// Applies cached translations and starts a translation job when the
    /// mode asks for one (provider translations always win).
    private func prepareTranslation() {
        guard let videoId = np.videoId, !lines.isEmpty else { return }
        let mode = settings.lyricsTranslationMode
        guard mode != .off else { return }
        let state = LyricsTranslationState.shared
        let missing = lines.filter { ($0.translation ?? "").isEmpty }
        // The provider translated (nearly) everything already.
        guard missing.count > lines.count / 4 else { return }
        let cached = LyricsTranslationCache.load(videoId)
        if !cached.isEmpty { applyTranslations(cached) }
        guard let language = state.sourceLanguage[videoId] ?? LyricsLanguage.detect(lines), language != "de" else { return }
        state.sourceLanguage[videoId] = language
        let wanted = mode == .always || state.requested.contains(videoId)
        let stillMissing = lines.contains { ($0.translation ?? "").isEmpty && cached[$0.text] == nil }
        guard wanted, stillMissing else { return }
        translationConfig = TranslationSession.Configuration(
            source: Locale.Language(identifier: language),
            target: Locale.Language(identifier: "de")
        )
    }

    private func translate(with session: TranslationSession) async {
        guard let videoId = np.videoId else { return }
        let state = LyricsTranslationState.shared
        state.isTranslating = true
        defer {
            state.isTranslating = false
            translationConfig = nil
        }
        let texts = Array(Set(lines.filter { ($0.translation ?? "").isEmpty }.map(\.text))).filter { !$0.isEmpty }
        guard !texts.isEmpty else { return }
        let requests = texts.enumerated().map { TranslationSession.Request(sourceText: $0.element, clientIdentifier: String($0.offset)) }
        guard let responses = try? await session.translations(from: requests) else { return }
        var map = LyricsTranslationCache.load(videoId)
        for response in responses {
            guard let id = response.clientIdentifier, let index = Int(id), texts.indices.contains(index) else { continue }
            map[texts[index]] = response.targetText
        }
        LyricsTranslationCache.save(map, for: videoId)
        guard np.videoId == videoId else { return }
        applyTranslations(map)
    }

    /// Fills missing translations (never overwrites the provider's).
    private func applyTranslations(_ map: [String: String]) {
        var changed = false
        let updated = lines.map { line -> LyricLine in
            guard (line.translation ?? "").isEmpty, let text = map[line.text], !LyricsStageText.same(text, line.text) else { return line }
            var copy = line
            copy.translation = text
            changed = true
            return copy
        }
        if changed { lines = updated }
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

    /// Drives line changes from the high-resolution playback clock on
    /// every display frame (instead of the 250 ms NowPlaying timer).
    private func startFrameDriver() {
        PlaybackClock.shared.retain()
        // Correct line immediately when opened mid-song (clock is seeded).
        updateActiveLine()
        let driver = DisplayLinkDriver(preferredFPS: 60) { timestamp in
            updateActiveLine()
            // The interval ring only needs a coarse clock.
            if timestamp - lastGapRefresh > 0.1 {
                lastGapRefresh = timestamp
                let t = PlaybackClock.shared.now()
                if abs(t - displayTime) > 0.05 { displayTime = t }
            }
        }
        driver.start()
        frameDriver = driver
    }

    private func stopFrameDriver() {
        frameDriver?.stop()
        frameDriver = nil
        PlaybackClock.shared.release()
    }

    private func loadLyrics() async {
        guard let videoId = np.videoId else {
            lines = []
            return
        }
        // A reload for the same song (refresh signal, view re-appearing)
        // keeps the existing rows; only a different song clears them.
        if loadedVideoId != videoId {
            // Per-song offset.
            let storedOffset = LyricsSongAdjustments.shared.offset(for: videoId)
            if settings.lyricsOffsetSeconds != storedOffset { settings.lyricsOffsetSeconds = storedOffset }
            lines = []
            instrumentalGaps = []
            activeIndex = -1
            scrollIndex = -1
        }
        isLoading = lines.isEmpty
        LyricsState.shared.providerName = nil
        defer { isLoading = false }

        guard !Task.isCancelled else { return }
        do {
            let result = try await LyricsService.shared.fetchLyrics(videoId: videoId)
            guard !result.isEmpty else { return }
            let withoutMarkers = LyricLine.monotonicTiming(LyricLine.normalizedTiming(result.filter { !Self.isInstrumentalMarker($0) }))
            // Manual tempo (lyrics menu) on top of the automatic factor.
            let manual = LyricsSongAdjustments.shared.tempo(for: videoId)
            let auto = LyricsState.shared.autoTempo[videoId] ?? 1
            let base = withoutMarkers.isEmpty ? result : withoutMarkers
            let timed: [LyricLine]
            if let manual {
                timed = LyricLine.scaled(base, by: manual / auto)
            } else if let calibration = LyricsCalibrationStore.shared.calibration(for: videoId), !isUserMadeLyrics {
                // AI calibration: provider times (original) → this recording.
                timed = LyricLine.monotonicTiming(TempoCalibrator.apply(LyricLine.scaled(base, by: 1 / auto), calibration))
            } else {
                timed = base
            }
            let fresh = LyricLine.stable(timed)
            let unchanged = fresh.count == lines.count && zip(fresh, lines).allSatisfy { $0.sameContent(as: $1) }
            if !unchanged {
                withAnimation(M3Motion.defaultEffects) { lines = fresh }
            }
            loadedVideoId = videoId
            prepareTranslation()
            autoCalibrateIfWanted(videoId: videoId)
            instrumentalGaps = detectGaps(in: result)
            updateActiveLine()
            await rebuildRomanization()
        } catch {}
    }

    /// Highlight index exactly on the timestamps; scroll index earlier by
    /// the central lead (± the user's adjustment). Both from the same
    /// PlaybackClock reading, every display frame.
    private func updateActiveLine() {
        guard !lines.isEmpty else { return }
        let t = PlaybackClock.shared.now() + settings.lyricsOffsetSeconds
        let idx = Self.activeIndex(in: lines, at: t)
        let lead = LyricsTiming.scrollLead - settings.lyricsLineChangeAdjustMs / 1000
        let scroll = max(idx, Self.activeIndex(in: lines, at: t + lead))
        if idx != activeIndex { activeIndex = idx }
        if scroll != scrollIndex { scrollIndex = scroll }
    }

    static func activeIndex(in lines: [LyricLine], at t: TimeInterval) -> Int {
        LyricsTiming.activeIndex(in: lines, at: t)
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

/// matchedGeometryEffect for the cover when a namespace is provided.
private struct CoverMatch: ViewModifier {
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: "player-cover", in: namespace)
        } else {
            content
        }
    }
}
