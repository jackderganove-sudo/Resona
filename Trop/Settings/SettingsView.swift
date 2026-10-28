//
//  SettingsView.swift
//  Trop / Resona
//
//  Settings home in the reference style (screenshots 07–09): large title,
//  grouped tonal cards (large outer radius, small radius between rows), each
//  row with an outline icon in a tonal circle, title and one-line description.
//

import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.m3) private var m3
    @Bindable private var accountState = AccountSheetState.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SettingsPageTitle(title: "Settings")

                group([
                    .init(icon: "person.crop.circle", title: "Account", subtitle: accountSubtitle, action: .custom {
                        if !accountState.isLoggedIn { accountState.isLoginSheetPresented = true }
                    }, trailing: accountTrailing),
                    .init(icon: "clock.arrow.circlepath", title: "History", subtitle: "Your recently played songs", action: .route(.history))
                ])

                group([
                    .init(icon: "paintpalette", title: "Appearance", subtitle: "Themes, colors and visual style", action: .page { AnyView(AppearanceSettingsView()) }),
                    .init(icon: "music.note", title: "Playback", subtitle: "Audio behavior, quality and crossfade", action: .page { AnyView(PlayerSettingsView()) }),
                    .init(icon: "rays", title: "Canvas", subtitle: "Animated artwork sources and cache", action: .page { AnyView(CanvasSettingsView()) }),
                    .init(icon: "quote.bubble", title: "Lyrics", subtitle: "Lyrics providers, alignment and romanization", action: .page { AnyView(LyricsSettingsView()) }),
                    .init(icon: "globe", title: "Content", subtitle: "Language, region and explicit content", action: .page { AnyView(ContentSettingsView()) })
                ])

                group([
                    .init(icon: "sparkles", title: "Integrations", subtitle: "Last.fm and SponsorBlock", action: .page { AnyView(IntegrationsSettingsView()) }),
                    .init(icon: "slider.vertical.3", title: "Equalizer", subtitle: "Shape the sound with presets and bands", action: .page { AnyView(EqualizerView()) })
                ])

                group([
                    .init(icon: "internaldrive", title: "Storage", subtitle: "Downloads and offline storage", action: .page { AnyView(DownloadSettingsView()) }),
                    .init(icon: "info.circle", title: "About", subtitle: "App information, licenses and credits", action: .page { AnyView(AboutSettingsView()) }, trailing: versionBadge)
                ])
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(m3.surface.ignoresSafeArea())
        // Same header as every settings subpage; the round back arrow comes
        // from the route (DetailRouteDestinationView).
        .settingsPageChrome("Settings", showsBackButton: false)
        .miniPlayerTracksScroll()
        .loginSheet(state: accountState)
        .task {
            await accountState.restoreSession()
            await accountState.fetchAccountInfo()
        }
    }

    // MARK: Rows

    private var accountSubtitle: String {
        accountState.isLoggedIn
            ? accountState.accountName
            : String(localized: "Sign in and account sync")
    }

    private var accountTrailing: AnyView {
        AnyView(
            Group {
                if accountState.isLoggedIn {
                    Button("Logout", action: accountState.signOut)
                        .font(.m3(.labelLarge, weight: .medium))
                        .foregroundStyle(m3.primary)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .overlay(Capsule().strokeBorder(m3.outline, lineWidth: 1))
                } else {
                    Text("Login")
                        .font(.m3(.labelLarge, weight: .medium))
                        .foregroundStyle(m3.onPrimary)
                        .padding(.horizontal, 16)
                        .frame(height: 36)
                        .background(m3.primary, in: Capsule())
                }
            }
        )
    }

    private var versionBadge: AnyView {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return AnyView(
            Text(verbatim: "v\(version) (\(build))")
                .font(.m3(.labelLarge, weight: .regular))
                .foregroundStyle(m3.onSurfaceVariant)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(m3.surfaceContainerHighest, in: Capsule())
        )
    }

    private func group(_ rows: [SettingsEntry]) -> some View {
        VStack(spacing: 3) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                SettingsCardRow(entry: row, position: .of(index: index, count: rows.count))
            }
        }
    }
}

// MARK: - Entry model

struct SettingsEntry {
    enum Action {
        case page(() -> AnyView)
        case route(DetailRoute)
        case custom(() -> Void)
    }

    let icon: String
    let title: LocalizedStringKey
    let subtitle: String
    let action: Action
    var trailing: AnyView?

    init(icon: String, title: LocalizedStringKey, subtitle: String, action: Action, trailing: AnyView? = nil) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.action = action
        self.trailing = trailing
    }
}

/// One row of a settings group: outline icon in a tonal circle, title and a
/// single-line subtitle on a tonal surface with segmented corners.
struct SettingsCardRow: View {
    @Environment(\.m3) private var m3
    let entry: SettingsEntry
    let position: M3GroupPosition

    var body: some View {
        rowBody.accessibilityIdentifier("settings.\(entry.icon)")
    }

    @ViewBuilder
    private var rowBody: some View {
        switch entry.action {
        case .page(let destination):
            NavigationLink {
                destination()
            } label: {
                label
            }
            .buttonStyle(.expressive(scale: 0.98))
        case .route(let route):
            NavigationLink(value: route) {
                label
            }
            .buttonStyle(.expressive(scale: 0.98))
        case .custom(let action):
            Button(action: action) {
                label
            }
            .buttonStyle(.expressive(scale: 0.98))
        }
    }

    private var label: some View {
        HStack(spacing: 20) {
            M3IconCircle(size: 52) { Image(systemName: entry.icon) }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.m3(.titleLarge, weight: .regular))
                    .foregroundStyle(m3.onSurface)
                    .lineLimit(1)
                Text(LocalizedStringKey(entry.subtitle))
                    .font(.m3(.bodyLarge))
                    .foregroundStyle(m3.onSurfaceVariant)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let trailing = entry.trailing {
                trailing
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(m3.surfaceContainerLow, in: position.shape)
        .contentShape(position.shape)
    }
}
