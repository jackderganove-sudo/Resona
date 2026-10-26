//
//  HomeScreenView.swift
//  Trop
//
//  Created by 686udjie on 01/07/2026.
//

import SwiftUI

struct HomeScreenView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.m3) private var m3
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject private var router = AppRouter.shared
    @State private var viewModel = HomeViewModel()
    private let accountState = AccountSheetState.shared

    @State private var pendingRoute: DetailRoute?
    @State private var speedDialEntries: [SpeedDialEntry] = []

    var body: some View {
        NavigationStack(path: $router.homePath) {
            VStack(spacing: 0) {
                TabHeaderView(
                    title: "Home",
                    accountIsLoggedIn: accountState.isLoggedIn,
                    accountImageUrl: accountState.accountImageUrl,
                    onHistory: { router.homePath.append(DetailRoute.history) },
                    onAccount: { router.homePath.append(DetailRoute.settings) }
                )

                if viewModel.isLoading {
                    Spacer()
                    ShimmerLoadingView()
                    Spacer()
                } else if let error = viewModel.error {
                    errorView(error)
                } else {
                    homescreenContent
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .background(homeBackground)
            .toolbar(.hidden, for: .navigationBar)
            .containerBackground(m3.surface, for: .navigation)
            .detailRouteDestinations()
            .onChange(of: pendingRoute) { _, route in
                if let route {
                    router.homePath.append(route)
                    pendingRoute = nil
                }
            }
            .onChange(of: accountState.isLoggedIn) { _, loggedIn in
                viewModel.handleSessionChange(loggedIn: loggedIn)
            }
            .task {
                await viewModel.restoreSession()
                await accountState.restoreSession()
                await accountState.fetchAccountInfo()
                viewModel.loadHomeData()
                await reloadSpeedDial()
                // Trigger library sync in background
                Task {
                    await SyncBridge.checkAndSyncIfStale()
                }
            }
            .task(id: viewModel.homeSections.count) {
                let urls = viewModel.homeSections
                    .flatMap(\.items)
                    .compactMap(\.thumbnailUrl)
                    .compactMap(URL.init)
                await ImagePreloader.shared.preload(urls)
            }
        }
    }

    private var homescreenContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if let chips = viewModel.homePage?.chips, !chips.isEmpty {
                    ChipsRowView(
                        chips: chips,
                        selectedChip: viewModel.selectedChip,
                        onChipTap: { viewModel.toggleChip($0) }
                    )
                }

                ForEach(viewModel.homeSections.indices, id: \.self) { index in
                    let section = viewModel.homeSections[index]
                    sectionView(for: section)
                }

                GeometryReader { _ in
                    Color.clear
                        .onAppear {
                            let total = viewModel.homeSections.count
                            if total > 0 {
                                viewModel.loadMoreIfNeeded(
                                    currentIndex: total - 1,
                                    total: total
                                )
                            }
                        }
                }
                .frame(height: 1)
            }
        }
        .scrollIndicators(.automatic)
        .miniPlayerTracksScroll()
        .refreshable {
            await viewModel.refresh()
            await reloadSpeedDial()
            await SyncBridge.checkAndSyncIfStale()
        }
        .onChange(of: settings.hideExplicit) { _, _ in
            viewModel.syncSettings()
        }
        .onChange(of: settings.showQuickPicks) { _, _ in
            viewModel.syncSettings()
            Task { await viewModel.refresh() }
        }
        .onChange(of: settings.topListsLength) { _, _ in
            Task { await viewModel.refresh() }
        }
        .onChange(of: settings.contentCountry) { _, _ in
            Task { await viewModel.refresh() }
        }
    }

    @ViewBuilder
    private func sectionView(for section: HomeSection) -> some View {
        switch section {
        case .quickPicks:
            quickPicksSection(section)
        case .keepListening:
            keepListeningSection(section)
        case .forgottenFavorites:
            songsSection(section)
        case .homePageSection(let sectionData, _):
            if sectionData.isSongsOnly {
                songsSection(section)
            } else {
                mixedSection(section)
            }
        default:
            mixedSection(section)
        }
    }

    @ViewBuilder
    private func quickPicksSection(_ section: HomeSection) -> some View {
        let pinnedSongs = speedDialEntries.map { $0.toSongItem() }
        let pinnedIds = Set(speedDialEntries.map(\.videoId))
        let visibleItems = section.items.filter { item in
            if case .song(let s) = item { return !pinnedIds.contains(s.videoId) }
            return true
        }
        let quickSongs = visibleItems.compactMap { if case .song(let s) = $0 { return s } else { return nil } }
        let combinedQueue = pinnedSongs + quickSongs

        if combinedQueue.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 4) {
                NavigationTitleView(title: section.displayTitle)
                HeroCarousel(items: combinedQueue.map(YTItem.song)) { item in
                    if case .song(let s) = item {
                        handleSongTap(s, in: combinedQueue)
                    } else {
                        handleItemTap(item)
                    }
                }
                .frame(height: 330)
            }
        }
    }

    private func keepListeningSection(_ section: HomeSection) -> some View {
        let queue = section.items.compactMap { if case .song(let s) = $0 { return s } else { return nil } }
        return VStack(alignment: .leading, spacing: 4) {
            NavigationTitleView(title: section.displayTitle)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(section.items.indices, id: \.self) { i in
                        let item = section.items[i]
                        KeepListeningCard(item: item) {
                            if case .song(let s) = item {
                                handleSongTap(s, in: queue)
                            } else {
                                handleItemTap(item)
                            }
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 16)
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }

    @ViewBuilder
    private func songsSection(_ section: HomeSection) -> some View {
        let queue = section.items.compactMap { if case .song(let s) = $0 { return s } else { return nil } }
        if horizontalSizeClass == .regular {
            // Wide screens: fill the width with a 2–3 column grid instead of
            // one narrow horizontally scrolling column.
            VStack(alignment: .leading, spacing: 4) {
                NavigationTitleView(title: section.displayTitle)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 12, alignment: .leading)], spacing: 0) {
                    ForEach(section.items.indices, id: \.self) { i in
                        songCell(section.items[i], queue: queue)
                    }
                }
                .padding(.horizontal, 4)
            }
        } else {
            let rows = max(1, min(4, section.items.count))
            HorizontalSection(title: section.displayTitle, vSpacing: 4, contentVerticalPadding: 0) {
                LazyHGrid(rows: Array(repeating: GridItem(.fixed(68), spacing: 0), count: rows), spacing: 12) {
                    ForEach(section.items.indices, id: \.self) { i in
                        songCell(section.items[i], queue: queue)
                            .frame(width: 300)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func songCell(_ item: YTItem, queue: [SongItem]) -> some View {
        if case .song(let s) = item {
            YouTubeListItemView(item: item, onTap: { handleSongTap(s, in: queue) }, onNavigate: { pendingRoute = $0 })
        } else {
            YouTubeListItemView(item: item, onTap: { handleItemTap(item) }, onNavigate: { pendingRoute = $0 })
        }
    }

    private func mixedSection(_ section: HomeSection) -> some View {
        let queue = section.items.compactMap { if case .song(let s) = $0 { return s } else { return nil } }
        return HorizontalSection(title: section.displayTitle, vSpacing: 8, contentVerticalPadding: 0) {
            HStack(spacing: 12) {
                ForEach(section.items.indices, id: \.self) { i in
                    let item = section.items[i]
                    if case .song(let s) = item, !queue.isEmpty {
                        YouTubeGridItemView(item: item, onTap: { handleSongTap(s, in: queue) })
                    } else {
                        YouTubeGridItemView(item: item, onTap: { handleItemTap(item) })
                    }
                }
            }
        }
    }

    // MARK: - Quick Picks (pinned)

    private func reloadSpeedDial() async {
        speedDialEntries = (try? await DatabaseService.shared.fetchSpeedDial()) ?? []
    }

    private func handleSongTap(_ song: SongItem, in queue: [SongItem]) {
        Log.homeScreenView.debug("Tapped song in queue: \(song.title) queueCount=\(queue.count)")
        PlaybackQueue.play(song, in: queue, log: Log.homeScreenView, context: "Tapped song")
    }

    private func handleItemTap(_ item: YTItem) {
        Log.homeScreenView.debug("Tapped item: \(item.title) type=\(typeName(item))")
        YTItemRouter.route(
            item,
            playSong: { PlaybackQueue.playSingleWithRadio($0, log: Log.homeScreenView) },
            appendRoute: { router.homePath.append($0) }
        )
    }

    private func typeName(_ item: YTItem) -> String {
        switch item {
        case .song: return "song"
        case .album: return "album"
        case .artist: return "artist"
        case .playlist: return "playlist"
        case .podcast: return "podcast"
        case .episode: return "episode"
        }
    }

    /// Surface with a faint primary glow at the top, like the reference.
    private var homeBackground: some View {
        LinearGradient(
            colors: [m3.primary.opacity(0.07), m3.surface.opacity(0)],
            startPoint: .top,
            endPoint: .init(x: 0.5, y: 0.35)
        )
        .ignoresSafeArea()
    }

    private func errorView(_ error: Error) -> some View {
        ContentUnavailableView(
            "Couldn't load your homescreen",
            systemImage: "wifi.slash",
            description: Text(error.localizedDescription)
        )
    }
}

#Preview {
    HomeScreenView()
}
