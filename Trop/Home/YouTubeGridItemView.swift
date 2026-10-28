//
//  YouTubeGridItemView.swift
//  Trop
//
//  Created by 686udjie on 01/07/2026.
//

import SwiftUI

struct YouTubeGridItemView: View {
    @Environment(\.m3) private var m3
    var item: YTItem
    var onTap: () -> Void

    @State private var durations = DurationResolver()
    private let artworkSize: CGFloat = 150

    private var videoId: String? {
        switch item {
        case .song(let s): return s.videoId
        case .episode(let e): return e.videoId
        default: return nil
        }
    }

    private var subtitleText: String {
        switch item {
        case .song(let s):
            return s.subtitleLine(duration: durations.effectiveDuration(known: s.duration))
        case .episode(let e):
            return e.toSongItem().subtitleLine(duration: durations.effectiveDuration(known: e.duration))
        case .album(let a):
            let names = a.artists.map(\.name)
            return names.isEmpty ? "" : names.joined(separator: ", ")
        default:
            return ""
        }
    }

    private var artworkShape: AnyShape {
        if case .artist = item { return AnyShape(Circle()) }
        return AnyShape(RoundedRectangle(cornerRadius: M3Shape.medium, style: .continuous))
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                AsyncImageView(url: item.thumbnailUrl)
                    .aspectRatio(1, contentMode: .fill)
                    .frame(width: artworkSize, height: artworkSize)
                    .clipShape(artworkShape)
                    .padding(.bottom, 6)

                Text(item.title)
                    .font(.m3(.titleSmall, weight: .medium))
                    .foregroundStyle(m3.onSurface)
                    .lineLimit(2)

                if !subtitleText.isEmpty {
                    Text(subtitleText)
                        .font(.m3(.bodySmall))
                        .foregroundStyle(m3.onSurfaceVariant)
                        .lineLimit(1)
                }
            }
            .frame(width: artworkSize, height: 218, alignment: .top)
        }
        .buttonStyle(.expressive(scale: 0.96))
        .task {
            guard let vid = videoId else { return }
            let known: Int
            switch item {
            case .song(let s): known = s.duration
            case .episode(let e): known = e.duration
            default: known = 0
            }
            await durations.resolve(videoId: vid, knownDuration: known)
        }
        .onReceive(NotificationCenter.default.publisher(for: .durationDidUpdate)) { notification in
            durations.handleUpdate(notification, videoId: videoId)
        }
    }
}

struct YouTubeListItemView: View {
    @Environment(\.m3) private var m3
    var item: YTItem
    var onTap: () -> Void
    var onNavigate: ((DetailRoute) -> Void)?

    private var songItem: SongItem? {
        switch item {
        case .song(let s): return s
        case .episode(let e): return e.toSongItem()
        default: return nil
        }
    }

    /// Artists are round, everything else uses the expressive rounded square.
    var body: some View {
        if let song = songItem {
            SongRowView(
                song: song,
                artSize: 48,
                onTap: onTap,
                onNavigate: onNavigate
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("result.song")
        } else {
            HStack(spacing: 16) {
                AsyncImageView(url: item.thumbnailUrl)
                    .frame(width: M3Metrics.listThumbnail, height: M3Metrics.listThumbnail)
                    .clipShape(isArtist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: M3Metrics.thumbnailRadius, style: .continuous)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.m3(.titleMedium, weight: .regular))
                        .foregroundStyle(m3.onSurface)
                        .lineLimit(1)

                    if !albumSubtitleText.isEmpty {
                        Text(albumSubtitleText)
                            .font(.m3(.bodyMedium))
                            .foregroundStyle(m3.onSurfaceVariant)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if let url = item.webUrl {
                    MoreButton {
                        UIPasteboard.general.string = url
                    }
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .modifier(M3TapHighlight())
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("result.\(kind)")
        }
    }

    /// UI-test identifier suffix.
    private var kind: String {
        switch item {
        case .song: return "song"
        case .album: return "album"
        case .artist: return "artist"
        case .playlist: return "playlist"
        case .podcast: return "podcast"
        case .episode: return "episode"
        }
    }

    private var isArtist: Bool {
        if case .artist = item { return true }
        return false
    }

    private var albumSubtitleText: String {
        if case .album(let a) = item {
            return a.artists.map(\.name).joined(separator: ", ")
        }
        return ""
    }
}
