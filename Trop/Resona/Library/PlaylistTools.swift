//
//  PlaylistTools.swift
//  Resona
//
//  Playlist tools from the playlist "…" menu:
//  • Save any song list (e.g. automatic playlists) as a YouTube Music
//    playlist in the account.
//  • Find duplicates in a synced playlist (same video id, or same title +
//    main artist) and remove the extra entries.
//  • Split a playlist into several new ones. YouTube Music exposes no
//    genre/mood/tempo per song, so grouping uses main artist, album,
//    (detected) language — and genre/mood from Last.fm tags when an API
//    key is available or Last.fm is connected (LastFMTags.swift). Groups
//    can be renamed, songs moved between groups by drag & drop (or the
//    context menu), then "Create" makes them real playlists.
//

import GRDB
import NaturalLanguage
import SwiftUI

enum PlaylistTools {
    /// Creates a YouTube Music playlist and adds the songs in order.
    @discardableResult
    static func saveToYouTubeMusic(title: String, songs: [SongItem]) async throws -> String {
        let id = try await SyncBridge.mutations.createPlaylist(title: title)
        for song in songs {
            try? await SyncBridge.mutations.addToPlaylist(playlistId: id, songId: song.videoId)
        }
        return id
    }

    struct Duplicate: Identifiable {
        let id = UUID()
        let songId: String
        let title: String
        let setVideoId: String
    }

    /// Extra entries (all but the first occurrence) of a synced playlist.
    static func duplicates(in playlistId: String) async -> [Duplicate] {
        let maps = (try? await DatabaseService.shared.fetchAll(
            PlaylistSongMap.self,
            sql: "SELECT * FROM playlist_song_map WHERE playlist_id = ? ORDER BY position",
            arguments: [playlistId]
        )) ?? []
        let songs = (try? await DatabaseService.shared.fetchAll(
            SongEntity.self,
            sql: "SELECT song.* FROM song JOIN playlist_song_map m ON m.song_id = song.id WHERE m.playlist_id = ?",
            arguments: [playlistId]
        )) ?? []
        let byId = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func key(_ songId: String) -> String {
            guard let song = byId[songId] else { return songId }
            let item = SongItem(entity: song)
            let artist = item.artists.first?.name ?? ""
            return (item.title + "|" + artist).lowercased().filter { $0.isLetter || $0.isNumber || $0 == "|" }
        }
        var seen = Set<String>()
        var result: [Duplicate] = []
        for map in maps {
            let k = key(map.songId)
            if seen.contains(k) {
                if let setVideoId = map.setVideoId {
                    result.append(Duplicate(songId: map.songId, title: byId[map.songId].map { SongItem(entity: $0).title } ?? map.songId, setVideoId: setVideoId))
                }
            } else {
                seen.insert(k)
            }
        }
        return result
    }

    /// Buckets songs by `key` (order of first appearance). Groups with
    /// fewer than 3 songs are merged into "More"; at most 7 named groups,
    /// biggest first.
    static func splitGroups(_ songs: [SongItem], title: String, key: (SongItem) -> String) -> [(name: String, songs: [SongItem])] {
        var buckets: [String: [SongItem]] = [:]
        var order: [String] = []
        for song in songs {
            let k = key(song)
            if buckets[k] == nil { order.append(k) }
            buckets[k, default: []].append(song)
        }
        let big = order.filter { (buckets[$0]?.count ?? 0) >= 3 }
            .sorted { (buckets[$0]?.count ?? 0) > (buckets[$1]?.count ?? 0) }
        let kept = Array(big.prefix(7))
        var result = kept.map { (name: "\(title) – \($0)", songs: buckets[$0] ?? []) }
        let rest = order.filter { !kept.contains($0) }.flatMap { buckets[$0] ?? [] }
        if !rest.isEmpty {
            result.append((name: "\(title) – " + String(localized: "More"), songs: rest))
        }
        return result
    }

    static func remove(_ duplicates: [Duplicate], from playlistId: String) async {
        for duplicate in duplicates {
            try? await SyncBridge.mutations.removeFromPlaylist(playlistId: playlistId, songId: duplicate.songId, setVideoId: duplicate.setVideoId)
        }
    }
}

// MARK: - Duplicates sheet

struct PlaylistDuplicatesSheet: View {
    let playlist: PlaylistDetailInfo
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.m3) private var m3
    @State private var duplicates: [PlaylistTools.Duplicate]?
    @State private var working = false

    var body: some View {
        NavigationStack {
            Group {
                if let duplicates {
                    if duplicates.isEmpty {
                        ContentUnavailableView("No duplicates", systemImage: "checkmark.circle", description: Text("Every song is in this playlist only once."))
                    } else {
                        List(duplicates) { duplicate in
                            Label(duplicate.title, systemImage: "doc.on.doc")
                        }
                        .scrollContentBackground(.hidden)
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Duplicates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if let duplicates, !duplicates.isEmpty {
                        Button(working ? String(localized: "Removing…") : String(localized: "Remove \(duplicates.count)")) {
                            working = true
                            Task {
                                await PlaylistTools.remove(duplicates, from: playlist.playlistId)
                                onDone()
                                dismiss()
                            }
                        }
                        .disabled(working)
                    }
                }
            }
        }
        .presentationBackground { ResonaGlassBackground() }
        .task { duplicates = await PlaylistTools.duplicates(in: playlist.playlistId) }
    }
}

// MARK: - Split sheet

struct PlaylistSplitSheet: View {
    let playlist: PlaylistDetailInfo
    @Environment(\.dismiss) private var dismiss
    @Environment(\.m3) private var m3

