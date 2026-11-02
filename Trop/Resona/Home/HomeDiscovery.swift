//
//  HomeDiscovery.swift
//  Resona
//
//  Round 10 home (after ArchiveTune 15):
//  - staggered genre tiles, each with its own shape and height,
//  - "Discover genres" on Home from YouTube Music's moods & genres,
//  - large featured cards for playlist shelves,
//  - more varied Quick Picks (no artist dominates the start),
//  - a colour header on genre pages.
//

import SwiftUI
import SwiftyTube

// MARK: - Genre tile shapes

enum GenreTileShape: Int, CaseIterable {
    case rounded, arch, pill, leaf, ticket

    /// Deterministic per title, so a genre always looks the same.
    static func of(_ title: String) -> GenreTileShape {
        allCases[Int(GenreLayout.hash(title) % UInt64(allCases.count))]
    }
}

struct GenreShape: Shape {
    let kind: GenreTileShape

    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height)
        switch kind {
        case .rounded:
            return RoundedRectangle(cornerRadius: M3Shape.extraLarge, style: .continuous).path(in: rect)
        case .pill:
            return RoundedRectangle(cornerRadius: min(r / 2, 44), style: .continuous).path(in: rect)
        case .arch:
            // Round top, small corners at the bottom.
            let top = min(rect.width / 2, rect.height * 0.55)
            return UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: 14,
                                          bottomTrailingRadius: 14, topTrailingRadius: top, style: .continuous).path(in: rect)
        case .leaf:
            let big = min(r * 0.5, 48)
            return UnevenRoundedRectangle(topLeadingRadius: big, bottomLeadingRadius: 10,
                                          bottomTrailingRadius: big, topTrailingRadius: 10, style: .continuous).path(in: rect)
        case .ticket:
            // Rounded rectangle with two notches on the sides.
            var path = RoundedRectangle(cornerRadius: 18, style: .continuous).path(in: rect)
            let notch = min(12, rect.height * 0.12)
            path = path.subtracting(Path(ellipseIn: CGRect(x: rect.minX - notch, y: rect.midY - notch, width: notch * 2, height: notch * 2)))
            path = path.subtracting(Path(ellipseIn: CGRect(x: rect.maxX - notch, y: rect.midY - notch, width: notch * 2, height: notch * 2)))
            return path
        }
    }
}

enum GenreLayout {
    /// FNV-1a over the lowercased title (same as GenreTile's colour).
    static func hash(_ title: String) -> UInt64 {
        var hash: UInt64 = 1469598103934665603
        for byte in title.lowercased().utf8 {
            hash = (hash ^ UInt64(byte)) &* 1099511628211
        }
        return hash
    }

    /// One of three heights per title for the staggered look.
    static func height(for title: String, base: CGFloat = 92) -> CGFloat {
        let factors: [CGFloat] = [1, 1.35, 1.7]
        return base * factors[Int((hash(title) >> 8) % UInt64(factors.count))]
    }

    /// Masonry: each tile goes into the currently shortest column.
    static func columns<T>(_ items: [T], count: Int, height: (T) -> CGFloat, spacing: CGFloat) -> [[T]] {
        let count = max(1, count)
        var columns = Array(repeating: [T](), count: count)
        var heights = Array(repeating: CGFloat(0), count: count)
        for item in items {
            let target = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            columns[target].append(item)
            heights[target] += height(item) + spacing
        }
        return columns
    }

    /// The same genres all day, others tomorrow.
    static func daily<T>(_ items: [T], count: Int, day: Date = Date()) -> [T] {
        guard items.count > count else { return items }
        let dayNumber = Int(day.timeIntervalSince1970 / 86_400)
        var generator = SeededGenerator(seed: UInt64(truncatingIfNeeded: dayNumber) &* 2654435761)
        return Array(items.shuffled(using: &generator).prefix(count))
    }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }

    mutating func next() -> UInt64 {
        // xorshift64*
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 2685821657736338717
    }
}

