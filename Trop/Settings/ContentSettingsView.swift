//
//  ContentSettingsView.swift
//  Trop
//
//  Created by 686udjie on 20/08/2026.
//

import SwiftUI

struct ContentSettingsView: View {
    @Environment(\.settingsStore) private var settings

    private static let countries = ["US", "GB", "CA", "AU", "FR", "DE", "ES", "IT", "PT", "JP", "KR", "MX", "BR", "IN"]

    var body: some View {
        @Bindable var settings = settings

        M3Form {
            M3Section {
                SettingsToggleRow("Hide Explicit Content", icon: "eye.slash", isOn: $settings.hideExplicit)
            } header: {
                Text("Content Filtering")
            }

            M3Section {
                SettingsToggleRow("Show Quick Picks", icon: "sparkles", isOn: $settings.showQuickPicks)
                M3SliderRow(
                    value: Binding(
                        get: { Double(settings.topListsLength) },
                        set: { settings.topListsLength = Int($0) }
                    ),
                    range: 4...20,
                    step: 2,
                    format: { "\(Int($0))" }
                ) {
                    Label("Top Lists Length", systemImage: "list.number")
                }
            } header: {
                Text("Home Feed")
            }

            M3Section {
                M3DropdownRow(
                    selection: $settings.contentCountry,
                    options: Self.countries.map { (value: $0, title: countryName(for: $0)) }
                ) {
                    Label("Country", systemImage: "globe")
                }
            } header: {
                Text("Region")
            } footer: {
                Text("Controls the region used for YouTube Music requests.")
            }

            M3Section {
                SettingsToggleRow("Track Search History", icon: "magnifyingglass", isOn: $settings.trackSearchHistory)
                SettingsToggleRow("Track Play History", icon: "clock.arrow.circlepath", isOn: $settings.trackPlayHistory)
            } header: {
                Text("Privacy")
            } footer: {
                Text("When off, searches and playback are not recorded locally.")
            }

            M3Section {
                SettingsToggleRow("Sync Artists", icon: "music.mic", isOn: $settings.syncArtists)
                SettingsToggleRow("Sync Playlists", icon: "music.note.list", isOn: $settings.syncPlaylists)
                SettingsToggleRow("Sync Albums", icon: "square.stack", isOn: $settings.syncAlbums)
                SettingsToggleRow("Sync Podcasts", icon: "antenna.radiowaves.left.and.right", isOn: $settings.syncPodcasts)
                SettingsToggleRow("Sync Liked Songs", icon: "heart.fill", isOn: $settings.syncSongs)
            } header: {
                Text("Library Sync")
            } footer: {
                Text("Choose which library sections sync from your YouTube Music account.")
            }
        }
        .navigationTitle("Content")
        .m3ScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
    }

    private func countryName(for code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }
}
