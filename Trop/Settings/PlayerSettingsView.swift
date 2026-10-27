//
//  PlayerSettingsView.swift
//  Trop
//
//  Created by 686udjie on 20/08/2026.
//

import SwiftUI

struct PlayerSettingsView: View {
    @Environment(\.settingsStore) private var settings

    var body: some View {
        @Bindable var settings = settings

        M3Form(title: "Playback") {
            M3Section {
                SettingsNavigationRow("Equalizer", icon: "slider.vertical.3") {
                    EqualizerView()
                }
            } header: {
                Text("Equalizer")
            } footer: {
                Text("Adjust the sound with presets or a custom curve.")
            }

            M3Section {
                SettingsPickerRow("Audio Quality", icon: "waveform", selection: $settings.audioQuality)
                SettingsToggleRow("Audio Normalization", icon: "speaker.wave.2", isOn: $settings.audioNormalization)
                SettingsToggleRow("Gapless Playback", icon: "arrow.right.arrow.left", isOn: $settings.gaplessPlayback)
                M3SliderRow(
                    value: $settings.crossfadeSeconds,
                    range: 0...12,
                    step: 1,
                    format: { $0 < 1 ? String(localized: "Off") : "\(Int($0)) s" }
                ) {
                    Label("Crossfade (experimental)", systemImage: "waveform.path")
                }
                M3DropdownRow(
                    selection: $settings.sleepFadeSeconds,
                    options: [(0.0, String(localized: "Off")), (10.0, "10 s"), (30.0, "30 s"), (60.0, "60 s")]
                ) {
                    Label("Sleep timer fade-out", systemImage: "moon.zzz")
                }
            } header: {
                Text("Audio")
            } footer: {
                Text("Crossfade blends the end of a song into the next one. It is skipped when you skip manually, with repeat one, with the sleep timer set to the end of the song, and between songs of the same album while gapless playback is on.")
            }

            M3Section {
                SettingsToggleRow("Autoplay Similar", icon: "infinity", isOn: $settings.autoplaySimilar)
                SettingsToggleRow("Persist Queue", icon: "clock.arrow.circlepath", isOn: $settings.persistQueue)
            } header: {
                Text("Queue")
            } footer: {
                Text("Persist Queue restores your queue, shuffle, and repeat state when the app relaunches.")
            }

            M3Section {
                SettingsToggleRow("Swipe Artwork to Skip", icon: "hand.draw", isOn: $settings.artworkSwipeNavigation)
            } header: {
                Text("Gestures")
            } footer: {
                Text("Swipe left or right on the artwork in the full player to play the next or previous song.")
            }
        }
        .m3ScreenBackground()
        .miniPlayerTracksScroll()
    }
}
