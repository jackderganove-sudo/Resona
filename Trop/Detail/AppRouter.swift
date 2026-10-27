//
// AppRouter.swift
// Trop
//
// Created by 686udjie on 21/08/2026.
//

import Combine
import SwiftUI

/// Owns each tab's NavigationPath so overlays (e.g. the Big Player menu) can
/// push detail pages onto the regular tab navigation. Appending to a path is
/// plain state mutation, so it works even while views are transitioning —
/// unlike pub/sub events, which tabs can miss during player teardown.
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    @Published var homePath = NavigationPath()
    @Published var libraryPath = NavigationPath()
    @Published var explorePath = NavigationPath()
    @Published var searchPath = NavigationPath()
    @Published var selectedTabIndex = 0

    /// Last route opened from an overlay; ContentView listens to collapse the player.
    @Published private(set) var activeRoute: DetailRoute?

    @Published private(set) var playerExpandToken = 0
    /// Logo tap: ContentView goes home (tab, stack, sheets, player).
    @Published private(set) var goHomeToken = 0
    /// Home scrolls to the very top when this changes.
    @Published private(set) var homeScrollTopToken = 0
    /// Keyboard shortcuts (⌘F / ⌘L / ⌘K / Esc).
    @Published private(set) var focusSearchToken = 0
    /// Consumed by the full player when it appears (it may not exist yet
    /// when the shortcut fires).
    @Published var pendingLyrics = false
    @Published var pendingQueue = false
    @Published private(set) var escapeToken = 0

    var activePathDepth: Int {
        switch selectedTabIndex {
        case 1: libraryPath.count
        case 2: explorePath.count
        case 3: searchPath.count
        default: homePath.count
        }
    }

    func popActiveRoute() {
        guard activePathDepth > 0 else { return }
        switch selectedTabIndex {
        case 1: libraryPath.removeLast()
        case 2: explorePath.removeLast()
        case 3: searchPath.removeLast()
        default: homePath.removeLast()
        }
    }

    func expandPlayer() {
        playerExpandToken += 1
    }

    /// From anywhere back to the top of the home tab.
    func goHome() {
        goHomeToken += 1
    }

    func scrollHomeToTop() {
        homeScrollTopToken += 1
    }

    func focusSearch() {
        selectedTabIndex = 3
        focusSearchToken += 1
    }

    func showLyrics() {
        guard NowPlaying.shared.videoId != nil else { return }
        pendingLyrics = true
        expandPlayer()
    }

    func showQueue() {
        guard NowPlaying.shared.videoId != nil else { return }
        pendingQueue = true
        expandPlayer()
    }

    func escape() {
        escapeToken += 1
    }

    func open(_ route: DetailRoute) {
        switch selectedTabIndex {
        case 1: libraryPath.append(route)
        case 2: explorePath.append(route)
        case 3: searchPath.append(route)
        default: homePath.append(route)
        }
        activeRoute = route
    }
}
