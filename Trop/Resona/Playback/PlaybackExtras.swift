//
//  PlaybackExtras.swift
//  Resona
//
//  Playback additions after ArchiveTune 15:
//  • PlaybackPriorityGate — stream resolution for playback first: download
//    resolutions wait (≤ 8 s) while a playback resolution runs.
//  • PlaybackErrorCenter — a visible hint when a song can't be played
//    (instead of a log line only), with "copy details" incl. app version.
//

import Foundation
import Observation
import SwiftyTube
import UIKit

actor PlaybackPriorityGate {
    static let shared = PlaybackPriorityGate()
    private var active = 0

    func begin() { active += 1 }
    func end() { active = max(0, active - 1) }

    /// Downloads call this before resolving: waits while playback resolves.
    func waitForPlayback(maxSeconds: Double = 8) async {
        var waited = 0.0
        while active > 0, waited < maxSeconds {
            try? await Task.sleep(for: .milliseconds(100))
            waited += 0.1
        }
    }
}

struct PlaybackErrorInfo: Equatable, Identifiable {
    let id = UUID()
    let title: String
    let hint: String
    let details: String
}

@MainActor
@Observable
final class PlaybackErrorCenter {
    static let shared = PlaybackErrorCenter()
    private(set) var current: PlaybackErrorInfo?
    private var hideTask: Task<Void, Never>?

    func report(_ error: Error, videoId: String, title: String?) {
        if error is CancellationError { return }
        let info = Self.describe(error, videoId: videoId, title: title)
        current = info
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, self?.current?.id == info.id else { return }
            self?.current = nil
        }
    }

    func dismiss() {
        hideTask?.cancel()
        current = nil
    }

    /// Readable cause + what to do (German UI via localization).
    static func describe(_ error: Error, videoId: String, title: String?) -> PlaybackErrorInfo {
        let raw = String(describing: error)
        let lower = raw.lowercased()
        let hint: String
        if lower.contains("sign in") || lower.contains("bot") || lower.contains("login_required") {
            hint = String(localized: "YouTube asks for a sign-in (bot check). Sign in to your account or try again later.")
        } else if lower.contains("unavailable") || lower.contains("not available") || lower.contains("private") {
            hint = String(localized: "This song isn't available (removed, private or blocked in your region).")
        } else if lower.contains("age") {
            hint = String(localized: "This song is age-restricted. Signing in may help.")
        } else if error is URLError || lower.contains("network") || lower.contains("offline") || lower.contains("timed out") {
            hint = String(localized: "No connection to YouTube. Check the internet connection.")
        } else {
            hint = String(localized: "The stream could not be loaded. Try again or play another version.")
        }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let details = "Resona \(version) (\(build)) · video \(videoId) · \(raw)"
        let name = title.map { "„\($0)“" } ?? String(localized: "This song")
        return PlaybackErrorInfo(title: String(format: String(localized: "%@ can't be played"), name), hint: hint, details: details)
    }
}

import SwiftUI

/// Top banner for a failed playback: what happened, what to do, details.
struct PlaybackErrorBanner: View {
    @Environment(\.m3) private var m3
    private let center = PlaybackErrorCenter.shared
    @State private var copied = false

    var body: some View {
        ZStack {
            if let info = center.current {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(m3.error)
                        .font(.system(size: 20))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(info.title)
                            .font(.m3(.titleSmall, weight: .semibold))
                            .foregroundStyle(m3.onSurface)
                            .lineLimit(2)
                        Text(info.hint)
                            .font(.m3(.bodySmall))
                            .foregroundStyle(m3.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(copied ? String(localized: "Copied") : String(localized: "Copy details")) {
                            UIPasteboard.general.string = info.details
                            copied = true
                        }
                        .font(.m3(.labelMedium, weight: .semibold))
                        .foregroundStyle(m3.primary)
                        .padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                    Button {
                        center.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(m3.onSurfaceVariant)
                            .frame(width: 30, height: 30)
                    }
                    .accessibilityLabel(Text("Close"))
                }
                .padding(14)
                .frame(maxWidth: 520)
                .background(ResonaGlassBackground(shape: RoundedRectangle(cornerRadius: M3Shape.large, style: .continuous)))
                .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onChange(of: info.id) { _, _ in copied = false }
                .accessibilityIdentifier("playback.error")
            }
        }
        .animation(M3Motion.defaultSpatial, value: center.current?.id)
    }
}
