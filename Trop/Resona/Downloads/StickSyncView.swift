//
//  StickSyncView.swift
//  Resona
//
//  Settings → Downloads → PS5 stick (preview, developer mode only until the
//  PS5 cover test): pick the stick in the Files picker, choose playlists,
//  sync by hand. Same layout and manifest as Resona-Android.
//

import GRDB
import SwiftUI
import UniformTypeIdentifiers

struct StickSyncView: View {
    @Environment(\.m3) private var m3
    @State private var playlists: [(id: String, name: String)] = []
    @State private var selected = StickSync.shared.selectedPlaylists
    @State private var stickName = StickSync.shared.stickURL?.lastPathComponent
    @State private var picking = false
    @State private var running = false
    @State private var progress = (0, 0)
    @State private var result: String?
    @State private var confirmDrop = false

    var body: some View {
        M3Form(title: "PS5 stick") {
            M3Section {
                Button {
                    picking = true
                } label: {
                    HStack {
                        Label("Stick", systemImage: "externaldrive")
                            .foregroundStyle(m3.onSurface)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(stickName ?? String(localized: "Choose…"))
                            .foregroundStyle(m3.onSurfaceVariant)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(M3RowPressStyle())
            } footer: {
                Text("Choose the top folder of the USB stick. Songs go to Music/<Playlist>/ as .m4a with title, artist, album, track number and cover, the same as Resona for Android. Only files Resona put there are moved or deleted.")
            }

            M3Section {
                ForEach(playlists, id: \.id) { playlist in
                    SettingsToggleRow(playlist.name, isOn: Binding(
                        get: { selected.contains(playlist.id) },
                        set: { on in
                            if on { selected.insert(playlist.id) } else { selected.remove(playlist.id) }
                            StickSync.shared.selectedPlaylists = selected
                        }
                    ))
                }
            } header: {
                Text("Playlists")
            } footer: {
                Text("Only downloaded songs are copied; download the playlists first.")
            }

            M3Section {
                Button {
                    start(allowDrop: false)
                } label: {
                    Label(running ? "Syncing \(progress.0)/\(progress.1)…" : "Sync now", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .disabled(running || stickName == nil)
                Button(role: .destructive) {
                    confirmDrop = true
                } label: {
                    Label("Sync and remove playlists no longer chosen", systemImage: "folder.badge.minus")
                        .foregroundStyle(m3.error)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .disabled(running || stickName == nil)
            } footer: {
                if let result { Text(result) }
            }
        }
        .m3ScreenBackground()
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { picked in
            if case .success(let url) = picked {
                StickSync.shared.remember(stick: url)
                stickName = StickSync.shared.stickURL?.lastPathComponent
            }
        }
        .confirmationDialog("Remove playlists from the stick?", isPresented: $confirmDrop, titleVisibility: .visible) {
            Button("Sync and remove", role: .destructive) { start(allowDrop: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Folders of playlists that are no longer chosen are deleted from the stick (only files Resona copied).")
        }
        .task {
            playlists = (try? await DatabaseService.shared.read { db in
                try Row.fetchAll(db, sql: "SELECT id, name FROM playlist ORDER BY name COLLATE NOCASE")
                    .map { (id: $0["id"] as String, name: $0["name"] as String) }
            }) ?? []
        }
    }

    private func start(allowDrop: Bool) {
        running = true
        result = nil
        Task {
            do {
                let done = try await StickSync.shared.sync(allowDrop: allowDrop) { done, total in
                    Task { @MainActor in progress = (done, total) }
                }
                result = String(localized: "\(done.copied) songs copied, \(done.missing) not downloaded.")
            } catch {
                result = error.localizedDescription
            }
            running = false
        }
    }
}
