//
//  PlaylistMoreSheet.swift
//  Trop
//
//  Created by 686udjie on 28/08/2026.
//

import SwiftUI

struct PlaylistMoreSheet: View {
    let playlist: PlaylistDetailInfo
    var onSync: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var showEditAlert = false
    @State private var editedName = ""
    @State private var showSplit = false
    @State private var showDuplicates = false
    @State private var saving = false
    @State private var saved = false

    var body: some View {
        SheetChrome {
            MenuCard {
                MenuRow(
                    icon: "pencil",
                    title: "Edit",
                    subtitle: "Edit playlist"
                ) {
                    editedName = playlist.title
                    showEditAlert = true
                }
                Divider()
                MenuRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Sync",
                    subtitle: "Sync this playlist with YouTube Music"
                ) {
                    onSync?()
                    dismiss()
                }
                Divider()
                if playlist.playlistId.isEmpty {
                    // Automatic playlists: keep them as a real playlist.
                    MenuRow(
                        icon: saved ? "checkmark.circle" : "square.and.arrow.down.on.square",
                        title: saved ? "Saved to YouTube Music" : (saving ? "Saving…" : "Save to YouTube Music"),
                        subtitle: "Create a playlist with these songs in your account"
                    ) {
                        guard !saving, !saved else { return }
                        saving = true
                        Task {
                            _ = try? await PlaylistTools.saveToYouTubeMusic(title: playlist.title, songs: playlist.songs)
                            saving = false
                            saved = true
                        }
                    }
                    Divider()
                } else {
                    MenuRow(
                        icon: "doc.on.doc",
                        title: "Remove duplicates",
                        subtitle: "Find songs that are in this playlist twice"
                    ) {
                        showDuplicates = true
                    }
                    Divider()
                }
                if playlist.songs.count >= 6 {
                    MenuRow(
                        icon: "rectangle.split.3x1",
                        title: "Split playlist",
                        subtitle: "Split into several new playlists"
                    ) {
                        showSplit = true
                    }
                    Divider()
                }
                MenuRow(
                    icon: "list.bullet",
                    title: "Add to Queue",
                    subtitle: "Add to the end of the queue"
                ) {
                    addToQueue()
                    dismiss()
                }
                Divider()
                MenuRow(
                    icon: "square.and.arrow.up",
                    title: "Share",
                    subtitle: "Share this playlist with others"
                ) {
                    share()
                    dismiss()
                }
                Divider()
                MenuRow(
                    icon: "trash",
                    title: "Delete",
                    subtitle: "Remove all downloads",
                    destructive: true
                ) {
                    deleteAllDownloads()
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showSplit) {
            PlaylistSplitSheet(playlist: playlist)
        }
        .sheet(isPresented: $showDuplicates) {
            PlaylistDuplicatesSheet(playlist: playlist) { onSync?() }
        }
        .textPrompt(
            "Rename Playlist",
            isPresented: $showEditAlert,
            placeholder: "Playlist name",
            text: $editedName,
            okTitle: "Rename",
            onOK: renamePlaylist
        )
    }

    // MARK: - Actions

    private func renamePlaylist() {
        let name = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != playlist.title else { return }
        Task {
            try? await SyncBridge.mutations.renamePlaylist(
                playlistId: playlist.playlistId,
                newName: name
            )
        }
    }

    private func addToQueue() {
        let np = NowPlaying.shared
        np.queueSongs.append(contentsOf: playlist.songs)
        np.persistQueueState()
    }

    private func downloadAll() {
        DownloadManager.shared.enqueue(playlist.songs)
    }

    private func share() {
        guard let url = URL.playlistShareURL(id: playlist.playlistId) else { return }
        presentShareSheet(items: [url])
        dismiss()
    }

    private func deleteAllDownloads() {
        let ids = playlist.songs.map(\.videoId)
        Task { await DownloadManager.shared.delete(videoIds: ids) }
    }
}
