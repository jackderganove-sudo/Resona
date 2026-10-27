//
//  AboutSettingsView.swift
//  Trop
//
//  Created by 686udjie on 26/08/2026.
//

import SwiftUI

struct AboutSettingsView: View {
    var body: some View {
        M3Form {
            M3Section {
                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    HStack {
                        Label("Version", systemImage: "info.circle")
                        Spacer()
                        Text(version)
                            .foregroundStyle(.m3OnSurfaceVariant)
                    }
                }
            }

            M3Section {
                SettingsLinkRow("GitHub", icon: "chevron.left.forwardslash.chevron.right", url: URL(string: "https://github.com/SwiftyMedia/Trop")!)
                SettingsLinkRow("Discord", icon: "bubble.left.and.bubble.right", url: URL(string: "https://discord.gg/QrMwZAfU97")!)
            } header: {
                Text("Links")
            }
        }
        .navigationTitle("About")
        .m3ScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
    }
}
