//
//  LyricsSettingsView.swift
//  Trop
//
//  Created by 686udjie on 20/08/2026.
//

import SwiftUI

struct LyricsSettingsView: View {
    @Environment(\.settingsStore) private var settings
    @Environment(\.m3) private var m3
    @AppStorage(PaxsenixProvider.apiKeyDefaultsKey) private var paxsenixKey = ""

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
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.name)
                                if let note = Self.note(for: provider.id) {
                                    Text(note)
                                        .font(.m3(.bodySmall))
                                        .foregroundStyle(m3.onSurfaceVariant)
                                }
                            }
                        } icon: {
                            Image(systemName: Self.icon(for: provider.id))
                        }
                    }
                }
            } header: {
                Text("Providers")
            } footer: {
                Text("Disabled providers are skipped when fetching lyrics.")
            }

            M3Section {
                HStack(spacing: 12) {
                    Label("API key", systemImage: "key")
                    SecureField(String(localized: "Optional"), text: $paxsenixKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(m3.onSurface)
                }
            } header: {
                Text(verbatim: "Paxsenix")
            } footer: {
                Text("Paxsenix only answers requests with your own API key. Without a key it is skipped.")
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

    /// Short hint under a provider's name.
    static func note(for id: String) -> LocalizedStringKey? {
        switch id {
        case "betterlyrics", "youlyplus": "Word-synced, incl. background vocals"
        case "spotify": "Requires Spotify sign-in"
        case "paxsenix": "Requires an API key (below)"
        case "youtube": "Plain text only (fallback)"
        default: nil
        }
    }

    static func icon(for id: String) -> String {
        switch id {
        case "betterlyrics", "youlyplus": "text.word.spacing"
        case "spotify": "dot.radiowaves.left.and.right"
        case "youtube": "play.rectangle"
        case "paxsenix": "key"
        default: "music.note"
        }
    }
}
