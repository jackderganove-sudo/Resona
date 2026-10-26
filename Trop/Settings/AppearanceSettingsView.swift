//
//  AppearanceSettingsView.swift
//  Trop
//
//  Created by 686udjie on 20/08/2026.
//

import SwiftUI

struct AppearanceSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.m3) private var m3

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 6)

    var body: some View {
        @Bindable var settings = settings

        M3Form {
            M3Section {
                SettingsPickerRow("Theme Mode", icon: "sun.max", selection: $settings.themeMode)
            } header: {
                Text("Theme")
            } footer: {
                Text("Choose how the app follows your device appearance.")
            }

            M3Section {
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

            M3Section {
                SettingsPickerRow("Player Background", icon: "photo", selection: $settings.playerBackgroundStyle)
            } header: {
                Text("Player")
            }

            M3Section {
                SettingsPickerRow("Lyrics Alignment", icon: settings.lyricsAlignment.iconName, selection: $settings.lyricsAlignment)
                M3SliderRow(
                    value: $settings.lyricsFontSize,
                    range: 16...44,
                    step: 1,
                    format: { "\(Int($0)) pt" }
                ) {
                    Label("Lyrics Font Size", systemImage: "textformat.size")
                } preview: {
                    // Live preview in the karaoke style of the player.
                    Text("Sing it loud")
                        .font(.system(size: settings.lyricsFontSize, weight: .bold))
                        .foregroundStyle(m3.onSurface)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity, alignment: settings.lyricsAlignment.textAlignment)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .background(m3.surfaceContainerHighest, in: RoundedRectangle(cornerRadius: M3Shape.large, style: .continuous))
                        .animation(M3Motion.fastSpatial, value: settings.lyricsFontSize)
                }
            } header: {
                Text("Lyrics")
            }

            M3Section {
                M3DropdownRow(
                    selection: $settings.defaultTab,
                    options: ResonaTab.ordered.map { (value: $0.rawValue, title: $0.plainTitle) }
                ) {
                    Label("Default Tab", systemImage: "square.grid.2x2")
                }
            } header: {
                Text("General")
            }
        }
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
