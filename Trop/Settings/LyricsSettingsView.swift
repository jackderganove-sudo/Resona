//
//  LyricsSettingsView.swift
//  Trop
//
//  Created by 686udjie on 20/08/2026.
//

import SwiftUI
import UIKit

struct LyricsSettingsView: View {
    @Environment(\.settingsStore) private var settings
    @Environment(\.m3) private var m3
    @AppStorage(PaxsenixProvider.apiKeyDefaultsKey) private var paxsenixKey = ""
    @Bindable private var debug = LyricsDebugOptions.shared
    /// Unlocked by tapping the version 7× in Settings → About.
    @AppStorage("resona.developerMode") private var developerMode = false

    var body: some View {
        @Bindable var settings = settings

        M3Form(title: "Lyrics") {
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
                SettingsPickerRow("Animation", icon: "sparkles", selection: $settings.lyricsAnimationStyle)
                SettingsPickerRow("Translation", icon: "character.bubble", selection: $settings.lyricsTranslationMode)
                SettingsToggleRow("Show romanization", icon: "globe", isOn: $settings.romanizeCurrentTrack)
            } header: {
                Text("Display")
            } footer: {
                Text("Lyrics in other languages are translated into German on the device (Apple Translation); translations from the lyrics source (e.g. Better Lyrics, YouLyPlus) are preferred. \"On request\": switch it on per song in the lyrics menu.")
            }

            M3Section {
                if SpotifyAccountStore.shared.isLoggedIn {
                    Label("Spotify account connected", systemImage: "checkmark.circle")
                } else {
                    SettingsNavigationRow("Sign in to Spotify", icon: "person.crop.circle.badge.plus") {
                        CanvasSettingsView()
                    }
                }
            } header: {
                Text(verbatim: "Spotify")
            } footer: {
                Text("Spotify lyrics use the same sign-in as Spotify Canvas. Without it Spotify is skipped.")
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
                HStack(spacing: 10) {
                    // Free "Starter" plan: sign in with GitHub on the
                    // Paxsenix dashboard (api.paxsenix.org/pricing →
                    // "Get started" leads to this login page).
                    Link(destination: URL(string: "https://api.paxsenix.org/login")!) {
                        Label("Get API key", systemImage: "arrow.up.right.square")
                            .labelStyle(.titleAndIcon)
                            .font(.m3(.labelLarge, weight: .medium))
                    }
                    .buttonStyle(.m3Tonal)
                    Button {
                        if let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                            paxsenixKey = text
                        }
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                            .labelStyle(.titleAndIcon)
                            .font(.m3(.labelLarge, weight: .medium))
                    }
                    .buttonStyle(.m3Outlined)
                    Spacer(minLength: 0)
                }
            } header: {
                Text(verbatim: "Paxsenix")
            } footer: {
                Text("Paxsenix only answers requests with your own API key; without one it is skipped. Get a key for free: sign in with GitHub on the Paxsenix website (free Starter plan, 1,000 requests a day), create a key in the dashboard, copy it and tap Paste.")
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

            if developerMode {
            M3Section {
                SettingsToggleRow("Blur off", icon: "drop", isOn: $debug.blurOff)
                SettingsToggleRow("Glow off", icon: "sun.max", isOn: $debug.glowOff)
                SettingsToggleRow("Word growth off", icon: "textformat.size.larger", isOn: $debug.growthOff)
                SettingsToggleRow("Scroll animation off (jump)", icon: "arrow.down.to.line", isOn: $debug.scrollAnimationOff)
                SettingsToggleRow("Debug overlay", icon: "ladybug", isOn: $debug.overlay)
            } header: {
                Text("Developer (testing)")
            } footer: {
                Text("Switches single lyrics effects off to find what causes a visual problem. The overlay shows the scroll offset, its target and retargets per second.")
            }
            }

            M3Section {
                NavigationLink {
                    LyricsProviderOrderView()
                } label: {
                    Label("Provider Order", systemImage: "list.number")
                }
            }
        }
        .m3ScreenBackground()
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
