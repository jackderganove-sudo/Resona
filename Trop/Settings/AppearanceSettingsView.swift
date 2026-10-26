//
//  AppearanceSettingsView.swift
//  Trop
//
//  Created by 686udjie on 20/08/2026.
//

import SwiftUI

struct AppearanceSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 6)

    var body: some View {
        @Bindable var settings = settings

        List {
            Section {
                SettingsPickerRow("Theme Mode", icon: "sun.max", selection: $settings.themeMode)
            } header: {
                Text("Theme")
            } footer: {
                Text("Choose how the app follows your device appearance.")
            }

            Section {
                Toggle(isOn: Binding(
                    get: { ThemeStore.shared.dynamicColor },
                    set: { ThemeStore.shared.dynamicColor = $0 }
                )) {
                    Label("Colors from artwork", systemImage: "paintpalette")
                }
                Toggle(isOn: Binding(
                    get: { ThemeStore.shared.pureBlack },
                    set: { ThemeStore.shared.pureBlack = $0 }
                )) {
                    Label("Pure black", systemImage: "circle.lefthalf.filled")
                }
            } header: {
                Text("Dynamic color")
            } footer: {
                Text("The whole app takes its colors from the current album cover.")
            }

            Section {
                SettingsPickerRow("Player Background", icon: "photo", selection: $settings.playerBackgroundStyle)
            } header: {
                Text("Player")
            }

            Section {
                SettingsPickerRow("Lyrics Alignment", icon: settings.lyricsAlignment.iconName, selection: $settings.lyricsAlignment)
                Stepper(value: $settings.lyricsFontSize, in: 16...44) {
                    HStack(spacing: 0) {
                        Label("Lyrics Font Size", systemImage: "textformat.size")
                        Text(": \(Int(settings.lyricsFontSize))")
                    }
                }
            } header: {
                Text("Lyrics")
            }

            Section {
                Picker("Default Tab", selection: $settings.defaultTab) {
                    Text("Home").tag(0)
                    Text("Library").tag(1)
                    Text("Explore").tag(2)
                    Text("Search").tag(3)
                }
            } header: {
                Text("General")
            }
        }
        .id(settings.accentName)
        .tint(settings.accentColor)
        .navigationTitle("Appearance")
        .m3ScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
    }

    /// Applies the selected accent and selects its bundled alternate app icon.
    private func applyAppIcon(for preset: AccentPreset) {
        settings.accentName = preset.name

        guard UIApplication.shared.supportsAlternateIcons else { return }
        let target = preset.alternateIconName
        guard UIApplication.shared.alternateIconName != target else { return }

        UIApplication.shared.setAlternateIconName(target) { error in
            if let error {
                Log.settings.error("Failed to set alternate icon '\(target ?? "nil")': \(error)")
            }
        }
    }
}
