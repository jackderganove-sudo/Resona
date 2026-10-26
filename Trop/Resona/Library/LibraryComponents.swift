//
//  LibraryComponents.swift
//  Resona
//
//  Library pieces from the reference (screenshots 05/06): filter chips with
//  icons, the sort / view-mode / create control row and the rounded tonal
//  cards with artwork mosaic, count, origin badge, play and menu buttons.
//

import SwiftUI

enum LibraryViewMode: String {
    case list, grid
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case custom, name, recent, size
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .custom: "Custom order"
        case .name: "Name"
        case .recent: "Recently added"
        case .size: "Song count"
        }
    }
}

/// Sort dropdown pill + list/grid segmented toggle + round create button.
struct LibraryControlRow: View {
    @Environment(\.m3) private var m3
    @Binding var sort: LibrarySort
    @Binding var viewMode: LibraryViewMode
    var onCreate: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Menu {
                Picker("Sort", selection: $sort) {
                    ForEach(LibrarySort.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Text(sort.title)
                        .font(.m3(.titleMedium, weight: .regular))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(m3.onSurface)
                .padding(.horizontal, 20)
                .frame(height: 48)
                .background(m3.surfaceContainerHigh, in: Capsule())
            }

            Spacer(minLength: 0)

            HStack(spacing: 2) {
                modeButton(.list, icon: "list.bullet")
                modeButton(.grid, icon: "square.grid.2x2")
            }
            .padding(4)
            .background(m3.surfaceContainerHigh, in: Capsule())

            if let onCreate {
                Button(action: onCreate) {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(m3.onPrimary)
                        .frame(width: 52, height: 52)
                        .background(m3.primary, in: Circle())
                }
                .buttonStyle(.expressive(scale: 0.88))
                .accessibilityLabel(Text("Create playlist"))
            }
        }
        .padding(.horizontal, 16)
    }

    private func modeButton(_ mode: LibraryViewMode, icon: String) -> some View {
        let selected = viewMode == mode
        return Button {
            withAnimation(M3Motion.defaultSpatial) { viewMode = mode }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(selected ? m3.onPrimary : m3.onSurfaceVariant)
                .frame(width: 42, height: 40)
                .background(selected ? m3.primary : .clear, in: Capsule())
        }
        .buttonStyle(.expressive(scale: 0.9))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Artwork for a library card: a single cover, a 2×2 mosaic, or an icon.
enum LibraryArtwork {
    case image(String?)
    case mosaic([String])
    case icon(String)
    case round(String?)

    /// Image used for the card's blurred background.
    var backdropURL: String? {
        switch self {
        case .image(let url), .round(let url): url
        case .mosaic(let urls): urls.first
        case .icon: nil
        }
    }
}

struct LibraryArtworkView: View {
    @Environment(\.m3) private var m3
    let artwork: LibraryArtwork
    var size: CGFloat

    var body: some View {
        Group {
            switch artwork {
            case .image(let url):
                AsyncImageView(url: url)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            case .mosaic(let urls):
                if urls.count >= 4 {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            tile(urls[0])
                            tile(urls[1])
                        }
                        HStack(spacing: 0) {
                            tile(urls[2])
                            tile(urls[3])
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
                } else {
                    AsyncImageView(url: urls.first)
                        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
                }
            case .icon(let name):
                ZStack {
                    LinearGradient(colors: [m3.primaryContainer, m3.tertiaryContainer], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: name)
                        .font(.system(size: size * 0.36, weight: .semibold))
                        .foregroundStyle(m3.onPrimaryContainer)
                }
                .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            case .round(let url):
                AsyncImageView(url: url)
                    .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
    }

    private func tile(_ url: String) -> some View {
        AsyncImageView(url: url)
            .frame(width: size / 2, height: size / 2)
            .clipped()
    }
}

enum LibraryCardMetrics {
    /// Fixed card height (76 pt artwork + 14 pt padding top and bottom).
    static let height: CGFloat = 104
}

/// Rounded tonal library card (list mode).
struct LibraryCard<MenuContent: View>: View {
    @Environment(\.m3) private var m3
    let artwork: LibraryArtwork
    let title: String
    var subtitle: String?
    var badge: LocalizedStringKey?
    var isDownloaded = false
    var onPlay: (() -> Void)?
    @ViewBuilder var menu: () -> MenuContent

    var body: some View {
        HStack(spacing: 18) {
            LibraryArtworkView(artwork: artwork, size: 76)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.m3(.titleLarge, weight: .regular))
                    .foregroundStyle(m3.onSurface)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if isDownloaded {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(m3.primary)
                            .accessibilityLabel(Text("Downloaded"))
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.m3(.titleMedium, weight: .regular))
                            .foregroundStyle(m3.onSurfaceVariant)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if let badge {
                        Text(badge)
                            .font(.m3(.titleSmall, weight: .regular))
                            .foregroundStyle(m3.primary)
                            .lineLimit(1)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 4)
                            .background(m3.primaryContainer.opacity(0.5), in: Capsule())
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let onPlay {
                Button(action: onPlay) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(m3.primary)
                        .frame(width: 44, height: 44)
                        .background(m3.surfaceContainerHighest, in: Circle())
                }
                .buttonStyle(.expressive(scale: 0.86))
                .accessibilityLabel(Text("Play"))
            }

            menu()
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(height: LibraryCardMetrics.height)
        .background {
            // Frosted, cover-tinted card (pre-blurred, cached → smooth lists).
            ZStack {
                m3.surfaceContainerLow
                if let url = artwork.backdropURL {
                    BlurredArtwork(url: url, radius: 12)
                        .opacity(0.7)
                    m3.surfaceContainerLow.opacity(0.55)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: M3Shape.extraLargeIncreased, style: .continuous))
        }
        .contentShape(RoundedRectangle(cornerRadius: M3Shape.extraLargeIncreased, style: .continuous))
    }
}

/// Grid tile used in grid mode.
struct LibraryGridTile: View {
    @Environment(\.m3) private var m3
    let artwork: LibraryArtwork
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                LibraryArtworkView(artwork: artwork, size: geo.size.width)
            }
            .aspectRatio(1, contentMode: .fit)
            .padding(.bottom, 4)
            Text(title)
                .font(.m3(.titleSmall, weight: .medium))
                .foregroundStyle(m3.onSurface)
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(.m3(.bodySmall))
                    .foregroundStyle(m3.onSurfaceVariant)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