    enum Strategy: String, CaseIterable, Identifiable {
        case artist, album, language, genre
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .artist: "Artist"
            case .album: "Album"
            case .language: "Language"
            case .genre: "Genre/Mood"
            }
        }
    }

    struct SplitGroup: Identifiable {
        let id = UUID()
        var name: String
        var songs: [SongItem]
    }

    @State private var strategy: Strategy = .artist
    @State private var groups: [SplitGroup] = []
    @State private var creating = false
    @State private var created = 0
    /// Genre/mood group per video id (Last.fm), loaded on first use.
    @State private var genreKeys: [String: String]?
    @State private var genreProgress = 0
    @State private var genreTask: Task<Void, Never>?
    private var genreAvailable: Bool { LastFMTagService.isAvailable }

    private var strategies: [Strategy] {
        genreAvailable ? Strategy.allCases : Strategy.allCases.filter { $0 != .genre }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Group by", selection: $strategy) {
                        ForEach(strategies) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Text(genreAvailable
                         ? LocalizedStringKey("Genre and mood come from Last.fm tags (YouTube Music has none). Rename groups, drag songs between them, then create the playlists.")
                         : LocalizedStringKey("YouTube Music provides no genre or mood per song, so songs are grouped by artist, album or language. Rename groups, drag songs between them, then create the playlists."))
                        .font(.m3(.bodySmall))
                        .foregroundStyle(m3.onSurfaceVariant)

                    if strategy == .genre, genreKeys == nil {
                        VStack(spacing: 10) {
                            ProgressView(value: Double(genreProgress), total: Double(max(1, playlist.songs.count)))
                                .tint(m3.primary)
                            Text(String(format: String(localized: "Loading Last.fm tags… %d/%d"), genreProgress, playlist.songs.count))
                                .font(.m3(.labelMedium))
                                .foregroundStyle(m3.onSurfaceVariant)
                        }
                        .padding(.vertical, 24)
                    } else {
                        ForEach($groups) { $group in
                            groupCard($group)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Split playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(creating ? String(localized: "Creating \(created)/\(groups.filter { !$0.songs.isEmpty }.count)…") : String(localized: "Create")) {
                        create()
                    }
                    .disabled(creating || groups.allSatisfy(\.songs.isEmpty) || (strategy == .genre && genreKeys == nil))
                }
            }
        }
        .presentationBackground { ResonaGlassBackground() }
        .onAppear { regroup() }
        .onChange(of: strategy) { _, _ in regroup() }
        .onDisappear { genreTask?.cancel() }
    }

    private func groupCard(_ group: Binding<SplitGroup>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Playlist name", text: group.name)
                .font(.m3(.titleMedium, weight: .medium))
                .foregroundStyle(m3.onSurface)
            Text(String(format: String(localized: "%d songs"), group.wrappedValue.songs.count))
                .font(.m3(.labelMedium))
                .foregroundStyle(m3.onSurfaceVariant)
            ForEach(group.wrappedValue.songs, id: \.videoId) { song in
                HStack(spacing: 10) {
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(m3.onSurfaceVariant)
                    Text(song.title)
                        .font(.m3(.bodyMedium))
                        .foregroundStyle(m3.onSurface)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .draggable(song.videoId)
                .contextMenu {
                    ForEach(groups.filter { $0.id != group.wrappedValue.id }) { target in
                        Button(target.name) { move(song.videoId, to: target.id) }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(m3.surfaceContainerHighest, in: RoundedRectangle(cornerRadius: M3Shape.large, style: .continuous))
        .dropDestination(for: String.self) { ids, _ in
            for id in ids { move(id, to: group.wrappedValue.id) }
            return !ids.isEmpty
        }
    }

    private func move(_ videoId: String, to groupId: UUID) {
        guard let fromIndex = groups.firstIndex(where: { $0.songs.contains { $0.videoId == videoId } }),
              let toIndex = groups.firstIndex(where: { $0.id == groupId }), fromIndex != toIndex,
              let song = groups[fromIndex].songs.first(where: { $0.videoId == videoId }) else { return }
        withAnimation(M3Motion.defaultSpatial) {
            groups[fromIndex].songs.removeAll { $0.videoId == videoId }
            groups[toIndex].songs.append(song)
        }
    }

    private func regroup() {
        let key: (SongItem) -> String
        switch strategy {
        case .artist:
            key = { $0.artists.first?.name ?? String(localized: "Unknown artist") }
        case .album:
            key = { ($0.album?.isEmpty == false ? $0.album : nil) ?? String(localized: "Singles") }
        case .language:
            key = { song in
                let recognizer = NLLanguageRecognizer()
                recognizer.processString(song.title)
                let code = recognizer.dominantLanguage?.rawValue ?? "und"
                return Locale.current.localizedString(forLanguageCode: code) ?? String(localized: "Other")
            }
        case .genre:
            guard let keys = genreKeys else {
                loadGenres()
                return
            }
            key = { keys[$0.videoId] ?? String(localized: "Other") }
        }
        groups = PlaylistTools.splitGroups(playlist.songs, title: playlist.title, key: key)
            .map { SplitGroup(name: $0.name, songs: $0.songs) }
    }

    private func loadGenres() {
        guard genreTask == nil else { return }
        let songs = playlist.songs
        genreTask = Task {
            let keys = await LastFMTagService.shared.groups(for: songs) { done in
                await MainActor.run { genreProgress = done }
            }
            guard !Task.isCancelled else { return }
            genreKeys = keys
            genreTask = nil
            if strategy == .genre { regroup() }
        }
    }

    private func create() {
        creating = true
        created = 0
        let toCreate = groups.filter { !$0.songs.isEmpty }
        Task {
            for group in toCreate {
                _ = try? await PlaylistTools.saveToYouTubeMusic(title: group.name, songs: group.songs)
                created += 1
            }
            creating = false
            dismiss()
        }
    }
}