/// Genre tile in its own shape and height (GenreTile's colours).
struct ShapedGenreTile: View {
    let title: String
    var height: CGFloat

    var body: some View {
        let base = GenreTile.color(for: title)
        let hsv = base.hsv
        let light = RGB(h: hsv.h, s: max(0.3, hsv.s * 0.75), v: min(0.95, hsv.v * 1.08))
        let dark = RGB(h: hsv.h, s: min(1, hsv.s * 1.05), v: hsv.v * 0.62)
        let shape = GenreShape(kind: .of(title))
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [dark.color, light.color], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(.white.opacity(0.09))
                .frame(width: height * 1.1)
                .offset(x: height * 0.9, y: -height * 0.55)
            Text(LocalizedStringKey(title))
                .font(.m3(.titleMedium, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.leading)
                .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
                .frame(maxWidth: .infinity, alignment: .bottomLeading)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
        .frame(height: height)
        .clipShape(shape)
        .contentShape(shape)
    }
}

/// Staggered grid of shaped genre tiles.
struct StaggeredGenreGrid: View {
    let moods: [MoodItem]
    var minColumnWidth: CGFloat = 170
    var spacing: CGFloat = 12
    let onTap: (MoodItem) -> Void

    @State private var width: CGFloat = 0

    var body: some View {
        let count = max(2, Int((width + spacing) / (minColumnWidth + spacing)))
        let columns = GenreLayout.columns(moods, count: count, height: { GenreLayout.height(for: $0.title) }, spacing: spacing)
        HStack(alignment: .top, spacing: spacing) {
            ForEach(columns.indices, id: \.self) { index in
                LazyVStack(spacing: spacing) {
                    ForEach(columns[index]) { mood in
                        Button { onTap(mood) } label: {
                            ShapedGenreTile(title: mood.title, height: GenreLayout.height(for: mood.title))
                        }
                        .buttonStyle(.expressive(scale: 0.96))
                        .accessibilityIdentifier("genre.\(mood.title)")
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { width = geo.size.width }
                    .onChange(of: geo.size.width) { _, value in width = value }
            }
        }
    }
}

// MARK: - Discover genres (Home)

@MainActor
@Observable
final class GenreDiscoveryStore {
    static let shared = GenreDiscoveryStore()
    private(set) var moods: [MoodItem] = []
    private var loadedRegion: String?

    private init() {}

    func load() async {
        let region = SettingsStore.shared.contentCountry
        guard loadedRegion != region || moods.isEmpty else { return }
        loadedRegion = region
        guard let json = try? await InnerTubeClient.tropShared.browse(
            browseId: HomePageParser.exploreBrowseId,
            formData: ["selectedValues": [region]]
        ) else {
            loadedRegion = nil
            return
        }
        var seen = Set<String>()
        moods = HomePageParser.parseExploreSections(from: json)
            .flatMap(\.moods)
            .filter { seen.insert($0.title.lowercased()).inserted }
        Log.explore.info("Genre discovery: \(self.moods.count) genres")
    }
}

struct GenreDiscoverySection: View {
    @Environment(\.m3) private var m3
    private let store = GenreDiscoveryStore.shared

    var body: some View {
        let picks = GenreLayout.daily(store.moods, count: 10)
        Group {
            if !picks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    NavigationTitleView(title: "Discover genres")
                    StaggeredGenreGrid(moods: picks) { mood in
                        AppRouter.shared.open(.genre(title: mood.title, params: mood.params))
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.bottom, 12)
                .accessibilityIdentifier("home.genreDiscovery")
            }
        }
        .task { await store.load() }
    }
}

// MARK: - Genre page header

/// Colour header of a genre page (ArchiveTune's browse header).
struct GenreBrowseHeader: View {
    let title: String
    @Environment(\.m3) private var m3

