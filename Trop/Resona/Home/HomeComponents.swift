//
//  HomeComponents.swift
//  Resona
//
//  Home screen pieces from the reference: the Material 3 "hero" carousel used
//  for Quick Picks (one large card followed by narrow peeking cards) and the
//  wide "Keep listening" cards with a round play button.
//

import SwiftUI

// MARK: - Hero carousel

/// M3 Expressive hero carousel. The focused item is large; the next items
/// are narrow slices of the same card (masked, not squashed). Swipe to move;
/// widths animate with an expressive spring.
struct HeroCarousel: View {
    @Environment(\.m3) private var m3
    let items: [YTItem]
    let onTap: (YTItem) -> Void

    @State private var index = 0
    @State private var dragX: CGFloat = 0

    private let spacing: CGFloat = 8
    private let smallWidth: CGFloat = 44

    var body: some View {
        GeometryReader { geo in
            let heroWidth = max(120, geo.size.width - 32 - (smallWidth + spacing) * 2)
            let height = geo.size.height
            HStack(spacing: spacing) {
                ForEach(visibleRange, id: \.self) { i in
                    let rel = i - index
                    let width = width(for: rel, hero: heroWidth)
                    card(items[i], fullWidth: heroWidth, height: height, isHero: rel == 0)
                        .frame(width: max(0, width), height: height)
                        .clipShape(RoundedRectangle(cornerRadius: M3Shape.extraLargeIncreased, style: .continuous))
                        .opacity(rel < 0 ? 0 : 1)
                        .onTapGesture {
                            if rel == 0 {
                                onTap(items[i])
                            } else {
                                move(to: i)
                            }
                        }
                }
            }
            .padding(.horizontal, 16)
            .offset(x: dragX * 0.35)
            .frame(width: geo.size.width, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        dragX = value.translation.width
                    }
                    .onEnded { value in
                        let predicted = value.predictedEndTranslation.width
                        if predicted < -80 {
                            move(to: min(items.count - 1, index + 1))
                        } else if predicted > 80 {
                            move(to: max(0, index - 1))
                        }
                        withAnimation(M3Motion.defaultSpatial) { dragX = 0 }
                    }
            )
            .animation(M3Motion.defaultSpatial, value: index)
        }
    }

    private var visibleRange: [Int] {
        guard !items.isEmpty else { return [] }
        let lower = max(0, index - 1)
        let upper = min(items.count - 1, index + 3)
        return Array(lower...upper)
    }

    private func width(for rel: Int, hero: CGFloat) -> CGFloat {
        switch rel {
        case 0: return hero
        case 1, 2: return smallWidth
        default: return 0
        }
    }

    private func move(to i: Int) {
        guard i != index else { return }
        withAnimation(M3Motion.defaultSpatial) { index = i }
    }

    private func card(_ item: YTItem, fullWidth: CGFloat, height: CGFloat, isHero: Bool) -> some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImageView(url: ArtworkLoader.highRes(item.thumbnailUrl) ?? item.thumbnailUrl)
                .frame(width: fullWidth, height: height)
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.m3(.headlineSmall, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if !subtitle(item).isEmpty {
                    Text(subtitle(item))
                        .font(.m3(.titleMedium, weight: .regular))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
            }
            .padding(20)
            .frame(width: fullWidth, alignment: .leading)
            .opacity(isHero ? 1 : 0)
        }
        .frame(width: fullWidth, height: height)
        .background(m3.surfaceContainerHigh)
    }

    private func subtitle(_ item: YTItem) -> String {
        switch item {
        case .song(let s): s.artistNamesDisplay
        case .album(let a): a.artists.map(\.name).joined(separator: ", ")
        default: ""
        }
    }
}

// MARK: - Keep listening card

/// Wide tonal card: artwork, title, subtitle and a round primary play button.
struct KeepListeningCard: View {
    @Environment(\.m3) private var m3
    let item: YTItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                AsyncImageView(url: item.thumbnailUrl)
                    .frame(width: 96, height: 96)
                    .clipShape(item.isArtistItem ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: M3Shape.largeIncreased, style: .continuous)))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.m3(.titleLarge, weight: .regular))
                        .foregroundStyle(m3.onSurface)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.m3(.titleMedium, weight: .regular))
                        .foregroundStyle(m3.onSurfaceVariant)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "play.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(m3.onPrimary)
                    .frame(width: 48, height: 48)
                    .background(m3.primary, in: Circle())
                    .padding(.trailing, 4)
            }
            .padding(12)
            .frame(width: 330)
            .background(m3.surfaceContainerHigh, in: RoundedRectangle(cornerRadius: M3Shape.extraLargeIncreased, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: M3Shape.extraLargeIncreased, style: .continuous))
        }
        .buttonStyle(.expressive(scale: 0.97))
    }

    private var subtitle: String {
        switch item {
        case .song(let s): s.subtitleLine(duration: s.duration)
        case .album(let a): a.artists.map(\.name).joined(separator: ", ")
        case .playlist: String(localized: "Playlist")
        case .artist: String(localized: "Artist")
        default: ""
        }
    }
}

extension YTItem {
    var isArtistItem: Bool {
        if case .artist = self { return true }
        return false
    }
}
