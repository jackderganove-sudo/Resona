//
//  FullPlayerView.swift
//  Trop / Resona
//
//  Full-screen player in the Material 3 Expressive style of the reference:
//  artwork-glow background, large rounded cover, title + action buttons,
//  expressive seek slider, button group, shuffle/repeat toggles, stream info
//  and a queue / sleep timer / lyrics action row. Wide screens get a
//  side-by-side layout.
//

import SwiftUI

struct FullPlayerView: View {
    let onCollapse: () -> Void

    @Environment(SettingsStore.self) private var settings
    @Environment(\.m3) private var m3
    @Environment(\.playerSheetDrag) private var sheetDrag

    private let player = PlayerController.shared
    @Bindable private var np = NowPlaying.shared
    @ObservedObject private var likeStore = LikeStore.shared
    private let sleepTimer = SleepTimer.shared

    @State private var editingProgress: Double = 0
    @State private var isEditingSlider = false
    @State private var showLyrics = false
    /// "Most replayed" heatmap of the current song (nil = no data).
    @State private var heatmap: Heatmap?
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// iPad landscape: sheets become a side panel.
    @State private var sidePanelMode = false
    /// Cover morph into the iPad lyrics split view.
    @Namespace private var coverSpace
    @State private var showQueue = false
    @State private var showSongMenu = false
    @State private var showSleepTimer = false
    @State private var pendingRoute: DetailRoute?
    @State private var artworkEntryOffset: CGFloat = 0
    @State private var isCollapseDragging = false
    @State private var toast: LocalizedStringKey?
    @State private var toastTask: Task<Void, Never>?

    private var currentSong: SongItem? {
        np.queueSongs.indices.contains(np.queueIndex) ? np.queueSongs[np.queueIndex] : nil
    }

    private var isLiked: Bool {
        guard let currentSong else { return false }
        return likeStore.isLiked(videoId: currentSong.videoId)
    }

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height && geo.size.width > 560
            // iPad landscape: queue / player menu as a side panel instead of
            // a centred sheet; the player content moves aside.
            let usePanel = sizeClass == .regular && wide
            let panel = usePanel ? activePanel : nil
            let contentSize = CGSize(width: geo.size.width - (panel == nil ? 0 : Self.panelWidth + 16), height: geo.size.height)
            ZStack {
                background

                HStack(spacing: 0) {
                    ZStack {
                        if showLyrics {
                            LyricsView(
                                showLyrics: $showLyrics,
                                pendingRoute: $pendingRoute,
                                progressSlider: { progressSlider(compact: true) },
                                coverNamespace: coverSpace
                            )
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        } else if np.isVideoMode && np.hasVideo {
                            videoLayout(size: contentSize)
                        } else if wide {
                            wideLayout(size: contentSize)
                        } else {
                            portraitLayout(size: contentSize)
                        }
                    }
                    .frame(width: contentSize.width)

                    if let panel {
                        sidePanel(panel)
                            .frame(width: Self.panelWidth)
                            .padding(.trailing, 16)
                            .padding(.vertical, 16)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(M3Motion.defaultSpatial, value: panel)

                if showSleepTimer {
                    SleepTimerDialog(isPresented: $showSleepTimer)
                        .zIndex(5)
                }

                if let toast {
                    VStack {
                        Spacer()
                        PlayerToast(text: toast)
                            .padding(.bottom, 84)
                    }
                    .allowsHitTesting(false)
                    .zIndex(6)
                }
            }
            .onChange(of: usePanel, initial: true) { _, value in sidePanelMode = value }
            .animation(M3Motion.defaultSpatial, value: showLyrics)
            .animation(M3Motion.defaultSpatial, value: showSleepTimer)
        }
        .simultaneousGesture(collapseDrag)
        .onChange(of: np.videoId) { _, _ in
            np.isVideoMode = false
            preloadLyrics()
        }
        .onChange(of: np.queueSongs.count) { _, _ in
            np.preloadNeighborArtwork()
            preloadLyrics()
        }
        .onChange(of: np.queueIndex) { _, _ in np.preloadNeighborArtwork() }
        .task(id: np.videoId) {
            heatmap = nil
            guard let id = np.videoId else { return }
            let loaded = await MostReplayedService.shared.heatmap(for: id)
            guard id == np.videoId else { return }
            withAnimation(M3Motion.defaultEffects) { heatmap = loaded }
        }
        .onReceive(AppRouter.shared.$pendingLyrics) { pending in
            guard pending else { return }
            AppRouter.shared.pendingLyrics = false
            withAnimation(M3Motion.defaultSpatial) { showLyrics = true }
        }
        .onReceive(AppRouter.shared.$pendingQueue) { pending in
            guard pending else { return }
            AppRouter.shared.pendingQueue = false
            showQueue = true
        }
        .task { np.preloadNeighborArtwork() }
        .sheet(isPresented: Binding(get: { showSongMenu && !sidePanelMode }, set: { showSongMenu = $0 })) {
            if let currentSong {
                PlayerMenuSheet(song: currentSong, onCollapseRequest: { onCollapse() })
            }
        }
        .sheet(isPresented: Binding(get: { showQueue && !sidePanelMode }, set: { showQueue = $0 })) {
            QueueSheet(pendingRoute: $pendingRoute)
        }
        .background(Color.clear.detailRouteSheet(item: $pendingRoute))
    }

