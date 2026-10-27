//
//  KeyboardCommands.swift
//  Resona
//
//  Hardware keyboard shortcuts (iPad). Declared as scene Commands, so iPadOS
//  lists them in the shortcut overview (hold ⌘). Shortcuts without a
//  modifier (Space, arrows, Esc) are disabled while a text field is being
//  edited, so typing is never hijacked.
//

import SwiftUI
import UIKit

/// Tracks whether any text field / text view is being edited.
@MainActor
@Observable
final class TextInputState {
    static let shared = TextInputState()
    private(set) var isEditing = false
    private var tokens: [NSObjectProtocol] = []

    private init() {
        let center = NotificationCenter.default
        let begin: [Notification.Name] = [UITextField.textDidBeginEditingNotification, UITextView.textDidBeginEditingNotification]
        let end: [Notification.Name] = [UITextField.textDidEndEditingNotification, UITextView.textDidEndEditingNotification]
        for name in begin {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { TextInputState.shared.isEditing = true }
            })
        }
        for name in end {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { TextInputState.shared.isEditing = false }
            })
        }
    }
}

struct ResonaCommands: Commands {
    var body: some Commands {
        let typing = TextInputState.shared.isEditing
        CommandMenu("Playback") {
            Button("Play / Pause") { KeyboardActions.playPause() }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(typing)
            Button("Back 10 Seconds") { KeyboardActions.seek(by: -10) }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(typing)
            Button("Forward 10 Seconds") { KeyboardActions.seek(by: 10) }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(typing)
            Button("Previous Song") { NowPlaying.shared.playPrevious() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Button("Next Song") { NowPlaying.shared.playNext() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Button("Volume Up") { KeyboardActions.volume(by: 0.05) }
                .keyboardShortcut(.upArrow, modifiers: [])
                .disabled(typing)
            Button("Volume Down") { KeyboardActions.volume(by: -0.05) }
                .keyboardShortcut(.downArrow, modifiers: [])
                .disabled(typing)
        }
        CommandMenu("Go") {
            Button("Search") { AppRouter.shared.focusSearch() }
                .keyboardShortcut("f", modifiers: .command)
            Button("Lyrics") { AppRouter.shared.showLyrics() }
                .keyboardShortcut("l", modifiers: .command)
            Button("Queue") { AppRouter.shared.showQueue() }
                .keyboardShortcut("k", modifiers: .command)
            Button("Home") { AppRouter.shared.selectedTabIndex = ResonaTab.home.rawValue }
                .keyboardShortcut("1", modifiers: .command)
            Button("Search Tab") { AppRouter.shared.selectedTabIndex = ResonaTab.search.rawValue }
                .keyboardShortcut("2", modifiers: .command)
            Button("Library") { AppRouter.shared.selectedTabIndex = ResonaTab.library.rawValue }
                .keyboardShortcut("3", modifiers: .command)
            Button("Close") { AppRouter.shared.escape() }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(typing)
        }
    }
}

@MainActor
enum KeyboardActions {
    static func playPause() {
        guard NowPlaying.shared.videoId != nil else { return }
        PlayerController.shared.togglePlayPause()
    }

    static func seek(by delta: TimeInterval) {
        let np = NowPlaying.shared
        guard np.videoId != nil, np.duration > 0 else { return }
        let target = min(max(0, np.currentTime + delta), max(0, np.duration - 1))
        PlayerController.shared.seek(to: target)
        PlayerController.shared.updateNowPlayingProgress()
    }

    static func volume(by delta: Double) {
        let settings = SettingsStore.shared
        settings.playerVolume = min(1, max(0, settings.playerVolume + delta))
        PlayerController.shared.applyPlayerVolume()
    }
}
