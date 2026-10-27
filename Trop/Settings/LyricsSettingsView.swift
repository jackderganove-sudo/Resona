//
//  LyricsSettingsView.swift
//  Trop
//
//  Created by 686udjie on 20/08/2026.
//

import SwiftUI

struct LyricsSettingsView: View {
    @Environment(\.settingsStore) private var settings

    var body: some View {
        @Bindable var settings = settings

        M3Form {
            M3Section {
                ForEach(LyricsProviderRegistry.all, id: \.id) { provider in
                    Toggle(isOn: Binding(
                        get: { !settings.disabledLyricsProviders.contains(provider.id) },
                        set: { enabled in
                            var disabled = settings.disabledLyricsProviders
                            if enabled {
                                disabled.remove(provider.id)
                            } else {
                                disabled.insert(provider.id)
                            }
                            settings.disabledLyricsProviders = disabled
                        }
                    )) {
                        Label(provider.name, systemImage: "music.note")
                    }
                }
            } header: {
                Text("Providers")
            } footer: {
                Text("Disabled providers are skipped when fetching lyrics.")
            }

            M3Section {
                M3SliderRow(
                    value: $settings.lyricsLineChangeAdjustMs,
                    range: -500...500,
                    step: 50,
                    format: { $0 == 0 ? "0 ms" : String(format: "%+.0f ms", $0) }
                ) {
                    Label("Line change earlier/later", systemImage: "arrow.up.arrow.down")
                }
            } header: {
                Text("Timing")
            } footer: {
                Text("Negative values move to the next line earlier, positive values later. Word highlighting always stays on the timestamps.")
            }

            M3Section {
                NavigationLink {
                    LyricsProviderOrderView()
                } label: {
                    Label("Provider Order", systemImage: "list.number")
                }
            }
        }
        .navigationTitle("Lyrics")
        .m3ScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
    }
}
