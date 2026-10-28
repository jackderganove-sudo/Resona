//
//  MiniPlayer.swift
//  Resona
//
//  Floating mini player: artwork-gradient pill with a circular progress ring
//  around the round cover, marquee title, and previous / play / next buttons.
//  Swipe sideways to skip, drag up (or tap) to open the full player.
//

import SwiftUI

struct MiniPlayer: View {
    @Environment(\.m3) private var m3
    @Environment(\.artworkColors) private var artworkColors

    /// 0 = standalone, 1 = docked on top of the navigation bar.
    var navigationProximity: CGFloat
    var onExpand: () -> Void
    /// Vertical drag forwarded to the player container (negative = up).
    var onVerticalDrag: (CGFloat) -> Void
    var onVerticalDragEnded: (_ translation: CGFloat, _ predicted: CGFloat) -> Void

    private let player = PlayerController.shared
    @Bindable private var np = NowPlaying.shared

    @State private var dragOffset: CGFloat = 0
    @State private var dragAxis: Axis?
    @State private var isCommitting = false

    var body: some View {
        let top = lerp(M3Metrics.floatingBarStandaloneRadius, M3Metrics.floatingBarOuterRadius, navigationProximity)
        let bottom = lerp(M3Metrics.floatingBarStandaloneRadius, M3Metrics.floatingBarJunctionRadius, navigationProximity)
        let shape = UnevenRoundedRectangle(
            cornerRadii: .init(topLeading: top, bottomLeading: bottom, bottomTrailing: bottom, topTrailing: top),
            style: .continuous
        )

        HStack(spacing: 0) {
            pagingArea
            MiniTransportControls(
                isPlaying: np.isPlaying,
                hasPrevious: np.hasPrevious,
                hasNext: np.hasNext,
                onPrevious: { np.playPrevious() },
                onPlayPause: { player.togglePlayPause() },
                onNext: { np.playNext() }
            )
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, 8)
        .frame(height: M3Metrics.miniPlayerHeight)
        .background { MiniPlayerBackground() }
        .clipShape(shape)
        .overlay(shape.stroke(.white.opacity(ResonaGlass.edgeOpacity), lineWidth: ResonaGlass.edgeWidth))
        .contentShape(shape)
        .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
        .onChange(of: np.videoId) { _, _ in
            dragOffset = 0
            preloadLyrics()
        }
        .onChange(of: np.queueIndex) { _, _ in
            dragOffset = 0
            np.preloadNeighborArtwork()
        }
        .task { np.preloadNeighborArtwork() }
    }

    private func preloadLyrics() {
        guard let id = np.videoId else { return }
        let upcoming = np.upcomingSongs(prefixLimit: 3).map(\.videoId)
        Task { await LyricsService.shared.preload(videoId: id, upcoming: upcoming) }
    }

    // MARK: Paging (artwork + titles slide with the swipe)

    private var pagingArea: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack {
                if let prev = song(at: np.queueIndex - 1) {
                    MiniPlayerInfo(song: prev, isCurrent: false).offset(x: -width)
                }
                if let current = song(at: np.queueIndex) {
                    MiniPlayerInfo(song: current, isCurrent: true)
                } else {
                    MiniPlayerInfo(song: nil, isCurrent: true)
                }
                if let next = song(at: np.queueIndex + 1) {
                    MiniPlayerInfo(song: next, isCurrent: false).offset(x: width)
                }
            }
            .frame(width: width, height: geo.size.height)
            .offset(x: dragOffset)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { onExpand() }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("miniplayer")
            .gesture(dragGesture(pageWidth: width))
        }
    }

    private func song(at index: Int) -> SongItem? {
        np.queueSongs.indices.contains(index) ? np.queueSongs[index] : nil
    }

    private func dragGesture(pageWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                guard !isCommitting else { return }
                if dragAxis == nil {
                    dragAxis = abs(value.translation.width) > abs(value.translation.height) ? .horizontal : .vertical
                }
                switch dragAxis {
                case .horizontal:
                    let minOffset: CGFloat = np.hasNext ? -pageWidth : -24
                    let maxOffset: CGFloat = np.hasPrevious ? pageWidth : 24
                    dragOffset = min(max(value.translation.width, minOffset), maxOffset)
                case .vertical:
                    onVerticalDrag(value.translation.height)
                case nil:
                    break
                }
            }
            .onEnded { value in
                guard !isCommitting else { return }
                defer { dragAxis = nil }
                switch dragAxis {
                case .horizontal:
                    let predicted = value.predictedEndTranslation.width
                    if (dragOffset <= -pageWidth * 0.35 || predicted < -pageWidth * 0.6), np.hasNext {
                        commit(next: true, pageWidth: pageWidth)
                    } else if (dragOffset >= pageWidth * 0.35 || predicted > pageWidth * 0.6), np.hasPrevious {
                        commit(next: false, pageWidth: pageWidth)
                    } else {
                        withAnimation(M3Motion.fastSpatial) { dragOffset = 0 }
                    }
                case .vertical:
                    onVerticalDragEnded(value.translation.height, value.predictedEndTranslation.height)
                case nil:
                    break
                }
            }
    }

    private func commit(next: Bool, pageWidth: CGFloat) {
        isCommitting = true
        withAnimation(M3Motion.fastSpatial) { dragOffset = next ? -pageWidth : pageWidth }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 130_000_000)
            if next { np.playNext() } else { np.playPrevious() }
            withAnimation(nil) { dragOffset = 0 }
            isCommitting = false
        }
    }
}