    var body: some View {
        let base = GenreTile.color(for: title)
        let hsv = base.hsv
        let light = RGB(h: hsv.h, s: max(0.3, hsv.s * 0.8), v: min(0.95, hsv.v * 1.1))
        let dark = RGB(h: hsv.h, s: min(1, hsv.s * 1.05), v: hsv.v * 0.5)
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [light.color, dark.color, m3.surface], startPoint: .topTrailing, endPoint: .bottom)
            GenreShape(kind: .of(title))
                .fill(.white.opacity(0.1))
                .frame(width: 220, height: 220)
                .rotationEffect(.degrees(-12))
                .offset(x: 40, y: -30)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            VStack(alignment: .leading, spacing: 4) {
                Text("Genre")
                    .font(.m3(.labelLarge))
                    .foregroundStyle(.white.opacity(0.8))
                    .textCase(.uppercase)
                Text(LocalizedStringKey(title))
                    .font(.m3(.displaySmall, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(height: 200)
        .clipped()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("genre.header")
    }
}

// MARK: - Featured playlist cards

/// Large card for a playlist shelf: blurred cover behind, cover, title,
/// author and a play affordance.
struct FeaturedPlaylistCard: View {
    let item: YTItem
    var width: CGFloat = 320
    let onTap: () -> Void
    @Environment(\.m3) private var m3

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                AsyncImageView(url: item.thumbnailUrl)
                    .blur(radius: 30, opaque: true)
                    .scaleEffect(1.3)
                    .overlay(Color.black.opacity(0.35))
                HStack(alignment: .bottom, spacing: 14) {
                    AsyncImageView(url: item.thumbnailUrl)
                        .frame(width: 112, height: 112)
                        .clipShape(RoundedRectangle(cornerRadius: M3Shape.large, style: .continuous))
                        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.m3(.titleLarge, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        if let subtitle = Self.subtitle(of: item) {
                            Text(subtitle)
                                .font(.m3(.bodyMedium))
                                .foregroundStyle(.white.opacity(0.8))
                                .lineLimit(1)
                        }
                        Image(systemName: "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(m3.onPrimary)
                            .frame(width: 40, height: 40)
                            .background(m3.primary, in: Circle())
                            .padding(.top, 6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
            }
            .frame(width: width, height: 180)
            .clipShape(RoundedRectangle(cornerRadius: M3Shape.extraLarge, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: M3Shape.extraLarge, style: .continuous))
        }
        .buttonStyle(.expressive(scale: 0.97))
    }

    static func subtitle(of item: YTItem) -> String? {
        switch item {
        case .playlist(let playlist):
            let parts = [playlist.author, playlist.songCount.map { L10n.songs($0) }].compactMap { $0 }.filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts.joined(separator: " • ")
        case .album(let album):
            return album.artists.map(\.name).joined(separator: ", ")
        default:
            return nil
        }
    }
}

enum FeaturedShelf {
    /// A shelf is "featured" when most of it is playlists.
    static func isPlaylistShelf(_ items: [YTItem]) -> Bool {
        guard items.count >= 3 else { return false }
        let playlists = items.filter { if case .playlist = $0 { return true } else { return false } }.count
        return Double(playlists) / Double(items.count) >= 0.6
    }
}

// MARK: - Quick Picks variety

enum QuickPicksMix {
    /// At most `maxPerArtist` songs of one artist among the first picks;
    /// the rest keep their order behind them.
    static func diversified(_ songs: [SongItem], maxPerArtist: Int = 2) -> [SongItem] {
        var counts: [String: Int] = [:]
        var front: [SongItem] = []
        var back: [SongItem] = []
        for song in songs {
            let key = (song.artists.first?.name ?? song.artistNamesDisplay).lowercased()
            let count = counts[key, default: 0]
            if key.isEmpty || count < maxPerArtist {
                front.append(song)
                counts[key] = count + 1
            } else {
                back.append(song)
            }
        }
        return front + back
    }
}
