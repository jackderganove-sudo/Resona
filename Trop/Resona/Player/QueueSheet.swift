//
//  QueueSheet.swift
//  Resona
//
//  Queue bottom sheet (reference screenshot 04): current song header, info
//  bar with song count, total duration and labelled actions,
//  autoplay switch, and the reorderable queue with the playing row
//  highlighted in secondaryContainer.
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

            Toggle(isOn: Binding(get: { settings.autoplaySimilar }, set: { settings.autoplaySimilar = $0 })) {
                HStack(spacing: 14) {
                    M3IconCircle { Image(systemName: "infinity") }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Autoplay Similar")
                            .font(.m3(.titleMedium, weight: .regular))
                            .foregroundStyle(m3.onSurface)
                        Text("Automatically play similar music")
                            .font(.m3(.bodyMedium))
                            .foregroundStyle(m3.onSurfaceVariant)
                    }
                }
            }
            .toggleStyle(.m3)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(m3.surfaceContainerHighest, in: RoundedRectangle(cornerRadius: M3Shape.large, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Rectangle()
                .fill(m3.outlineVariant)
                .frame(height: 1)
                .padding(.horizontal, 16)

            queueList
        }
        .presentationDetents([.large, .medium])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(M3Shape.extraLarge)
        .presentationBackground {
            ResonaGlassBackground()
        }
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
        VStack(alignment: .leading, spacing: 10) {
            Text(summary)
                .font(.m3(.bodyLarge))
                .foregroundStyle(m3.onSurfaceVariant)
                .lineLimit(1)
                .padding(.horizontal, 4)
            HStack(spacing: 8) {
                // Lock = order frozen: no reordering, removing or clearing.
                M3Chip(
                    title: isLocked ? String(localized: "Order locked") : String(localized: "Lock order"),
                    systemImage: isLocked ? "lock.fill" : "lock.open",
                    isSelected: isLocked
                ) {
                    withAnimation(M3Motion.fastSpatial) { isLocked.toggle() }
                }
                M3Chip(title: String(localized: "Clear queue"), systemImage: "trash", isSelected: false) {
                    clearUpcoming()
                }
                .disabled(isLocked)
                .opacity(isLocked ? 0.38 : 1)
                Menu {
                    Button {
                        np.shuffleQueue()
                    } label: {
                        Label("Shuffle upcoming", systemImage: "shuffle")
                    }
                    .disabled(isLocked)
                    Button {
                        UIPasteboard.general.string = np.queueSongs.map(\.webUrl).joined(separator: "\n")
                    } label: {
                        Label("Copy Link", systemImage: "link")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(m3.onSecondaryContainer)
                        .frame(width: 40, height: 32)
                        .background(m3.secondaryContainer, in: Capsule())
                }
                .accessibilityLabel(Text("More"))
                Spacer(minLength: 0)
            }
        }
    }

    private var summary: String {
        let count = np.queueSongs.count
        let seconds = np.queueSongs.reduce(0) { $0 + max(0, $1.duration) }
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        let duration = h > 0 ? "\(h)h \(m)m \(s)s" : "\(m)m \(s)s"
        let songs = String(format: NSLocalizedString("%d songs", comment: "Queue song count"), count)
        return "\(songs) • \(duration)"
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
                    .onMove(perform: isLocked ? nil : { source, destination in
                        np.moveQueueSongs(from: source, to: destination)
                    })
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
                    .foregroundStyle(isCurrent ? m3.onSecondaryContainer : m3.onSurface)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    DownloadStatusIndicator(videoId: song.videoId, size: 13)
                    Text(subtitle(for: song, isCurrent: isCurrent))
                        .font(.m3(.bodyMedium))
                        .foregroundStyle(isCurrent ? m3.onSecondaryContainer.opacity(0.8) : m3.onSurfaceVariant)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                menuSong = QueueMenuItem(song: song)
            } label: {
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isCurrent ? m3.onSecondaryContainer : m3.onSurfaceVariant)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Visible drag handle (long-press and drag anywhere on the row).
            if !isLocked {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isCurrent ? m3.onSecondaryContainer : m3.onSurfaceVariant)
                    .frame(width: 28, height: 40)
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background {
            if isCurrent {
                RoundedRectangle(cornerRadius: M3Shape.large, style: .continuous)
                    .fill(m3.secondaryContainer)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { play(at: index) }
        .modifier(M3TapHighlight())
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

    /// "Artist • m:ss" — the artist falls back to the resolved uploader when
    /// the queue item carries no credits.
    private func subtitle(for song: SongItem, isCurrent: Bool) -> String {
        let artist = isCurrent && !np.displayArtist.isEmpty ? np.displayArtist : ArtistNameResolver.shared.artist(for: song)
        let duration = displayDuration(song, isCurrent: isCurrent).formattedDuration
        return [artist, duration].filter { !$0.isEmpty }.joined(separator: " • ")
    }

    /// Some sources (home shelves, radio) deliver songs without a length;
    /// the playing song falls back to the player's duration.
    private func displayDuration(_ song: SongItem, isCurrent: Bool) -> Int {
        if song.duration > 0 { return song.duration }
        if isCurrent, np.duration > 0 { return Int(np.duration.rounded()) }
        return 0
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
