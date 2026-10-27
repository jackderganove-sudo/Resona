//
//  ThemeStore.swift
//  Resona
//
//  App-wide dynamic theme. Watches the now-playing artwork, extracts a seed
//  colour off the main thread and publishes a new M3 scheme with an animated
//  cross-fade, so every surface in the app follows the current cover.
//

import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class ThemeStore {
    static let shared = ThemeStore()

    private(set) var dark: M3Scheme = .fallbackDark
    private(set) var light: M3Scheme = .generate(seed: M3Scheme.defaultSeed, dark: false)
    private(set) var artwork: ArtworkColors = .fallback

    /// Follow the artwork (true) or stay on the default blue seed.
    var dynamicColor: Bool {
        didSet {
            UserDefaults.standard.set(dynamicColor, forKey: Keys.dynamicColor)
            refresh(force: true)
        }
    }

    /// Pure black surfaces in dark mode (AMOLED).
    var pureBlack: Bool {
        didSet {
            UserDefaults.standard.set(pureBlack, forKey: Keys.pureBlack)
            rebuildSchemes(seed: currentSeed, animated: true)
        }
    }

    func scheme(for colorScheme: ColorScheme) -> M3Scheme {
        colorScheme == .dark ? dark : light
    }

    private enum Keys {
        static let dynamicColor = "resona.theme.dynamicColor"
        static let pureBlack = "resona.theme.pureBlack"
    }

    private var currentSeed = M3Scheme.defaultSeed
    private var lastImageIdentity: ObjectIdentifier?
    private var cache: [String: ArtworkColors] = [:]
    private var cacheOrder: [String] = []
    private var extractionTask: Task<Void, Never>?

    private init() {
        let defaults = UserDefaults.standard
        dynamicColor = defaults.object(forKey: Keys.dynamicColor) as? Bool ?? true
        pureBlack = defaults.bool(forKey: Keys.pureBlack)
        observeArtwork()
        refresh(force: true)
    }

    private func observeArtwork() {
        withObservationTracking {
            _ = NowPlaying.shared.thumbnailVersion
            _ = NowPlaying.shared.videoId
        } onChange: {
            Task { @MainActor [weak self] in
                self?.refresh(force: false)
                self?.observeArtwork()
            }
        }
    }

    private func refresh(force: Bool) {
        let np = NowPlaying.shared
        guard dynamicColor, let image = np.thumbnailUIImage else {
            if force || !dynamicColor {
                lastImageIdentity = nil
                apply(.fallback, animated: !force)
            }
            return
        }

        let identity = ObjectIdentifier(image)
        guard force || identity != lastImageIdentity else { return }
        lastImageIdentity = identity

        let key = np.videoId ?? "\(identity.hashValue)"
        if let cached = cache[key] {
            apply(cached, animated: true)
            return
        }

        extractionTask?.cancel()
        extractionTask = Task.detached(priority: .userInitiated) { [image] in
            let colors = ArtworkColorExtractor.extract(from: image)
            let darkScheme = M3Scheme.generate(seed: colors.seed, dark: true)
            let lightScheme = M3Scheme.generate(seed: colors.seed, dark: false)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, self.lastImageIdentity == identity else { return }
                self.remember(colors, for: key)
                self.apply(colors, animated: true, prebuilt: (darkScheme, lightScheme))
            }
        }
    }

    private func remember(_ colors: ArtworkColors, for key: String) {
        cache[key] = colors
        cacheOrder.append(key)
        if cacheOrder.count > 32 {
            cache.removeValue(forKey: cacheOrder.removeFirst())
        }
    }

    private func apply(_ colors: ArtworkColors, animated: Bool, prebuilt: (M3Scheme, M3Scheme)? = nil) {
        currentSeed = colors.seed
        let update = {
            self.artwork = colors
            if let prebuilt, !self.pureBlack {
                self.dark = prebuilt.0
                self.light = prebuilt.1
            } else {
                self.dark = .generate(seed: colors.seed, dark: true, pureBlack: self.pureBlack)
                self.light = .generate(seed: colors.seed, dark: false)
            }
        }
        if animated {
            withAnimation(M3Motion.colorChange, update)
        } else {
            update()
        }
    }

    private func rebuildSchemes(seed: RGB, animated: Bool) {
        let update = {
            self.dark = .generate(seed: seed, dark: true, pureBlack: self.pureBlack)
            self.light = .generate(seed: seed, dark: false)
        }
        if animated { withAnimation(M3Motion.colorChange, update) } else { update() }
    }
}

// MARK: - Environment

private struct M3SchemeKey: EnvironmentKey {
    static let defaultValue: M3Scheme = .fallbackDark
}

private struct PlayerAccentKey: EnvironmentKey {
    static let defaultValue = M3Scheme.fallbackDark.playerAccent
}

private struct ArtworkColorsKey: EnvironmentKey {
    static let defaultValue: ArtworkColors = .fallback
}

extension EnvironmentValues {
    /// The active Material 3 colour scheme (dynamic, follows the artwork).
    var m3: M3Scheme {
        get { self[M3SchemeKey.self] }
        set { self[M3SchemeKey.self] = newValue }
    }

    /// Accent for the (always dark) player controls, from the same scheme.
    var playerAccent: PlayerAccent {
        get { self[PlayerAccentKey.self] }
        set { self[PlayerAccentKey.self] = newValue }
    }

    /// Raw artwork colours for gradients/glows (player, mini player).
    var artworkColors: ArtworkColors {
        get { self[ArtworkColorsKey.self] }
        set { self[ArtworkColorsKey.self] = newValue }
    }
}

/// Injects the theme into the environment for the system colour scheme
/// that is currently in effect.
struct M3ThemeProvider: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    private let theme = ThemeStore.shared

    func body(content: Content) -> some View {
        let scheme = theme.scheme(for: colorScheme)
        content
            .environment(\.m3, scheme)
            .environment(\.artworkColors, theme.artwork)
            .environment(\.playerAccent, theme.dark.playerAccent)
            .tint(scheme.primary)
    }
}

extension View {
    func m3Theme() -> some View { modifier(M3ThemeProvider()) }
}
