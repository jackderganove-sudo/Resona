//
//  QueueSheet.swift
//  Resona
//
//  Queue bottom sheet (reference screenshot 04): current song header, info
//  bar with song count and total duration, shuffle / repeat / autoplay
//  segmented buttons, and the reorderable queue with the playing row
//  highlighted in primaryContainer.
//

import SwiftUI

struct QueueSheet: View {
    @Binding var pendingRoute: DetailRoute?

    @Environment(\.m3) private var m3
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings
    @Bindable private var np = NowPlaying.shared
    @ObservedObject private var likeStore = LikeStore.shared

    @State private var menuSong: QueueMenuItem?
    @State private var isLocked = false

    private var currentSong: SongItem? {
        np.queueSongs.indices.contains(np.queueIndex) ? np.queueSongs[np.queueIndex] : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 24)

            infoBar
                .padding(.horizontal, 16)
                .padding(.top, 14)

            modeButtons
                .padding(.horizontal, 16)
                .padding(.top, 14)

            VStack(alignment: .leading, spacing: 2) {
                Text("Continue playback")
                    .font(.m3(.titleLarge))
                    .foregroundStyle(m3.onSurface)
                Text("Automatically play similar music")
                    .font(.m3(.bodyMedium))
                    .foregroundStyle(m3.onSurfaceVariant)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)

            Rectangle()
                .fill(m3.outlineVariant)
                .frame(height: 1)
                .padding(.horizontal, 16)