    // MARK: Side panel (iPad landscape)

    enum SidePanel: Equatable { case queue, menu }
    static let panelWidth: CGFloat = 400

    private var activePanel: SidePanel? {
        if showQueue { return .queue }
        if showSongMenu, currentSong != nil { return .menu }
        return nil
    }

    private func sidePanel(_ panel: SidePanel) -> some View {
        let shape = RoundedRectangle(cornerRadius: M3Shape.extraLarge, style: .continuous)
        return VStack(spacing: 0) {
            HStack {
                Spacer()
                M3IconButton(systemName: "xmark", kind: .onDark, size: 40, iconSize: 14, accessibility: "Close") {
                    withAnimation(M3Motion.defaultSpatial) {
                        showQueue = false
                        showSongMenu = false
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            Group {
                switch panel {
                case .queue:
                    QueueSheet(pendingRoute: $pendingRoute)
                case .menu:
                    if let currentSong {
                        PlayerMenuSheet(song: currentSong, onCollapseRequest: { onCollapse() })
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .background(ResonaGlassBackground(shape: shape))
        .clipShape(shape)
        .shadow(color: .black.opacity(0.3), radius: 20, x: -6)
    }

    // MARK: Background

    @ViewBuilder
    private var background: some View {
        if np.isVideoMode && np.hasVideo || settings.playerBackgroundStyle == .solid {
            Color.black.ignoresSafeArea()
        } else {
            PlayerBackground(dimmed: showSleepTimer)
        }
    }

    // MARK: Layouts

    private func portraitLayout(size: CGSize) -> some View {
        let padding: CGFloat = size.width < 380 ? 24 : M3Metrics.playerHorizontalPadding
        let compact = size.height < 700
        let controlSide = min(size.width - padding * 2, size.height * (compact ? 0.4 : 0.46))
        let withLyrics = settings.playerLayoutStyle == .smallCoverLyrics
        // "Small cover + lyrics": smaller cover with a live lyrics preview.
        let coverSide = withLyrics ? controlSide * 0.62 : controlSide
        let artworkSide = controlSide

        return VStack(spacing: 0) {
            header
                .padding(.top, compact ? 4 : 12)

            Spacer(minLength: compact ? 8 : 16)

            artwork
                .frame(width: coverSide, height: coverSide)

            if withLyrics {
                PlayerLyricsPreview {
                    withAnimation(M3Motion.defaultSpatial) { showLyrics = true }
                }
                .frame(width: artworkSide, height: compact ? 96 : 120)
                .padding(.top, 12)
            }

            titleRow
                .padding(.top, compact ? 10 : 14)
                .frame(width: artworkSide)

            progressSlider(compact: false)
                .frame(width: artworkSide)
                .padding(.top, compact ? 8 : 18)

            PlaybackButtonGroup(
                isPlaying: np.isPlaying,
                hasPrevious: np.hasPrevious,
                hasNext: np.hasNext,
                onPrevious: { np.playPrevious() },
                onPlayPause: { player.togglePlayPause() },
                onNext: { np.playNext() }
            )
            .frame(width: artworkSide, height: compact ? 74 : 84)
            .padding(.top, compact ? 10 : 18)

            toggleRow
                .padding(.top, compact ? 10 : 14)

            Spacer(minLength: 8)

            if settings.showAudioDetails {
                StreamInfoLine(videoId: np.videoId)
                    .padding(.bottom, 10)
            }

            bottomRow
                .padding(.horizontal, padding - 12)
                .padding(.bottom, compact ? 4 : 10)
        }
        .frame(maxWidth: .infinity)
    }

    /// Side-by-side layout (iPad, landscape): cover and controls form one
    /// block that is centred vertically, so there is no dead space above
    /// and below; the cover takes most of the height.
    private func wideLayout(size: CGSize) -> some View {
        let column = min(480, max(340, size.width * 0.36))
        let side = max(240, min(size.height * 0.8, size.width - column - 48 - 64))
        return HStack(alignment: .center, spacing: 48) {
            artwork
                .frame(width: side, height: side)
            VStack(spacing: 0) {
                header
                    .padding(.bottom, 18)
                titleRow(multiline: true)
                progressSlider(compact: false)
                    .padding(.top, 18)
                PlaybackButtonGroup(
                    isPlaying: np.isPlaying,
                    hasPrevious: np.hasPrevious,
                    hasNext: np.hasNext,
                    onPrevious: { np.playPrevious() },
                    onPlayPause: { player.togglePlayPause() },
                    onNext: { np.playNext() }
                )
                .frame(height: 84)
                .padding(.top, 16)
                toggleRow
                    .padding(.top, 14)
                if settings.showAudioDetails {
                    StreamInfoLine(videoId: np.videoId)
                        .padding(.top, 20)
                }
                bottomRow
                    .padding(.top, settings.showAudioDetails ? 10 : 24)
            }
            .frame(width: column)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func videoLayout(size: CGSize) -> some View {
        VStack(spacing: 0) {
            HStack {
                M3IconButton(systemName: "chevron.down", kind: .onDark, size: 44, iconSize: 17, accessibility: "Return to artwork player") {
                    withAnimation(M3Motion.defaultSpatial) { np.isVideoMode = false }
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            ZStack {
                VideoPlayerView()
                if !np.isVideoReady { artworkImage.transition(.opacity) }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: M3Shape.large, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .animation(M3Motion.quickFade, value: np.isVideoReady)

            Spacer(minLength: 16)
            titleRow.padding(.horizontal, 24)
            progressSlider(compact: false).padding(.horizontal, 24).padding(.top, 16)
            PlaybackButtonGroup(
                isPlaying: np.isPlaying,
                hasPrevious: np.hasPrevious,
                hasNext: np.hasNext,
                onPrevious: { np.playPrevious() },
                onPlayPause: { player.togglePlayPause() },
                onNext: { np.playNext() }
            )
            .frame(height: 84)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            Spacer(minLength: 16)
            bottomRow.padding(.horizontal, 20).padding(.bottom, 10)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 2) {
            Text("Now Playing")
                .font(.poppins(15, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
            if !np.albumTitle.isEmpty {
                Text(np.albumTitle)
                    .font(.poppins(13))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 48)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { onCollapse() }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("Collapse player"))
    }

    // MARK: Artwork

    private var artwork: some View {
        ZStack {
            artworkImage
            CanvasVideoView(
                videoId: np.videoId,
                title: np.title,
                artist: np.artist,
                album: np.albumTitle.isEmpty ? nil : np.albumTitle,
                isPlaying: np.isPlaying,
                enabled: settings.canvasEnabled,
                onDominantColorsChange: { _ in }
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: M3Shape.large, style: .continuous))
        .matchedGeometryEffect(id: "player-cover", in: coverSpace)
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        .scaleEffect(np.isPlaying ? 1 : 0.94)
        .animation(M3Motion.slowSpatial, value: np.isPlaying)
        .offset(x: artworkEntryOffset)
        .contentShape(Rectangle())
        .onTapGesture {
            guard np.hasVideo else { return }
            player.setVideoMode()
        }
        .gesture(artworkSwipe)
        .accessibilityLabel(Text("Artwork"))
    }

    private var artworkImage: some View {
        GeometryReader { geo in
            if let image = np.thumbnailUIImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .transition(.opacity)
                    .id(ObjectIdentifier(image))
            } else {
                ZStack {
                    Color.white.opacity(0.1)
                    Image(systemName: "music.note")
                        .font(.system(size: 64))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        .animation(M3Motion.defaultEffects, value: np.thumbnailVersion)
    }

    // MARK: Title + actions

    private var titleRow: some View { titleRow(multiline: false) }

    private func titleRow(multiline: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if multiline {
                    Text(np.title)
                        .font(.poppins(22, weight: .semibold, relativeTo: .title2))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    MarqueeText(text: np.title, font: .poppins(22, weight: .semibold, relativeTo: .title2), frameHeight: 32, textColor: .white)
                }
                Button {
                    openArtist()
                } label: {
                    Text(np.displayArtist)
                        .font(.poppins(16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                if let currentSong, let url = URL(string: currentSong.webUrl) {
                    ShareLink(item: url) {
                        Image(systemName: "arrowshape.turn.up.right")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.expressive(scale: 0.86))
                    .accessibilityLabel(Text("Share"))
                }

                PlayerActionButton(
                    systemName: isLiked ? "heart.fill" : "heart",
                    shape: AnyShape(Circle()),
                    tint: isLiked ? m3.error : .white,
                    fill: isLiked ? m3.error.opacity(0.22) : .white.opacity(0.15),
                    label: isLiked ? "Unlike" : "Like"
                ) {
                    guard let currentSong else { return }
                    Task { await likeStore.toggle(song: currentSong) }
                }
                .sensoryFeedback(.success, trigger: isLiked) { _, liked in liked }

                if currentSong != nil {
                    PlayerActionButton(systemName: "ellipsis", label: "More") {
                        showSongMenu = true
                    }
                }
            }
        }
    }

    // MARK: Slider

    private func progressSlider(compact: Bool) -> some View {
        PlaybackProgressReader { time, progress in
            VStack(spacing: compact ? 4 : 6) {
                ExpressiveSlider(
                    value: Binding(
                        get: { isEditingSlider ? editingProgress : progress },
                        set: { editingProgress = $0 }
                    ),
                    trackHeight: compact ? 6 : 14,
                    handleHeight: compact ? 20 : 40,
                    activeColor: .white,
                    inactiveColor: .white.opacity(0.28),
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

                HStack {
                    Text(DurationFormat.playbackTime(isEditingSlider ? editingProgress * np.duration : time))
                    Spacer()
                    Text(DurationFormat.playbackTime(np.duration))
                }
                .font(.poppins(14, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 4)
            }
            // "Most replayed" as a soft wave rising behind the bar.
            .background(alignment: .top) {
                if let heatmap, !compact {
                    HeatmapWave(heatmap: heatmap, color: playerAccentColor)
                        .frame(height: 26)
                        .offset(y: -18)
                        .transition(.opacity)
                }
            }
        }
    }

    private var playerAccentColor: Color { ThemeStore.shared.dark.primary }

    /// Jump just before the most replayed part.
    private func jumpToDrop() {
        guard let time = heatmap?.dropTime, np.duration > 0 else { return }
        player.seek(to: min(time, np.duration - 5))
        player.updateNowPlayingProgress()
        showToast("Jumped to the drop")
    }

    // MARK: Toggles + bottom row

    private var toggleRow: some View {
        HStack(spacing: 16) {
            PlayerRoundToggle(systemName: "shuffle", isOn: np.isShuffleOn, label: "Shuffle") {
                np.isShuffleOn.toggle()
                if np.isShuffleOn { np.shuffleQueue() } else { np.disableShuffle() }
            }
            PlayerRoundToggle(systemName: np.isRepeatOn ? "repeat.1" : "repeat", isOn: np.isRepeatOn, label: "Repeat") {
                np.isRepeatOn.toggle()
            }
            if heatmap?.dropTime != nil {
                PlayerRoundToggle(systemName: "bolt.fill", isOn: false, label: "Jump to the drop") {
                    jumpToDrop()
                }
                .transition(.scale.combined(with: .opacity))
            }
            PlayerAirPlayButton()
        }
    }

    private var bottomRow: some View {
        HStack(spacing: 12) {
            PlayerBottomPill(systemName: "list.bullet", title: "Queue") {
                showQueue = true
            }
            SleepTimerButton(
                onOpen: { withAnimation(M3Motion.defaultSpatial) { showSleepTimer = true } },
                onCancelled: { showToast("Sleep timer off") }
            )
            PlayerBottomPill(systemName: "quote.bubble", title: "Lyrics", highlighted: showLyrics) {
                withAnimation(M3Motion.defaultSpatial) { showLyrics.toggle() }
            }
        }
    }

    // MARK: Gestures

    /// Swipe the artwork sideways to skip (toggleable in Settings).
    private var artworkSwipe: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                guard settings.artworkSwipeNavigation else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < -60, np.hasNext {
                    np.playNext()
                    slideInArtwork(fromLeft: false)
                } else if value.translation.width > 60, np.hasPrevious {
                    np.playPrevious()
                    slideInArtwork(fromLeft: true)
                }
            }
    }

    private func slideInArtwork(fromLeft: Bool) {
        artworkEntryOffset = fromLeft ? -500 : 500
        withAnimation(M3Motion.defaultSpatial) { artworkEntryOffset = 0 }
    }

    /// Pull down anywhere to collapse; the host follows the finger.
    private var collapseDrag: some Gesture {
        DragGesture(minimumDistance: 14, coordinateSpace: .global)
            .onChanged { value in
                guard !showLyrics, !isEditingSlider else { return }
                if !isCollapseDragging {
                    guard value.translation.height > 0,
                          value.translation.height > abs(value.translation.width) * 1.4 else { return }
                    isCollapseDragging = true
                }
                sheetDrag.onChanged(max(0, value.translation.height))
            }
            .onEnded { value in
                guard isCollapseDragging else { return }
                isCollapseDragging = false
                sheetDrag.onEnded(max(0, value.translation.height), value.predictedEndTranslation.height)
            }
    }

    // MARK: Helpers

    private func preloadLyrics() {
        guard let id = np.videoId else { return }
        let upcoming = np.upcomingSongs(prefixLimit: 3).map(\.videoId)
        Task { await LyricsService.shared.preload(videoId: id, upcoming: upcoming) }
    }

    private func showToast(_ text: LocalizedStringKey) {
        toastTask?.cancel()
        withAnimation(M3Motion.defaultSpatial) { toast = text }
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(M3Motion.defaultSpatial) { toast = nil }
        }
    }

    private func openArtist() {
        guard let artist = np.artists.first(where: { $0.id != nil }), let id = artist.id else { return }
        onCollapse()
        AppRouter.shared.open(.artist(browseId: id))
    }
}
