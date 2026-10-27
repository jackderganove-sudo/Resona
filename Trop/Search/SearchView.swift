//
//  SearchView.swift
//  Trop
//
//  Created by 686udjie on 03/07/2026.
//

import SwiftUI

struct SearchView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.m3) private var m3
    @State private var viewModel = SearchViewModel()
    @State private var exploreModel = ExploreViewModel()
    @State private var homeTab: SearchHomeTab = .explore
    @ObservedObject private var router = AppRouter.shared
    @FocusState private var fieldFocused: Bool

    @State private var pendingRoute: DetailRoute?

    var body: some View {
        NavigationStack(path: $router.searchPath) {
            VStack(spacing: 0) {
                content
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .frostedTopChrome {
                VStack(spacing: 0) {
                    ResonaTopBar()
                    searchTopBar
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .containerBackground(m3.surface, for: .navigation)
            .detailRouteDestinations()
            .navigationDestination(for: MoodItem.self) { mood in
                MoodDetailView(mood: mood)
            }
            .onChange(of: pendingRoute) { _, route in
                if let route {
                    router.searchPath.append(route)
                    pendingRoute = nil
                }
            }
            .onAppear {
                viewModel.loadSearchHistory()
                exploreModel.load()
            }
            .task(id: viewModel.results.count) {
                let urls = viewModel.results
                    .flatMap(\.items)
                    .compactMap(\.thumbnailUrl)
                    .compactMap(URL.init)
                await ImagePreloader.shared.preload(urls)
            }
        }
    }

    // MARK: - Top bar

    /// Large pill search field with the sort menu inside (reference style).
    private var searchTopBar: some View {
        M3SearchBar(text: $viewModel.fieldText, focus: $fieldFocused, onSubmit: { submit(nil) }) {
            sortMenu
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SearchSort.allCases, id: \.self) { option in
                Button {
                    viewModel.sort = option
                } label: {
                    if viewModel.sort == option {
                        Label(LocalizedStringKey(option.title), systemImage: "checkmark")
                    } else {
                        Text(LocalizedStringKey(option.title))
                    }
                }
            }
        } label: {
            Image(systemName: "globe")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(m3.onSurface)
                .frame(width: 40, height: 40)
        }
        .accessibilityLabel("Sort results")
    }

    /// Focuses the field (raising the keyboard) whenever the Search tab
    /// becomes active.
    private func focusIfSearchTab() {
        if AppRouter.shared.selectedTabIndex == 3 {
            fieldFocused = true
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle:
            let typed = !viewModel.fieldText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if typed {
                suggestionsView
            } else if fieldFocused {
                // Empty field while typing: recent searches (deletable).
                if viewModel.searchHistory.isEmpty { noRecentSearchesView } else { searchHistoryView }
            } else {
                searchHome
            }
        case .loading:
            loadingView
        case .results:
            searchResultsList
        case .noResults:
            noResultsView
        case .failed:
            errorView(viewModel.error)
        }
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            ShimmerLoadingView()
            Spacer()
        }
    }

    // MARK: - Submission

    private func submit(_ text: String? = nil) {
        if let text {
            viewModel.fieldText = text
        }
        fieldFocused = false
        viewModel.submit()
    }

    /// Idle state: "Explore" (moods, charts, new releases) and
    /// "Suggestions" (recent searches) tabs, like the reference.
    private var searchHome: some View {
        VStack(spacing: 0) {
            M3PrimaryTabs(
                tabs: [
                    (tab: SearchHomeTab.explore, title: "Explore", icon: "safari"),
                    (tab: SearchHomeTab.suggestions, title: "Suggestions", icon: "sparkles")
                ],
                selection: $homeTab
            )

            Group {
                switch homeTab {
                case .explore:
                    exploreContent
                case .suggestions:
                    if viewModel.searchHistory.isEmpty {
                        noRecentSearchesView
                    } else {
                        searchHistoryView
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .transition(.opacity)
        }
        .animation(M3Motion.defaultEffects, value: homeTab)
    }

    @ViewBuilder
    private var exploreContent: some View {
        switch exploreModel.phase {
        case .idle, .loading:
            ExploreSkeletonView()
        case .loaded:
            ScrollView {
                ExploreSectionsList(
                    sections: exploreModel.sections.sorted { lhs, rhs in
                        // Moods & genres first, as in the reference.
                        (lhs.kind == .moods ? 0 : 1) < (rhs.kind == .moods ? 0 : 1)
                    },
                    pendingRoute: $pendingRoute
                )
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            .miniPlayerTracksScroll()
            .refreshable { await exploreModel.refresh() }
        case .empty, .failed:
            ContentUnavailableView(
                "Nothing to explore",
                systemImage: "safari",
                description: Text("Try again later.")
            )
        }
    }

    private var searchHistoryView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Recently searched")
                        .font(.m3(.titleMedium, weight: .medium))
                        .foregroundStyle(m3.onSurface)
                    Spacer()
                    Button("Clear") {
                        viewModel.clearSearchHistory()
                    }
                    .font(.m3(.labelLarge))
                    .foregroundStyle(m3.primary)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 6)

                ForEach(viewModel.searchHistory, id: \.query) { entry in
                    HStack(spacing: 18) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 18))
                            .foregroundStyle(m3.onSurfaceVariant)
                        Text(entry.query)
                            .font(.m3(.bodyLarge))
                            .foregroundStyle(m3.onSurface)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            viewModel.fieldText = entry.query
                            fieldFocused = true
                        } label: {
                            Image(systemName: "arrow.up.left")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(m3.onSurfaceVariant)
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Edit search"))
                    }
                    .padding(.leading, 18)
                    .padding(.trailing, 8)
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
                    .onTapGesture { submit(entry.query) }
                    .contextMenu {
                        Button(role: .destructive) {
                            viewModel.deleteSearchHistoryEntry(entry)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .scrollIndicators(.automatic)
        .scrollDismissesKeyboard(.immediately)
        .miniPlayerTracksScroll()
    }

    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let fix = viewModel.didYouMean {
                    didYouMeanBanner(fix)
                }
                if !viewModel.availableFilters.isEmpty {
                    filterChips
                }

                if let hero = viewModel.heroArtist {
                    artistHeroCard(hero, songs: viewModel.heroSongs)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                ForEach(viewModel.filteredResults) { section in
                    sectionHeader(section.title)

                    switch section.title {
                    case "Artists":
                        artistCarousel(items: section.items)
                    case "Albums":
                        albumCarousel(items: section.items)
                    default:
                        ForEach(section.items, id: \.id) { item in
                            YouTubeListItemView(item: item, onTap: {
                                handleItemTap(item)
                            }, onNavigate: { pendingRoute = $0 })
                        }
                    }
                }
            }
            .padding(.bottom, 16)
        }
        .scrollIndicators(.automatic)
        .scrollDismissesKeyboard(.immediately)
        .miniPlayerTracksScroll()
    }

    /// Section title with chevron — taps drill into (or clear) the filter.
    private func sectionHeader(_ title: String) -> some View {
        Button {
            if viewModel.selectedSectionFilter == title {
                viewModel.selectedSectionFilter = nil
            } else {
                viewModel.selectedSectionFilter = title
                viewModel.isShowingLibrary = false
            }
        } label: {
            HStack(spacing: 6) {
                Text(LocalizedStringKey(title))
                    .font(.m3(.titleLarge))
                    .foregroundStyle(m3.onSurface)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(m3.onSurfaceVariant)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    /// Artist-first hero: big circular artwork + name, then top songs.
    private func artistHeroCard(_ artist: ArtistItem, songs: [SongItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                router.searchPath.append(DetailRoute.artist(browseId: artist.browseId))
            } label: {
                HStack(spacing: 12) {
                    AsyncImageView(url: artist.thumbnailUrl)
                        .frame(width: 56, height: 56)
                        .clipShape(Circle())
                    Text(artist.name)
                        .font(.m3(.headlineSmall))
                        .foregroundStyle(m3.onSurface)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(m3.onPrimaryContainer)
                        .frame(width: 40, height: 40)
                        .background(m3.primaryContainer, in: Circle())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            ForEach(songs, id: \.videoId) { song in
                let item = YTItem.song(song)
                YouTubeListItemView(item: item, onTap: {
                    handleItemTap(item)
                }, onNavigate: { pendingRoute = $0 })
            }
        }
        .padding(.bottom, 8)
        .background(
            RoundedRectangle(cornerRadius: M3Shape.extraLarge, style: .continuous)
                .fill(m3.surfaceContainerLow)
        )
    }

    private func artistCarousel(items: [YTItem]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(items, id: \.id) { item in
                    if case .artist(let artist) = item {
                        Button {
                            router.searchPath.append(DetailRoute.artist(browseId: artist.browseId))
                        } label: {
                            VStack(spacing: 8) {
                                AsyncImageView(url: artist.thumbnailUrl)
                                    .frame(width: 110, height: 110)
                                    .clipShape(Circle())
                                Text(artist.name)
                                    .font(.m3(.titleSmall, weight: .medium))
                                    .foregroundStyle(m3.onSurface)
                                    .lineLimit(1)
                                    .frame(width: 110)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private func albumCarousel(items: [YTItem]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(items, id: \.id) { item in
                    if case .album(let album) = item {
                        Button {
                            router.searchPath.append(DetailRoute.album(browseId: album.browseId))
                        } label: {
                            MediaGridCell(
                                thumbnailUrl: album.thumbnailUrl,
                                title: album.title,
                                subtitle: album.artists.map(\.name).joined(separator: ", "),
                                size: 140
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private var filterChips: some View {
        FilterChipBar(
            items: ["All Results"] + viewModel.availableFilters,
            id: \.self,
            title: { $0 },
            isSelected: { filter in
                if filter == "All Results" {
                    return viewModel.selectedSectionFilter == nil && !viewModel.isShowingLibrary
                }
                return filter == "Library"
                    ? viewModel.isShowingLibrary
                    : viewModel.selectedSectionFilter == filter
            },
            onTap: { filter in
                if filter == "All Results" {
                    viewModel.selectedSectionFilter = nil
                    viewModel.isShowingLibrary = false
                } else if filter == "Library" {
                    let willShow = !viewModel.isShowingLibrary
                    viewModel.isShowingLibrary = willShow
                    viewModel.selectedSectionFilter = nil
                } else {
                    viewModel.selectedSectionFilter = filter
                    viewModel.isShowingLibrary = false
                }
            }
        )
    }

    private var noResultsView: some View {
        VStack(spacing: 0) {
            if let fix = viewModel.didYouMean {
                didYouMeanBanner(fix)
            }
            ContentUnavailableView(
                "No Results",
                systemImage: "magnifyingglass",
                description: Text("No results found for \"\(viewModel.submittedQuery)\"")
            )
        }
    }

    /// "Did you mean: …" from YouTube's correction; tap searches for it.
    private func didYouMeanBanner(_ fix: String) -> some View {
        Button {
            submit(fix)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(m3.primary)
                Text("Did you mean:")
                    .foregroundStyle(m3.onSurfaceVariant)
                Text(fix)
                    .fontWeight(.semibold)
                    .foregroundStyle(m3.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.m3(.bodyLarge))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Live suggestions

    /// While typing: direct hits with artwork first (tap plays/opens),
    /// then text suggestions (tap searches; the arrow only fills the field).
    private var suggestionsView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.suggestionItems, id: \.id) { item in
                    Button {
                        fieldFocused = false
                        handleItemTap(item)
                    } label: {
                        HStack(spacing: 14) {
                            AsyncImageView(url: item.thumbnailUrl)
                                .frame(width: 48, height: 48)
                                .clipShape(suggestionShape(for: item))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.m3(.bodyLarge, weight: .medium))
                                    .foregroundStyle(m3.onSurface)
                                    .lineLimit(1)
                                Text(LocalizedStringKey(Self.kindLabel(item)))
                                    .font(.m3(.bodyMedium))
                                    .foregroundStyle(m3.onSurfaceVariant)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: Self.kindIcon(item))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(m3.onSurfaceVariant)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(M3RowPressStyle())
                }

                if !viewModel.suggestionItems.isEmpty && !viewModel.suggestionTexts.isEmpty {
                    Rectangle().fill(m3.outlineVariant.opacity(0.5)).frame(height: 1)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6)
                }

                ForEach(viewModel.suggestionTexts, id: \.self) { text in
                    HStack(spacing: 18) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 17))
                            .foregroundStyle(m3.onSurfaceVariant)
                        Text(text)
                            .font(.m3(.bodyLarge))
                            .foregroundStyle(m3.onSurface)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            viewModel.fieldText = text
                            fieldFocused = true
                        } label: {
                            Image(systemName: "arrow.up.left")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(m3.onSurfaceVariant)
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Use suggestion"))
                    }
                    .padding(.leading, 18)
                    .padding(.trailing, 8)
                    .frame(minHeight: 50)
                    .contentShape(Rectangle())
                    .onTapGesture { submit(text) }
                }
            }
            .padding(.vertical, 6)
            .animation(M3Motion.defaultEffects, value: viewModel.suggestionTexts)
        }
        .scrollIndicators(.automatic)
        .scrollDismissesKeyboard(.immediately)
        .miniPlayerTracksScroll()
    }

    private func suggestionShape(for item: YTItem) -> AnyShape {
        if case .artist = item { return AnyShape(Circle()) }
        return AnyShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    static func kindLabel(_ item: YTItem) -> String {
        switch item {
        case .song(let song):
            let artist = artistDisplayString(from: song.artists)
            return artist.isEmpty ? "Song" : artist
        case .album(let album): return album.artists.isEmpty ? "Album" : "Album • " + album.artists.map(\.name).joined(separator: ", ")
        case .artist: return "Artist"
        case .playlist: return "Playlist"
        case .podcast: return "Podcast"
        case .episode: return "Episode"
        }
    }

    static func kindIcon(_ item: YTItem) -> String {
        switch item {
        case .song, .episode: "play.circle"
        case .album: "square.stack"
        case .artist: "person"
        case .playlist: "music.note.list"
        case .podcast: "mic"
        }
    }

    private var noRecentSearchesView: some View {
        ContentUnavailableView(
            "No Recent Searches",
            systemImage: "magnifyingglass",
            description: Text("Your recent searches will appear here.")
        )
    }

    private func errorView(_ error: Error?) -> some View {
        ContentUnavailableView(
            "Search failed",
            systemImage: "exclamationmark.triangle",
            description: Text(error?.localizedDescription ?? "Something went wrong.")
        )
    }

    private func handleItemTap(_ item: YTItem) {
        YTItemRouter.route(
            item,
            playSong: { PlaybackQueue.playSingleWithRadio($0, log: Log.searchView) },
            appendRoute: { router.searchPath.append($0) }
        )
    }
}

enum SearchHomeTab: Hashable {
    case explore
    case suggestions
}
