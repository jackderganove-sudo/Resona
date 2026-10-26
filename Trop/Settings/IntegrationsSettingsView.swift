//
//  IntegrationsSettingsView.swift
//  Trop
//

import SwiftUI

struct IntegrationsSettingsView: View {
    var body: some View {
        List {
            Section {
                SettingsNavigationRow("Last.fm", icon: "music.note") {
                    LastFMSettingsView()
                }
                SettingsNavigationRow("Canvas", icon: "film") {
                    CanvasSettingsView()
                }
                SettingsNavigationRow("SponsorBlock", icon: "forward.end") {
                    SponsorBlockSettingsView()
                }
            } footer: {
                Text("Connect external services to enhance your experience.")
            }
        }
        .navigationTitle("Integrations")
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
    }
}