            queueList
        }
        .background(m3.surfaceContainerLow.ignoresSafeArea())
        .presentationDetents([.large, .medium])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(M3Shape.extraLarge)
        .presentationBackground(m3.surfaceContainerLow)
        .sheet(item: $menuSong) { item in
            SongMenuSheet(song: item.song, onNavigate: { route in
                pendingRoute = route
                dismiss()
            })
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 16) {
            Group {
                if let image = np.thumbnailUIImage {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    m3.surfaceContainerHigh
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: M3Metrics.thumbnailRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(text: np.title, font: .m3(.headlineSmall), frameHeight: 32, textColor: m3.onSurface)
                Text(np.displayArtist)
                    .font(.m3(.titleMedium, weight: .regular))
                    .foregroundStyle(m3.onSurfaceVariant)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let currentSong {
                let liked = likeStore.isLiked(videoId: currentSong.videoId)
                Button {
                    Task { await likeStore.toggle(song: currentSong) }
                } label: {
                    Image(systemName: liked ? "heart.fill" : "heart")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(liked ? m3.error : m3.onSurface)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.expressive(scale: 0.85))
                .accessibilityLabel(Text(liked ? "Unlike" : "Like"))
            }
        }
    }

    // MARK: Info bar

    private var infoBar: some View {
        HStack(spacing: 20) {
            Button {
                isLocked.toggle()
            } label: {
                Image(systemName: isLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(m3.onSurfaceVariant)
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel(Text(isLocked ? "Unlock queue" : "Lock queue"))

            Menu {
                Button {
                    np.shuffleQueue()
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                }
                Button {
                    UIPasteboard.general.string = np.queueSongs.map(\.webUrl).joined(separator: "\n")
                } label: {
                    Label("Copy Link", systemImage: "link")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(m3.onSurfaceVariant)
                    .frame(width: 24, height: 24)
            }

            Button(role: .destructive) {
                clearUpcoming()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(m3.error)
            }
            .disabled(isLocked)
            .accessibilityLabel(Text("Clear queue"))

            Spacer()

            Text(summary)
                .font(.m3(.bodyLarge))
                .foregroundStyle(m3.onSurfaceVariant)
                .lineLimit(1)
        }
        .padding(.horizontal, 20)
        .frame(height: 48)
        .background(m3.surfaceContainerHigh, in: Capsule())
    }

    private var summary: String {
        let count = np.queueSongs.count
        let seconds = np.queueSongs.reduce(0) { $0 + max(0, $1.duration) }
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        let duration = h > 0 ? "\(h)h \(m)m \(s)s" : "\(m)m \(s)s"
        let songs = String(format: NSLocalizedString("%d songs", comment: "Queue song count"), count)
        return "\(songs) • \(duration)"
    }

    // MARK: Mode buttons

    private var modeButtons: some View {
        HStack(spacing: 4) {
            modeButton(icon: "shuffle", isOn: np.isShuffleOn, position: .first, label: "Shuffle") {
                np.isShuffleOn.toggle()
                if np.isShuffleOn { np.shuffleQueue() } else { np.disableShuffle() }
            }
            modeButton(icon: np.isRepeatOn ? "repeat.1" : "repeat", isOn: np.isRepeatOn, position: .middle, label: "Repeat") {
                np.isRepeatOn.toggle()
            }
            modeButton(icon: "infinity", isOn: settings.autoplaySimilar, position: .last, label: "Autoplay") {
                settings.autoplaySimilar.toggle()
            }
        }
        .frame(height: 48)
    }

    private func modeButton(icon: String, isOn: Bool, position: M3GroupPosition, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        let outer: CGFloat = 24, inner: CGFloat = 6
        let radii: RectangleCornerRadii = switch position {
        case .first: .init(topLeading: outer, bottomLeading: outer, bottomTrailing: inner, topTrailing: inner)
        case .last: .init(topLeading: inner, bottomLeading: inner, bottomTrailing: outer, topTrailing: outer)
        default: .init(topLeading: inner, bottomLeading: inner, bottomTrailing: inner, topTrailing: inner)
        }
        let shape = UnevenRoundedRectangle(cornerRadii: isOn ? .init(topLeading: outer, bottomLeading: outer, bottomTrailing: outer, topTrailing: outer) : radii, style: .continuous)
        return Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isOn ? m3.onSurface : m3.onSurfaceVariant)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(isOn ? m3.surfaceContainerHighest.mixWhite(0.12) : m3.surfaceContainerHigh, in: shape)
                .contentShape(shape)
        }
        .buttonStyle(.expressive)
        .animation(M3Motion.defaultSpatial, value: isOn)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: List

    private var queueList: some View {
        ScrollViewReader { proxy in
            List {
                if np.queueSongs.isEmpty {
                    Text("Queue is empty")
                        .font(.m3(.bodyLarge))
                        .foregroundStyle(m3.onSurfaceVariant)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(Array(np.queueSongs.enumerated()), id: \.element.videoId) { index, song in
                        row(song: song, index: index)
                    }
                    .onMove { source, destination in
                        guard !isLocked else { return }
                        np.moveQueueSongs(from: source, to: destination)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 72)
            .onAppear {
                if let currentSong { proxy.scrollTo(currentSong.videoId, anchor: .center) }
            }
        }
    }

    private func row(song: SongItem, index: Int) -> some View {
        let isCurrent = index == np.queueIndex
        return HStack(spacing: 16) {
            ZStack {
                SongArtworkView(videoId: song.videoId)
                if isCurrent {
                    Color.black.opacity(0.35)
                    PlayingBars(isAnimating: np.isPlaying)
                        .frame(width: 26, height: 26)
                }
            }
            .frame(width: M3Metrics.listThumbnail, height: M3Metrics.listThumbnail)
            .clipShape(RoundedRectangle(cornerRadius: M3Metrics.thumbnailRadius, style: .continuous))
            .opacity(index < np.queueIndex ? 0.55 : 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.m3(.titleMedium, weight: .regular))
                    .foregroundStyle(isCurrent ? m3.primary : m3.onSurface)
                    .lineLimit(1)
                Text(song.subtitleLine(duration: song.duration))
                    .font(.m3(.bodyMedium))
                    .foregroundStyle(isCurrent ? m3.primary.opacity(0.85) : m3.onSurfaceVariant)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                menuSong = QueueMenuItem(song: song)
            } label: {
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isCurrent ? m3.primary : m3.onSurfaceVariant)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background {
            if isCurrent {
                RoundedRectangle(cornerRadius: M3Shape.large, style: .continuous)
                    .fill(m3.primaryContainer)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { play(at: index) }
        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !isLocked {
                Button(role: .destructive) {
                    withAnimation(M3Motion.defaultSpatial) { remove(at: index) }
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
        .animation(M3Motion.defaultEffects, value: isCurrent)
    }

    // MARK: Actions (same behaviour as Trop's QueueView)

    private func play(at index: Int) {
        guard np.queueSongs.indices.contains(index) else { return }
        np.lastManualSkipTime = Date()
        np.queueIndex = index
        np.playCurrentSong(logContext: "resolveAndPlay", manageResolvingFlag: false)
    }

    private func clearUpcoming() {
        guard np.queueSongs.indices.contains(np.queueIndex) else { return }
        withAnimation(M3Motion.defaultSpatial) {
            np.queueSongs = Array(np.queueSongs[...np.queueIndex])
        }
        np.persistQueueState()
    }

    private func remove(at index: Int) {
        guard np.queueSongs.indices.contains(index) else { return }
        let wasCurrent = index == np.queueIndex
        np.queueSongs.remove(at: index)
        if wasCurrent {
            if np.queueSongs.isEmpty {
                np.queueIndex = 0
                np.isPlaying = false
                np.persistQueueState()
                Task { @MainActor in PlayerController.shared.setPaused(true) }
                return
            }
            let nextIndex = min(index, np.queueSongs.count - 1)
            np.queueIndex = nextIndex
            let song = np.queueSongs[nextIndex]
            np.update(with: song)
            loggedTask(Log.nowPlaying, "removeSong auto-play failed") {
                try await PlaybackManager.shared.resolveAndPlay(videoId: song.videoId)
            }
        } else {
            np.repairQueueIndex()
        }
        np.persistQueueState()
    }
}

private struct QueueMenuItem: Identifiable {
    let song: SongItem
    var id: String { song.videoId }
}

/// Animated equaliser bars shown over the playing song's artwork.
struct PlayingBars: View {
    var isAnimating: Bool
    var color: Color = .white

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isAnimating)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    let phase = sin(t * (5 + Double(i) * 1.7) + Double(i) * 1.3)
                    Capsule()
                        .fill(color)
                        .frame(width: 5)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .scaleEffect(y: isAnimating ? 0.35 + 0.65 * abs(phase) : 0.4, anchor: .bottom)
                }
            }
        }
    }
}

extension Color {
    /// Blends toward white — used for "selected" tonal fills.
    func mixWhite(_ amount: Double) -> Color {
        let rgb = RGB(UIColor(self))
        return rgb.mix(.white, amount).color
    }
}
