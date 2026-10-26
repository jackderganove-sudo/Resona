//
//  LibraryView.swift
//  Trop
//
//  Created by 686udjie on 05/07/2026.
//

import SwiftUI
import GRDB

struct LibraryView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var artists: [ArtistEntity] = []
    @State private var playlists: [PlaylistEntity] = []
    @State private var albums: [AlbumEntity] = []
    @State private var podcasts: [PodcastEntity] = []
    @State private var likedSongCount = 0
    @State private var isLoading = true
    @State private var selectedFilter: LibraryFilter?
    @State private var showCreateDialog = false
    @State private var playlistToDelete: PlaylistEntity?
    @State private var playlistSongCounts: [String: Int] = [:]
    @State private var playlistMosaics: [String: [String]] = [:]
    @AppStorage("resona.library.viewMode") private var viewMode: LibraryViewMode = .list
    @AppStorage("resona.library.sort") private var sort: LibrarySort = .custom
    @Environment(\.m3) private var m3

    @ObservedObject private var router = AppRouter.shared
    @ObservedObject private var downloadManager = DownloadManager.shared

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let accountState = AccountSheetState.shared

    private var gridColumns: [GridItem] {
        let count = horizontalSizeClass == .regular ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 16), count: count)
    }
    private var autoPlaylists: [AutoPlaylistInfo] {
        [
            AutoPlaylistInfo(id: "liked", title: "Liked Songs", icon: "heart.fill", subtitle: "\(likedSongCount) songs", route: .likedSongs),
            AutoPlaylistInfo(id: "downloads", title: "Downloads", icon: "arrow.down.circle.fill",
                             subtitle: downloadsSubtitle, route: nil, detailRoute: .downloads),
            AutoPlaylistInfo(id: "top100", title: "My Top 100", icon: "trophy.fill", subtitle: "Top 100", route: .topSongs(limit: 100))
        ]
    }

    private var downloadsSubtitle: String {
        downloadManager.persistedDownloadCount == 0
            ? "Offline"
            : "\(downloadManager.persistedDownloadCount) songs"
    }

    enum LibraryFilter: String, CaseIterable {
        case playlists = "Playlists"
        case albums = "Albums"
        case artists = "Artists"
        case podcasts = "Podcasts"

        var icon: String {
            switch self {
            case .playlists: "list.bullet"
            case .albums: "square.stack"
            case .artists: "music.mic"
            case .podcasts: "mic"
            }
        }
    }

    var body: some View {
        NavigationStack(path: $router.libraryPath) {
            VStack(spacing: 0) {
                TabHeaderView(
                    title: "Library",
                    accountIsLoggedIn: accountState.isLoggedIn,
                    accountImageUrl: accountState.accountImageUrl,
                    onHistory: { router.libraryPath.append(DetailRoute.history) },
                    onAccount: { router.libraryPath.append(DetailRoute.settings) }
                )

                Group {
                    if isLoading {
                        librarySkeleton
                    } else {
                        feedContent
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .toolbar(.hidden, for: .navigationBar)
            .detailRouteDestinations()
            .overlay {
                if showCreateDialog {
                    CreatePlaylistDialog(
                        isPresented: $showCreateDialog,
                        onCreated: { await loadContent() }
                    )
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showCreateDialog)
            .task {
                await loadContent()
                await accountState.restoreSession()
                await accountState.fetchAccountInfo()
                Task {
                    await SyncBridge.forceFullSync()
                    await loadContent()
                }
            }
            .task(id: isLoading) {
                guard !isLoading else { return }
                let urls = (playlists.map(\.thumbnailUrl) + albums.map(\.thumbnailUrl) + artists.map(\.thumbnailUrl) + podcasts.map(\.thumbnailUrl))
                    .compactMap { $0 }
                    .compactMap(URL.init)
                await ImagePreloader.shared.preload(urls)
            }
            .refreshable {
                await SyncBridge.forceFullSync()
                await loadContent()
            }
            .destructiveConfirm(
                "Delete Playlist",
                isPresented: .init(
                    get: { playlistToDelete != nil },
                    set: { if !$0 { playlistToDelete = nil } }
                ),
                message: Text("Are you sure you want to delete \"\(playlistToDelete?.name ?? "")\"?"),
                confirmTitle: "Delete"
            ) {
                if let p = playlistToDelete {
                    Task { await deletePlaylist(p) }
                }
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                M3Chip(title: String(localized: "Library"), systemImage: "waveform", isSelected: selectedFilter == nil, height: 48) {
                    withAnimation(M3Motion.defaultSpatial) { selectedFilter = nil }
                }
                ForEach(LibraryFilter.allCases, id: \.self) { filter in
                    M3Chip(title: String(localized: String.LocalizationValue(filter.rawValue)), systemImage: filter.icon, isSelected: selectedFilter == filter, height: 48) {
                        withAnimation(M3Motion.defaultSpatial) {
                            selectedFilter = selectedFilter == filter ? nil : filter
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Feed Content

    @ViewBuilder
    private var feedContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                filterBar
                LibraryControlRow(sort: $sort, viewMode: $viewMode, onCreate: { showCreateDialog = true })
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                switch selectedFilter {
                case .playlists:
                    playlistsSection
                case .albums:
                    if !albums.isEmpty { albumsSection }
                case .artists:
                    if !artists.isEmpty { artistsSection }
                case .podcasts:
                    if !podcasts.isEmpty { podcastsSection }
                case nil:
                    playlistsSection
                    if !albums.isEmpty { albumsSection }
                    if !artists.isEmpty { artistsSection }
                    if !podcasts.isEmpty { podcastsSection }
                }
            }
        }
        .scrollIndicators(.automatic)
        .miniPlayerTracksScroll()
    }

    // MARK: - Playlists (Auto + User)

    private var playlistsSection: some View {
        librarySection(title: "Playlists", count: playlists.count) {
            ForEach(autoPlaylists) { info in
                let link = info.detailRoute ?? info.route.map { DetailRoute.autoPlaylist($0) }
                if let link {
                    NavigationLink(value: link) {
                        entry(
                            artwork: .icon(info.icon),
                            title: String(localized: String.LocalizationValue(info.title)),
                            subtitle: info.subtitle.map { String(localized: String.LocalizationValue($0)) }
                        )
                    }
                    .buttonStyle(.expressive(scale: 0.98))
                }
            }

            ForEach(sortedPlaylists, id: \.id) { playlist in
                NavigationLink(value: DetailRoute.playlist(playlistId: playlist.id)) {
                    entry(
                        artwork: playlistArtwork(playlist),
                        title: playlist.name,
                        subtitle: songCountText(playlistSongCounts[playlist.id] ?? playlist.remoteSongCount),
                        badge: playlist.browseId == nil ? "Personal" : "Synced with YouTube",
                        onPlay: { Task { await play(playlist) } },
                        menuItems: {
                            if playlist.isEditable {
                                Button(role: .destructive) {
                                    playlistToDelete = playlist
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            if let url = URL.playlistShareURL(id: playlist.browseId ?? playlist.id), playlist.browseId != nil {
                                ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                            }
                        }
                    )
                }
                .buttonStyle(.expressive(scale: 0.98))
                .contextMenu {
                    if playlist.isEditable {
                        Button(role: .destructive) {
                            playlistToDelete = playlist
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private var sortedPlaylists: [PlaylistEntity] {
        switch sort {
        case .custom: return playlists
        case .name: return playlists.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .recent: return playlists.sorted { ($0.bookmarkedAt ?? .distantPast) > ($1.bookmarkedAt ?? .distantPast) }
        case .size: return playlists.sorted { (playlistSongCounts[$0.id] ?? 0) > (playlistSongCounts[$1.id] ?? 0) }
        }
    }

    private func playlistArtwork(_ playlist: PlaylistEntity) -> LibraryArtwork {
        if let mosaic = playlistMosaics[playlist.id], mosaic.count >= 4, playlist.browseId == nil || playlist.thumbnailUrl == nil {
            return .mosaic(mosaic)
        }
        if let url = playlist.thumbnailUrl { return .image(url) }
        if let mosaic = playlistMosaics[playlist.id], !mosaic.isEmpty { return .mosaic(mosaic) }
        return .icon("music.note.list")
    }

    private func songCountText(_ count: Int?) -> String? {
        guard let count else { return nil }
        return String(format: NSLocalizedString("%d tracks", comment: "Library song count"), count)
    }

    /// Plays a playlist straight from the library card.
    private func play(_ playlist: PlaylistEntity) async {
        let songs: [SongEntity] = (try? await DatabaseService.shared.fetchAll(
            SongEntity.self,
            sql: "SELECT song.* FROM song JOIN playlist_song_map m ON m.song_id = song.id WHERE m.playlist_id = ? ORDER BY m.position",
            arguments: [playlist.id]
        )) ?? []
        if songs.isEmpty {
            router.libraryPath.append(DetailRoute.playlist(playlistId: playlist.id))
            return
        }
        PlaybackQueue.play(songs.map { SongItem(entity: $0) }, log: Log.libraryView, context: "Library card play")
    }

    /// List-mode card or grid-mode tile, depending on the view mode.
    @ViewBuilder
    private func entry(
        artwork: LibraryArtwork,
        title: String,
        subtitle: String?,
        badge: LocalizedStringKey? = nil,
        onPlay: (() -> Void)? = nil,
        @ViewBuilder menuItems: () -> some View = { EmptyView() }
    ) -> some View {
        let items = menuItems()
        if viewMode == .list {
            LibraryCard(artwork: artwork, title: title, subtitle: subtitle, badge: badge, onPlay: onPlay) {
                Menu {
                    items
                } label: {
                    Image(systemName: "ellipsis")
                        .rotationEffect(.degrees(90))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(m3.onSurface)
                        .frame(width: 36, height: 44)
                        .contentShape(Rectangle())
                }
            }
        } else {
            LibraryGridTile(artwork: artwork, title: title, subtitle: subtitle)
        }
    }

    // MARK: - Artists

    private var artistsSection: some View {
        librarySection(title: "Artists", count: artists.count) {
            ForEach(artists, id: \.id) { artist in
                NavigationLink(value: DetailRoute.artist(browseId: artist.id)) {
                    entry(artwork: .round(artist.thumbnailUrl), title: artist.name, subtitle: String(localized: "Artist"))
                }
                .buttonStyle(.expressive(scale: 0.98))
            }
        }
    }

    // MARK: - Albums

    private var albumsSection: some View {
        librarySection(title: "Albums", count: albums.count) {
            ForEach(albums, id: \.id) { album in
                NavigationLink(value: DetailRoute.album(browseId: album.id)) {
                    entry(artwork: .image(album.thumbnailUrl), title: album.title, subtitle: album.songCount > 0 ? songCountText(album.songCount) : String(localized: "Album"))
                }
                .buttonStyle(.expressive(scale: 0.98))
            }
        }
    }

    // MARK: - Podcasts

    private var podcastsSection: some View {
        librarySection(title: "Podcasts", count: podcasts.count) {
            ForEach(podcasts, id: \.id) { podcast in
                NavigationLink(value: DetailRoute.podcast(browseId: podcast.id)) {
                    entry(artwork: .image(podcast.thumbnailUrl), title: podcast.name, subtitle: String(localized: "Podcast"))
                }
                .buttonStyle(.expressive(scale: 0.98))
            }
        }
    }

    // MARK: - Components

    private func librarySection<Content: View>(
        title: String,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if selectedFilter == nil {
                sectionTitle(title, count: count)
            }

            if viewMode == .list {
                LazyVStack(spacing: 12) {
                    content()
                }
                .padding(.horizontal, 12)
            } else {
                LazyVGrid(columns: gridColumns, spacing: 18) {
                    content()
                }
                .padding(.horizontal, DesignTokens.screenHPadding)
            }
        }
        .padding(.bottom, 20)
    }

    private func sectionTitle(_ title: String, count: Int? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(LocalizedStringKey(title))
                .font(.m3(.titleLarge))
                .foregroundStyle(m3.onSurface)
            Spacer()
            if let count {
                Text("\(count)")
                    .font(.m3(.labelLarge))
                    .foregroundStyle(m3.onSurfaceVariant)
            }
        }
        .padding(.horizontal, DesignTokens.screenHPadding)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func autoPlaylistCell(info: AutoPlaylistInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(autoPlaylistGradient())
                    .aspectRatio(1, contentMode: .fill)
                Image(systemName: info.icon)
                    .font(.largeTitle)
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)

            Text(LocalizedStringKey(info.title))
                .lineLimit(1)
                .font(.callout)
            if let subtitle = info.subtitle {
                Text(LocalizedStringKey(subtitle))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func autoPlaylistGradient() -> LinearGradient {
        let accent = settings.accentColor
        return LinearGradient(
            colors: [accent.opacity(0.55), accent],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func itemCell(url: String?, title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImageView(url: url)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(title).lineLimit(1).font(.callout)
            if let subtitle {
                Text(subtitle).font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private func artistCell(url: String?, name: String) -> some View {
        VStack(spacing: 8) {
            AsyncImageView(url: url)
                .frame(width: 120, height: 120)
                .clipShape(Circle())
            Text(name).lineLimit(1).font(.callout)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Loading Skeleton

    private var librarySkeleton: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ShimmerChips(count: 4, width: 88)

                ForEach(0..<2, id: \.self) { _ in
                    ShimmerSectionTitle(width: 130)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                    LazyVGrid(columns: gridColumns, spacing: 16) {
                        ForEach(0..<6, id: \.self) { _ in
                            VStack(alignment: .leading, spacing: 6) {
                                ShimmerFill(radius: 12)
                                    .aspectRatio(1, contentMode: .fit)
                                ShimmerBlock(width: 110, height: 15, radius: 4)
                                ShimmerBlock(width: 70, height: 12, radius: 4)
                            }
                        }
                    }
                    .padding(.horizontal, DesignTokens.screenHPadding)
                }
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Data Loading

    private func loadContent() async {
        do {
            async let artistsFetch = DatabaseService.shared.fetchAll(
                ArtistEntity.self,
                sql: "SELECT * FROM artist WHERE bookmarked_at IS NOT NULL ORDER BY name LIMIT 50"
            )
            async let playlistsFetch = DatabaseService.shared.fetchAll(
                PlaylistEntity.self,
                sql: "SELECT * FROM playlist WHERE bookmarked_at IS NOT NULL ORDER BY name LIMIT 50"
            )
            async let albumsFetch = DatabaseService.shared.fetchAllAlbums()
            async let podcastsFetch = DatabaseService.shared.fetchAllPodcasts()
            async let countFetch = DatabaseService.shared.fetchAllLikedSongCount()
            artists = try await artistsFetch
            playlists = try await playlistsFetch
            albums = try await albumsFetch
            podcasts = try await podcastsFetch
            likedSongCount = try await countFetch

            let rows: [(String, Int)] = try await DatabaseService.shared.read { db in
                try Row.fetchAll(
                    db,
                    sql: "SELECT playlist_id, COUNT(*) as cnt "
                        + "FROM playlist_song_map "
                        + "WHERE EXISTS (SELECT 1 FROM song WHERE id = song_id) "
                        + "GROUP BY playlist_id"
                )
                .map { ($0["playlist_id"] as String, $0["cnt"] as Int) }
            }
            playlistSongCounts = Dictionary(uniqueKeysWithValues: rows)

            let thumbs: [(String, String)] = try await DatabaseService.shared.read { db in
                try Row.fetchAll(
                    db,
                    sql: "SELECT playlist_id, thumbnail_url FROM ("
                        + "SELECT m.playlist_id, s.thumbnail_url, "
                        + "ROW_NUMBER() OVER (PARTITION BY m.playlist_id ORDER BY m.position) AS rn "
                        + "FROM playlist_song_map m JOIN song s ON s.id = m.song_id "
                        + "WHERE s.thumbnail_url IS NOT NULL) WHERE rn <= 4"
                )
                .map { ($0["playlist_id"] as String, $0["thumbnail_url"] as String) }
            }
            playlistMosaics = Dictionary(grouping: thumbs, by: \.0).mapValues { $0.map(\.1) }

            isLoading = false
        } catch {
            Log.libraryView.error("Failed to load: \(error)")
            isLoading = false
        }
    }

    private func deletePlaylist(_ playlist: PlaylistEntity) async {
        do {
            try await SyncBridge.mutations.deletePlaylist(playlistId: playlist.id)
            await loadContent()
        } catch {
            Log.libraryView.error("Failed to delete playlist: \(error)")
        }
    }
}

// MARK: - Create Playlist Dialog

struct CreatePlaylistDialog: View {
    @Environment(SettingsStore.self) private var settings
    @Binding var isPresented: Bool
    let onCreated: () async -> Void

    @State private var name = ""
    @State private var syncWithYouTube = false
    @State private var isCreating = false
    @State private var error: Error?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text("New Playlist")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.top, 24)
                .padding(.bottom, 20)

            TextField("Playlist name", text: $name)
                .font(.body)
                .focused($isFocused)
                .padding(.horizontal, DesignTokens.screenHPadding)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(.systemGray6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isFocused ? settings.accentColor : Color(.systemGray4), lineWidth: 1)
                )
                .autocorrectionDisabled()
                .padding(.horizontal, 24)
                .padding(.bottom, 20)

            // Sync toggle
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sync playlist")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Syncs with your YouTube Music account. This cannot be changed later.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                Toggle("", isOn: $syncWithYouTube)
                    .labelsHidden()
                    .tint(settings.accentColor)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)

            if let error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption)
                    Text(error.localizedDescription)
                        .font(.caption)
                }
                .foregroundColor(.red)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }

            Divider()
                .padding(.bottom, 4)

            HStack(spacing: 12) {
                                Button(action: { isPresented = false }, label: {
                    Text("Cancel")
                        .font(.body.weight(.medium))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(.systemGray6))
                        )
                })
                .buttonStyle(.plain)

                Button(action: {
                    guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    Task {
                        isCreating = true
                        do {
                            try await createPlaylist()
                            await onCreated()
                            isPresented = false
                        } catch {
                            self.error = error
                        }
                        isCreating = false
                    }
                }, label: {
                    HStack(spacing: 6) {
                        if isCreating {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                        }
                        Text("Create")
                            .font(.body.weight(.semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(name.trimmingCharacters(in: .whitespaces).isEmpty ? settings.accentColor.opacity(0.4) : settings.accentColor)
                    )
                })
                .buttonStyle(.plain)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 30, y: 10)
        .onTapGesture { }
        .onAppear { isFocused = true }
    }

    private func createPlaylist() async throws {
        let title = name.trimmingCharacters(in: .whitespaces)
        if syncWithYouTube {
            _ = try await SyncBridge.mutations.createPlaylist(title: title)
        } else {
            let id = UUID().uuidString
            let entity = PlaylistEntity(
                id: id,
                browseId: nil,
                name: title,
                thumbnailUrl: nil,
                isEditable: true,
                bookmarkedAt: Date(),
                remoteSongCount: 0
            )
            try await DatabaseService.shared.insert(entity)
        }
    }
}

// MARK: - AutoPlaylist Info

struct AutoPlaylistInfo: Identifiable {
    let id: String
    let title: String
    let icon: String
    let subtitle: String?
    let route: AutoPlaylistRoute?
    var detailRoute: DetailRoute?
}
