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

    private var storageLabel: String {
        ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file)
    }

    var body: some View {
        @Bindable var settings = settings

        M3Form {
            M3Section {
                storageCard
            }

            M3Section {
                SettingsPickerRow("Download Quality", icon: "waveform", selection: $settings.downloadQuality)
                SettingsToggleRow("Wi-Fi Only", icon: "wifi", isOn: $settings.wifiOnlyDownloads)
                SettingsToggleRow("Auto-Download on Like", icon: "heart.fill", isOn: $settings.autoDownloadOnLike)
                SettingsToggleRow("Auto-Download New Episodes", icon: "antenna.radiowaves.left.and.right", isOn: $settings.autoDownloadNewEpisodes)
            } header: {
                Text("Preferences")
            } footer: {
                Text("Auto-download saves liked songs for offline playback. Wi-Fi Only blocks downloads on cellular data.")
            }
        }
        .navigationTitle("Download Settings")
        .m3ScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
        .task { await refreshStats() }
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

    private func refreshStats() async {
        storageBytes = await downloadManager.totalStorageBytes()
        trackCount = downloadManager.persistedDownloadCount
    }
}
