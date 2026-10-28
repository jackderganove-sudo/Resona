//
//  DownloadSettingsView.swift
//  Trop
//

import SwiftUI

struct DownloadSettingsView: View {
    @Environment(\.settingsStore) private var settings
    @Environment(\.m3) private var m3
    @ObservedObject private var downloadManager = DownloadManager.shared
    @State private var storageBytes: Int64 = 0
    @State private var trackCount = 0
    @State private var cacheSizes: [StorageMaintenance.Area: Int64?] = [:]
    @State private var confirmDeleteAll = false

    private var storageLabel: String {
        ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file)
    }

    var body: some View {
        @Bindable var settings = settings

        M3Form(title: "Download Settings") {
            M3Section {
                storageCard
            }

            M3Section {
                SettingsPickerRow("Download Quality", icon: "waveform", selection: $settings.downloadQuality)
                SettingsToggleRow("Wi-Fi Only", icon: "wifi", isOn: $settings.wifiOnlyDownloads)
                SettingsToggleRow("Auto-Download on Like", icon: "heart.fill", isOn: $settings.autoDownloadOnLike)
                SettingsToggleRow("Auto-Download New Episodes", icon: "antenna.radiowaves.left.and.right", isOn: $settings.autoDownloadNewEpisodes)
                SettingsToggleRow("Remove songs deleted from playlists", icon: "minus.circle", isOn: $settings.removeDeletedPlaylistSongs)
                SettingsToggleRow("Smart downloads", icon: "sparkles", isOn: $settings.smartDownloadsEnabled)
                if settings.smartDownloadsEnabled {
                    M3DropdownRow(
                        selection: $settings.smartDownloadsLimitGB,
                        options: [(1.0, "1 GB"), (2.0, "2 GB"), (5.0, "5 GB"), (10.0, "10 GB")]
                    ) {
                        Label("Smart download limit", systemImage: "externaldrive")
                    }
                }
            } header: {
                Text("Preferences")
            } footer: {
                Text("Auto-download saves liked songs for offline playback. Wi-Fi Only blocks downloads on cellular data. Downloaded playlists are checked for new songs when you open the app (at most every 4 hours); other playlists are never downloaded automatically. Smart downloads (off by default) keep your most played songs of the last 30 days and your liked songs offline on Wi-Fi up to the limit; songs you downloaded yourself are never removed automatically.")
            }

            M3Section {
                ForEach(StorageMaintenance.Area.allCases) { area in
                    HStack(spacing: 12) {
                        Label(Self.title(area), systemImage: Self.icon(area))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(cacheSizes[area].flatMap { $0 }.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? String(localized: "In memory"))
                            .font(.m3(.bodyMedium))
                            .foregroundStyle(m3.onSurfaceVariant)
                        Button("Clear") {
                            Task {
                                await StorageMaintenance.clear(area)
                                await refreshCacheSizes()
                            }
                        }
                        .buttonStyle(.m3Tonal)
                    }
                }
            } header: {
                Text("Cache")
            } footer: {
                Text("Clearing caches never touches your downloads; images and lyrics are loaded again when needed.")
            }

            M3Section {
                Button(role: .destructive) {
                    confirmDeleteAll = true
                } label: {
                    Label("Delete all downloads", systemImage: "trash")
                        .foregroundStyle(m3.error)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .disabled(downloadManager.tracks.isEmpty)
            }
        }
        .m3ScreenBackground()
        .miniPlayerTracksScroll()
        .task {
            await refreshStats()
            await refreshCacheSizes()
        }
        .onChange(of: settings.smartDownloadsEnabled) { _, enabled in
            if enabled { SmartDownloads.shared.refreshIfDue(force: true) }
        }
        .onChange(of: settings.smartDownloadsLimitGB) { _, _ in
            SmartDownloads.shared.refreshIfDue(force: true)
        }
        .confirmationDialog("Delete all downloads?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Delete all downloads", role: .destructive) {
                Task {
                    await StorageMaintenance.deleteAllDownloads()
                    await refreshStats()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All downloaded songs are removed from this device. They stay in your library and stream again when online.")
        }
        .onChange(of: downloadManager.persistedDownloadCount) { _, _ in
            Task { await refreshStats() }
        }
    }

    private var storageCard: some View {
        HStack(spacing: 16) {
            M3IconCircle(size: 48) { Image(systemName: "internaldrive") }
            VStack(alignment: .leading, spacing: 2) {
                Text(storageLabel)
                    .font(.m3(.headlineSmall, weight: .medium))
                    .foregroundStyle(m3.onSurface)
                    .contentTransition(.numericText())
                Text(L10n.offlineTracks(trackCount))
                    .font(.m3(.bodyMedium))
                    .foregroundStyle(m3.onSurfaceVariant)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    private func refreshCacheSizes() async {
        var sizes: [StorageMaintenance.Area: Int64?] = [:]
        for area in StorageMaintenance.Area.allCases {
            sizes[area] = await StorageMaintenance.size(of: area)
        }
        cacheSizes = sizes
    }

    private static func title(_ area: StorageMaintenance.Area) -> LocalizedStringKey {
        switch area {
        case .images: "Images"
        case .lyrics: "Lyrics"
        case .streams: "Streams & Canvas"
        }
    }

    private static func icon(_ area: StorageMaintenance.Area) -> String {
        switch area {
        case .images: "photo"
        case .lyrics: "quote.bubble"
        case .streams: "dot.radiowaves.left.and.right"
        }
    }

    private func refreshStats() async {
        storageBytes = await downloadManager.totalStorageBytes()
        trackCount = downloadManager.persistedDownloadCount
    }
}
