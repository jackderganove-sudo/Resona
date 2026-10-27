//
//  UpdateChecker.swift
//  Resona
//
//  Checks GitHub Releases for a newer Resona build — on launch at most once
//  a day (switchable) and on demand in Settings → About — and offers the
//  update in a small banner. ESign has no documented URL scheme for
//  installing, so "Open in ESign" opens the IPA download (iOS then offers
//  "Open in ESign"); alternatively ESign picks it up from the app source.
//

import Foundation
import Observation
import SwiftUI

struct AvailableUpdate: Equatable {
    let version: String
    let notes: String
    let ipaURL: URL
    let pageURL: URL
}

@MainActor
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    static let repository = "jackderganove-sudo/Resona"
    static let sourceURL = "https://raw.githubusercontent.com/\(repository)/app-source/apps.json"

    private(set) var available: AvailableUpdate?
    private(set) var isChecking = false
    /// Result of the last manual check (Settings → About).
    private(set) var statusText: String?
    /// The banner was dismissed with "Later" for this version.
    private(set) var bannerDismissed = false

    var autoCheck: Bool {
        didSet { UserDefaults.standard.set(autoCheck, forKey: Keys.autoCheck) }
    }

    private enum Keys {
        static let autoCheck = "resona.update.autoCheck"
        static let lastCheck = "resona.update.lastCheck"
        static let skipped = "resona.update.skippedVersion"
    }

    private init() {
        autoCheck = UserDefaults.standard.object(forKey: Keys.autoCheck) as? Bool ?? true
    }

    static var installedVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Launch: at most once per 24 h, only with the switch on.
    func checkIfDue() {
        guard autoCheck else { return }
        let last = UserDefaults.standard.double(forKey: Keys.lastCheck)
        guard Date().timeIntervalSince1970 - last > 24 * 3600 else { return }
        Task { await check(manual: false) }
    }

    func check(manual: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Keys.lastCheck)

        guard let release = await Self.latestRelease() else {
            if manual { statusText = String(localized: "Could not check for updates.") }
            return
        }
        if Self.isNewer(release.version, than: Self.installedVersion) {
            available = release
            let skipped = UserDefaults.standard.string(forKey: Keys.skipped)
            bannerDismissed = !manual && skipped == release.version
            if manual { statusText = String(format: String(localized: "Version %@ is available."), release.version) }
        } else {
            available = nil
            if manual { statusText = String(localized: "Resona is up to date.") }
        }
    }

    /// "Later": hide the banner for this version.
    func dismissBanner() {
        bannerDismissed = true
        if let version = available?.version {
            UserDefaults.standard.set(version, forKey: Keys.skipped)
        }
    }

    func showBannerAgain() { bannerDismissed = false }

    // MARK: GitHub

    private static func latestRelease() async -> AvailableUpdate? {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        let assets = (json["assets"] as? [[String: Any]]) ?? []
        let ipa = assets.first { ($0["name"] as? String)?.hasSuffix(".ipa") == true }
        let ipaURL = (ipa?["browser_download_url"] as? String).flatMap(URL.init(string:)) ?? page
        return AvailableUpdate(
            version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag,
            notes: (json["body"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            ipaURL: ipaURL,
            pageURL: page
        )
    }

    /// Numeric comparison of dotted versions ("0.10.2" > "0.9.7").
    static func isNewer(_ candidate: String, than installed: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = installed.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

// MARK: - Banner

/// Discreet card at the top: new version, changelog, "Open in ESign" / "Later".
struct UpdateBanner: View {
    @Environment(\.m3) private var m3
    @Environment(\.openURL) private var openURL
    let update: AvailableUpdate
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                M3IconCircle(size: 40) { Image(systemName: "arrow.down.app") }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Update available")
                        .font(.m3(.titleMedium, weight: .medium))
                        .foregroundStyle(m3.onSurface)
                    Text(verbatim: "Resona \(update.version)")
                        .font(.m3(.bodyMedium))
                        .foregroundStyle(m3.onSurfaceVariant)
                }
                Spacer(minLength: 0)
                if !update.notes.isEmpty {
                    Button {
                        withAnimation(M3Motion.defaultSpatial) { expanded.toggle() }
                    } label: {
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                            .foregroundStyle(m3.onSurfaceVariant)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Changelog"))
                }
            }
            if expanded {
                ScrollView {
                    Text(update.notes)
                        .font(.m3(.bodySmall))
                        .foregroundStyle(m3.onSurfaceVariant)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
            }
            HStack(spacing: 10) {
                Spacer()
                Button("Later") { withAnimation(M3Motion.defaultSpatial) { UpdateChecker.shared.dismissBanner() } }
                    .buttonStyle(.m3Text)
                Button("Open in ESign") { openURL(update.ipaURL) }
                    .buttonStyle(.m3Filled)
            }
        }
        .padding(16)
        .background(ResonaGlassBackground(shape: RoundedRectangle(cornerRadius: M3Shape.extraLarge, style: .continuous)))
        .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
        .frame(maxWidth: 520)
        .padding(.horizontal, 16)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