// MARK: - Info (artwork ring + titles)

private struct MiniPlayerInfo: View {
    @Environment(\.m3) private var m3
    let song: SongItem?
    let isCurrent: Bool
    @Bindable private var np = NowPlaying.shared

    init(song: SongItem?, isCurrent: Bool) {
        self.song = song
        self.isCurrent = isCurrent
    }

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                PlaybackProgressReader { _, progress in
                    ProgressRing(progress: isCurrent ? progress : 0, isLoading: isCurrent && np.isPlaying && np.duration <= 0, color: m3.primary, track: m3.primary.opacity(0.22))
                }
                .frame(width: 52, height: 52)
                artwork
                    .frame(width: 42, height: 42)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.22), lineWidth: 1))
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 0) {
                MarqueeText(text: title, font: .m3(.titleMedium, weight: .medium), frameHeight: 24, textColor: .white)
                    .id("title-\(title)")
                    .transition(.opacity)
                MarqueeText(text: artist, font: .m3(.bodySmall), frameHeight: 18, textColor: .white.opacity(0.72))
                    .id("artist-\(artist)")
                    .transition(.opacity)
            }
            .padding(.horizontal, 10)
            .animation(M3Motion.defaultEffects, value: title)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var title: String {
        if isCurrent, !np.title.isEmpty { return np.title }
        return song?.title ?? ""
    }

    private var artist: String {
        if isCurrent, !np.displayArtist.isEmpty { return np.displayArtist }
        return song.map { ArtistNameResolver.shared.artist(for: $0) } ?? ""
    }

    @ViewBuilder
    private var artwork: some View {
        if isCurrent, let image = np.thumbnailUIImage {
            Image(uiImage: image).resizable().scaledToFill()
        } else if let song {
            SongArtworkView(videoId: song.videoId)
        } else {
            Color.white.opacity(0.14)
        }
    }
}

/// Circular progress around the mini-player artwork.
struct ProgressRing: View {
    var progress: Double
    var isLoading: Bool
    var lineWidth: CGFloat = 3
    var color: Color = .white
    var track: Color = .white.opacity(0.24)

    @State private var spin = false

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            if isLoading {
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .onAppear {
                        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { spin = true }
                    }
            } else {
                Circle()
                    .trim(from: 0, to: max(0.001, min(progress, 1)))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(lineWidth / 2)
    }
}

// MARK: - Transport

private struct MiniTransportControls: View {
    @Environment(\.m3) private var m3
    let isPlaying: Bool
    let hasPrevious: Bool
    let hasNext: Bool
    let onPrevious: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            button("backward.fill", size: 18, primary: false, enabled: hasPrevious, label: "Previous", action: onPrevious)
            button(isPlaying ? "pause.fill" : "play.fill", size: 22, primary: true, enabled: true, label: isPlaying ? "Pause" : "Play", action: onPlayPause)
            button("forward.fill", size: 18, primary: false, enabled: hasNext, label: "Next", action: onNext)
        }
    }

    private func button(_ icon: String, size: CGFloat, primary: Bool, enabled: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .bold))
                .contentTransition(.symbolEffect(.replace.downUp))
                // Cover accent: play = primary, skip = primaryContainer.
                .foregroundStyle(primary ? m3.onPrimary : m3.onPrimaryContainer.opacity(enabled ? 1 : 0.38))
                .frame(width: 48, height: 48)
                .background(primary ? m3.primary : m3.primaryContainer.opacity(0.7), in: Circle())
                .animation(M3Motion.colorChange, value: m3.primary)
        }
        .buttonStyle(.expressive(scale: 0.86))
        .disabled(!enabled)
        .accessibilityLabel(Text(label))
    }
}

// MARK: - Background

/// Mini player glass: the shared ResonaGlassBackground (cover-tinted blur,
/// same values as every other blurred surface).
struct MiniPlayerBackground: View {
    var body: some View {
        ResonaGlassBackground(shape: Rectangle(), edge: false)
    }
}

// MARK: - Artwork for arbitrary songs

/// Square artwork for a song, using Trop's artwork cache/loader.
struct SongArtworkView: View {
    let videoId: String
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.white.opacity(0.12)
                Image(systemName: "music.note")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .task(id: videoId) { await load() }
    }

    private func load() async {
        guard let url = URL(string: NowPlaying.artworkURL(for: videoId)) else { return }
        let source: UIImage?
        if let cached = ArtworkLoader.cachedImage(for: url) {
            source = cached
        } else {
            source = try? await ArtworkLoader.image(for: url)
        }
        guard let source else { return }
        // Crop + decode off the main thread (keeps list scrolling smooth).
        let prepared = await Task.detached(priority: .userInitiated) {
            let cropped = source.centerCroppedSquare()
            return cropped.preparingForDisplay() ?? cropped
        }.value
        image = prepared
    }
}
