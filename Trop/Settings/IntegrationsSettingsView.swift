//
//  IntegrationsSettingsView.swift
//  Trop
//

import SwiftUI

struct IntegrationsSettingsView: View {
    var body: some View {
        M3Form(title: "Integrations") {
            M3Section {
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
        .m3ScreenBackground()
        .miniPlayerTracksScroll()
    }
}
