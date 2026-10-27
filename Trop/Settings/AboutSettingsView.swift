//
//  AboutSettingsView.swift
//  Trop
//
//  Created by 686udjie on 26/08/2026.
//

import SwiftUI

struct AboutSettingsView: View {
    @Environment(\.m3) private var m3
    @Bindable private var updates = UpdateChecker.shared
    @AppStorage("resona.developerMode") private var developerMode = false
    @State private var versionTaps = 0
    @State private var developerNote: String?

    var body: some View {
        M3Form(title: "About") {
            M3Section {
                HStack {
                    Label("Version", systemImage: "info.circle")
                    Spacer()
                    Text(verbatim: versionText)
                        .foregroundStyle(m3.onSurfaceVariant)
                }
                .contentShape(Rectangle())
                .onTapGesture { countVersionTap() }
                if let developerNote {
                    Text(developerNote)
                        .font(.m3(.bodyMedium))
                        .foregroundStyle(m3.primary)
                }
            }

            M3Section {
                SettingsToggleRow("Automatically check for updates", icon: "arrow.triangle.2.circlepath", isOn: $updates.autoCheck)
                Button {
                    Task { await updates.check(manual: true) }
                } label: {
                    HStack(spacing: 12) {
                        Label("Check for updates", systemImage: "arrow.down.app")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if updates.isChecking {
                            ProgressView()
                        }
                    }
                    .contentShape(Rectangle())
                }
                if let status = updates.statusText {
                    Text(status)
                        .font(.m3(.bodyMedium))
                        .foregroundStyle(m3.onSurfaceVariant)
                }
                if updates.available != nil {
                    Button {
                        updates.showBannerAgain()
                    } label: {
                        Label("Show update", systemImage: "sparkles")
                            .contentShape(Rectangle())
                    }
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("New builds are published on GitHub and in the ESign app source: \(UpdateChecker.sourceURL)")
            }

            M3Section {
                SettingsLinkRow("GitHub", icon: "chevron.left.forwardslash.chevron.right", url: URL(string: "https://github.com/\(UpdateChecker.repository)")!)
                SettingsLinkRow("Trop (base project)", icon: "arrow.triangle.branch", url: URL(string: "https://github.com/SwiftyMedia/Trop")!)
            } header: {
                Text("Links")
            }
        }
        .miniPlayerTracksScroll()
    }

    /// 7 taps on the version toggle the hidden developer switches
    /// (Songtext settings → Developer).
    private func countVersionTap() {
        versionTaps += 1
        guard versionTaps >= 7 else { return }
        versionTaps = 0
        developerMode.toggle()
        developerNote = developerMode
            ? String(localized: "Developer options enabled (Settings → Lyrics).")
            : String(localized: "Developer options hidden.")
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return "\(version) (\(build))"
    }
}
