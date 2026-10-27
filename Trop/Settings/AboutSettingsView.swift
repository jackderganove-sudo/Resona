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

    var body: some View {
        M3Form {
            M3Section {
                HStack {
                    Label("Version", systemImage: "info.circle")
                    Spacer()
                    Text(verbatim: versionText)
                        .foregroundStyle(m3.onSurfaceVariant)
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
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return "\(version) (\(build))"
    }
}
