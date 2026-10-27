//
//  SongMenuSheet.swift
//  Trop
//
//  Created by 686udjie on 26/08/2026.
//

import SwiftUI

struct SongMenuSheet: View {
    let song: SongItem
    var onNavigate: ((DetailRoute) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.settingsStore) private var settings
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var likeStore = LikeStore.shared

    enum Destination: Hashable {
        case details
        case similar
    }

    @State private var pin = PinState()
    @State private var showPlaylistPicker = false
    @State private var showArtistPicker = false
    @State private var showRadioOptions = false
    @State private var isResolvingArtist = false

    private var isLiked: Bool {
        likeStore.isLiked(videoId: song.videoId)
    }
    var body: some View {
        SheetChrome {
            Group {
                headerCard
                actionGrid
                MenuCard {
                    MenuRow(
                        icon: isLiked ? "heart.slash" : "heart",
                        title: isLiked ? "Unlike" : "Like"
                    ) {
                        Task { await likeStore.toggle(song: song) }
                    }
                    M3RowDivider()
                    downloadRow
                }
                MenuCard {
                    MenuRow(
                        icon: "text.insert",
                        title: "Play Next",
                        subtitle: "Add to the queue, next in line"
                    ) { playNext() }
                    M3RowDivider()
                    MenuRow(
                        icon: "list.bullet",
                        title: "Add to Queue",
                        subtitle: "Add to the end of the queue"
                    ) { addToQueue() }
                    M3RowDivider()
                    MenuRow(
                        icon: pin.isPinned ? "pin.fill" : "pin",
                        title: pin.isPinned ? "Unpin from Quick Picks" : "Pin to Quick Picks"
                    ) { Task { await pin.toggle(song: song) } }
                    MenuRow(
                        icon: "music.mic",
                        title: "View Artist",
                        subtitle: song.artistNamesDisplay
                    ) { handleViewArtist() }
                    if let albumId = song.firstAlbumBrowseId {
                        M3RowDivider()
                        MenuRow(
                            icon: "record.circle",
                            title: "View Album",
                            subtitle: song.album
                        ) { navigate(.album(browseId: albumId)) }
                    }
                }
                MenuCard {
                    NavigationLink(value: Destination.details) {
                        MenuRowLabel(
                            icon: "info.circle",
                            title: "Details",
                            subtitle: "Metadata & stream information"
                        )
                    }
                    .buttonStyle(.plain)
                    M3RowDivider()
                    NavigationLink(value: Destination.similar) {
                        MenuRowLabel(
                            icon: "dot.radiowaves.left.and.right",
                            title: "Similar to this song",
                            subtitle: "More like “\(song.title)”"
                        )
                    }
                    .buttonStyle(.plain)
                    M3RowDivider()
                    MenuRow(
                        icon: "slider.horizontal.3",
                        title: "Customize Radio",
                        subtitle: "Style, size & explicit filter"
                    ) { showRadioOptions = true }
                }
            }
            .navigationDestination(for: Destination.self) { dest in
                switch dest {
                case .details:
                    SongDetailsView(song: song)
                case .similar:
                    SimilarSongsView(
                        song: song,
                        onNavigate: onNavigate,
                        onPlaySong: { similar, songs in
                            playSimilarAndExpand(similar, in: songs)
                        }
                    )
                }
            }
        }
        .confirmationDialog("View Artist", isPresented: $showArtistPicker, titleVisibility: .visible) {
            ForEach(song.artists.filter { !$0.name.isEmpty }, id: \.self) { artist in
                Button(artist.name) {
                    openArtist(artist)
                }
            }
        }
        .sheet(isPresented: $showPlaylistPicker) {
            AddSongToPlaylistSheet(song: song)
        }
        .sheet(isPresented: $showRadioOptions) {
            RadioOptionsSheet(song: song)
        }
        .task { await pin.load(videoId: song.videoId) }
    }

    // MARK: - Header

    private var headerCard: some View {
        M3MenuHeaderCard(
            title: song.title,
            subtitle: song.artistNamesDisplay,
            thumbnailURL: song.thumbnailUrl
        )
    }

    // MARK: - Action Grid

    private var actionGrid: some View {
        M3ActionTileGrid(tiles: [
            M3ActionTile(icon: "dot.radiowaves.left.and.right", title: "Start Radio") { startRadio() },
            M3ActionTile(icon: "text.badge.plus", title: "Add to playlist") { showPlaylistPicker = true },
            M3ActionTile(icon: "square.and.arrow.up", title: "Share") { share() }
        ])
    }

    private var downloadRow: some View {
        let state = downloadManager.state(for: song.videoId)
        return Group {
            switch state {
            case .completed:
                MenuRow(icon: "checkmark.circle.fill", title: "Remove Download", destructive: true) {
                    Task { await downloadManager.delete(videoId: song.videoId) }
                }
            case .downloading, .queued:
                MenuRow(icon: "arrow.down.circle", title: "Downloading…") {}
                    .disabled(true)
            case .notStarted, .failed:
                MenuRow(icon: "arrow.down.circle", title: "Download") {
                    Task { await downloadManager.download(song: song) }
                }
            }
        }
    }

    private func actionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(settings.accentColor)
                Text(LocalizedStringKey(label))
                    .font(.caption)
                    .foregroundStyle(.m3OnSurface)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - State

    // MARK: - Actions

    private func startRadio() {
        PlaybackQueue.startRadio(for: song)
        dismiss()
    }

    private func playNext() {
        let np = NowPlaying.shared
        let insertIndex = min(np.queueIndex + 1, np.queueSongs.count)
        np.queueSongs.insert(song, at: insertIndex)
        np.repairQueueIndex()
        np.persistQueueState()
        dismiss()
    }

    private func addToQueue() {
        let np = NowPlaying.shared
        np.queueSongs.append(song)
        np.persistQueueState()
        dismiss()
    }

    private func share() {
        presentShareSheet(items: [song.webUrl], afterDismiss: { dismiss() })
    }

    private func navigate(_ route: DetailRoute) {
        dismiss()
        onNavigate?(route)
    }

    private func playSimilarAndExpand(_ similar: SongItem, in songs: [SongItem]) {
        dismiss()
        PlaybackQueue.play(similar, in: songs, log: Log.search, context: "SimilarTo tap")
        AppRouter.shared.expandPlayer()
    }

    private func handleViewArtist() {
        guard !isResolvingArtist else { return }
        let namedArtists = song.artists.filter { !$0.name.isEmpty }
        if namedArtists.count > 1 {
            showArtistPicker = true
            return
        }
        guard let artist = namedArtists.first else { return }
        openArtist(artist)
    }

    private func openArtist(_ artist: YTArtist) {
        if let id = artist.id {
            navigate(.artist(browseId: id))
            return
        }
        resolveArtistByName(artist.name)
    }

    private func resolveArtistByName(_ name: String) {
        guard !name.isEmpty else { return }
        isResolvingArtist = true
        Task {
            defer { isResolvingArtist = false }
            var browseId: String?
            do {
                let json = try await SearchService.shared.search(query: name)
                let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                browseId = SearchParser.parseSearchResults(from: json)
                    .flatMap(\.items)
                    .compactMap { item -> (String, String)? in
                        if case .artist(let artist) = item { return (artist.name, artist.browseId) }
                        return nil
                    }
                    .first {
                        $0.0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == wanted
                    }?.1
            } catch {
                browseId = nil
            }
            if let browseId {
                navigate(.artist(browseId: browseId))
            }
        }
    }
}
