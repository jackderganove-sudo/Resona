//
//  SongRowView.swift
//  Trop
//
// Created by 686udjie on 12/09/2026.
//

import SwiftUI

/// Trailing ⋮ button shared by every song row.
struct MoreButton: View {
    @Environment(\.m3) private var m3
    let action: () -> Void

    var body: some View {
        Button(action: action, label: {
            Image(systemName: "ellipsis")
                .rotationEffect(.degrees(90))
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(m3.onSurfaceVariant)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        })
        .buttonStyle(.expressive(scale: 0.85))
        .accessibilityLabel("More")
    }
}

/// Unified song row: artwork + title + artists • duration + overflow menu.
/// Replaces AlbumSongRow, PlaylistSongRow, PodcastEpisodeRow, DownloadedSongRow
/// and the song branch of YouTubeListItemView.
struct SongRowView: View {
    @Environment(\.m3) private var m3
    let song: SongItem
    var artSize: CGFloat = M3Metrics.listThumbnail
    var artRadius: CGFloat = M3Metrics.thumbnailRadius
    var onTap: () -> Void
    var onNavigate: ((DetailRoute) -> Void)?

    @State private var durations = DurationResolver()
    @State private var showSongMenu = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onTap) {
                rowContent
            }
            .buttonStyle(M3RowPressStyle())

            MoreButton {
                showSongMenu = true
            }
            .sheet(isPresented: $showSongMenu) {
                SongMenuSheet(
                    song: song,
                    onNavigate: { onNavigate?($0) }
                )
            }
            .padding(.trailing, 6)
        }
        .task { await durations.resolve(videoId: song.videoId, knownDuration: song.duration) }
        .onReceive(NotificationCenter.default.publisher(for: .durationDidUpdate)) { notification in
            durations.handleUpdate(notification, videoId: song.videoId)
        }
    }

    private var rowContent: some View {
        HStack(spacing: 16) {
            ZStack {
                AsyncImageView(url: song.thumbnailUrl)
                if NowPlaying.shared.videoId == song.videoId {
                    Color.black.opacity(0.35)
                    PlayingBars(isAnimating: NowPlaying.shared.isPlaying)
                        .frame(width: artSize * 0.42, height: artSize * 0.42)
                }
            }
            .frame(width: artSize, height: artSize)
            .clipShape(RoundedRectangle(cornerRadius: max(artRadius, M3Metrics.thumbnailRadius), style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.m3(.titleMedium, weight: .regular))
                    .foregroundStyle(NowPlaying.shared.videoId == song.videoId ? m3.primary : m3.onSurface)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    DownloadStatusIndicator(videoId: song.videoId, size: 13)
                    if song.isExplicit {
                        Image(systemName: "e.square.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(m3.onSurfaceVariant)
                    }
                    Text(song.subtitleLine(duration: durations.effectiveDuration(known: song.duration)))
                        .font(.m3(.bodyMedium))
                        .foregroundStyle(m3.onSurfaceVariant)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, DesignTokens.screenHPadding)
        .padding(.trailing, 4)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

/// Full-cell progress background shown while a song is downloading.
struct DownloadCellProgressView: View {
    let song: SongItem
    @ObservedObject private var downloadManager = DownloadManager.shared

    var body: some View {
        let state = downloadManager.state(for: song.videoId)
        return GeometryReader { geo in
            if case .downloading(let fraction) = state {
                ThemeStore.shared.dark.primary.opacity(0.18)
                    .frame(
                        width: geo.size.width * CGFloat(min(max(fraction, 0), 1)),
                        height: geo.size.height
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: state)
    }
}
