//
//  Onboarding.swift
//  Resona
//
//  First-launch welcome (as in ArchiveTune 15's onboarding, in Resona's
//  style): what Resona does, then an optional YouTube Music sign-in —
//  "Continue without account" is a full choice, not a hidden link. Shown
//  once; existing installs (queue, update checks or seen release notes
//  present) skip it. Never in UI or unit tests.
//

import SwiftUI

@MainActor
@Observable
final class OnboardingState {
    static let shared = OnboardingState()

    static let doneKey = "resona.onboarding.done"

    var isPresented = false

    private init() {}

    /// Launch check; returns whether this is the very first launch (then
    /// "What's new" stays quiet).
    @discardableResult
    func checkOnLaunch() -> Bool {
        let defaults = UserDefaults.standard
        guard !TestMode.isUITest, !WhatsNewCenter.isUnitTestHost else { return false }
        guard !defaults.bool(forKey: Self.doneKey) else { return false }
        if Self.isExistingInstall(defaults) {
            defaults.set(true, forKey: Self.doneKey)
            return false
        }
        isPresented = true
        return true
    }

    func finish() {
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        isPresented = false
    }

    /// Traces an earlier Resona version leaves behind.
    static func isExistingInstall(_ defaults: UserDefaults) -> Bool {
        defaults.double(forKey: "resona.update.lastCheck") > 0
            || defaults.object(forKey: "nowPlaying.queue") != nil
            || defaults.object(forKey: WhatsNewCenter.lastSeenKey) != nil
            || defaults.object(forKey: "lyricsProviderOrder") != nil
    }
}

struct OnboardingView: View {
    @Environment(\.m3) private var m3
    @Bindable private var account = AccountSheetState.shared
    @ObservedObject private var loginModel = AccountSheetState.shared.loginModel
    @State private var page = 0

    private let pageCount = 3

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcome.tag(0)
                highlights.tag(1)
                signIn.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(M3Motion.defaultSpatial, value: page)

            footer
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { ResonaGlassBackground().ignoresSafeArea() }
        .loginSheet(state: account)
        .accessibilityIdentifier("onboarding")
    }

    // MARK: Pages

    private var welcome: some View {
        pageLayout {
            Group {
                if let icon = UIImage(named: "AppIcon") {
                    Image(uiImage: icon)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                } else {
                    M3IconCircle(size: 128) { Image(systemName: "waveform").font(.system(size: 56, weight: .medium)) }
                }
            }
            .frame(width: 128, height: 128)
            .shadow(color: .black.opacity(0.25), radius: 24, y: 10)

            Text("Welcome to Resona")
                .font(.m3(.displaySmall))
                .foregroundStyle(m3.onSurface)
                .multilineTextAlignment(.center)
            Text("YouTube Music on your iPad, with lyrics that keep up and a player that adapts to every cover.")
                .font(.m3(.bodyLarge))
                .foregroundStyle(m3.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
        }
    }

    private var highlights: some View {
        pageLayout {
            Text("What Resona does")
                .font(.m3(.headlineMedium))
                .foregroundStyle(m3.onSurface)
            VStack(spacing: 12) {
                highlight("music.mic", "Lyrics from many sources",
                          "Word-synced where available; AI sync and translation for the rest.")
                highlight("arrow.left.and.right", "Crossfade and jump to the drop",
                          "Smooth transitions and a jump straight to the drop.")
                highlight("paintpalette", "Colours from the cover",
                          "Frosted glass and theme colours follow the playing song.")
                highlight("arrow.down.circle", "Downloads",
                          "Songs, albums and playlists offline, kept up to date automatically.")
            }
            .frame(maxWidth: 520)
        }
    }

    private var signIn: some View {
        pageLayout {
            M3IconCircle(size: 72) { Image(systemName: "person.crop.circle").font(.system(size: 34)) }
            Text("Sign in to YouTube Music?")
                .font(.m3(.headlineMedium))
                .foregroundStyle(m3.onSurface)
                .multilineTextAlignment(.center)
            Text("Optional. With an account you get your library, playlists, likes and personal recommendations. Without one, search, radio, lyrics and downloads work all the same.")
                .font(.m3(.bodyLarge))
                .foregroundStyle(m3.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            if loginModel.isLoggedIn {
                Label("Signed in", systemImage: "checkmark.circle.fill")
                    .font(.m3(.titleMedium))
                    .foregroundStyle(m3.primary)
                    .padding(.top, 8)
            } else {
                Button {
                    account.isLoginSheetPresented = true
                } label: {
                    Label("Sign in", systemImage: "person.badge.key")
                        .frame(maxWidth: 280)
                }
                .buttonStyle(.m3Tonal)
                .padding(.top, 8)
                .accessibilityIdentifier("onboarding.signIn")
            }
        }
    }

    private func pageLayout<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                content()
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 48)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(.center)
    }

    private func highlight(_ icon: String, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            M3IconCircle { Image(systemName: icon) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.m3(.titleMedium))
                    .foregroundStyle(m3.onSurface)
                Text(text)
                    .font(.m3(.bodyMedium))
                    .foregroundStyle(m3.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(m3.surfaceContainerHigh.opacity(0.7), in: RoundedRectangle(cornerRadius: M3Shape.large, style: .continuous))
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? m3.primary : m3.outlineVariant)
                        .frame(width: index == page ? 22 : 8, height: 8)
                }
            }
            .animation(M3Motion.fastSpatial, value: page)
            .accessibilityHidden(true)
            Spacer()
            if page < pageCount - 1 {
                Button("Skip") { OnboardingState.shared.finish() }
                    .buttonStyle(.m3Text)
                Button("Next") { page += 1 }
                    .buttonStyle(.m3Filled)
                    .accessibilityIdentifier("onboarding.next")
            } else {
                Button(loginModel.isLoggedIn ? "Let's go" : "Continue without account") {
                    OnboardingState.shared.finish()
                }
                .buttonStyle(.m3Filled)
                .accessibilityIdentifier("onboarding.done")
            }
        }
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
    }
}
