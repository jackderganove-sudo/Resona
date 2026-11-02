//
//  SponsorBlockSettingsView.swift
//  Trop
//
//  Created by 686udjie on 23/10/2026.
//

import SwiftUI

struct SponsorBlockSettingsView: View {
    @State private var enabled = SponsorBlock.isEnabled
    @State private var showButton = SponsorBlock.showsSkipButton

    var body: some View {
        M3Form(title: "SponsorBlock") {
            M3Section {
                Toggle("Skip Segments", isOn: $enabled)
            } footer: {
                Text("Skips non-music parts of music videos, like talking intros, skits and long outros.")
            }
            M3Section {
                Toggle("Ask with a button instead of skipping", isOn: $showButton)
                    .disabled(!enabled)
            } footer: {
                Text("Shows “Skip non-music part” in the player while such a part plays. Per song SponsorBlock can be switched off in the player menu.")
            }
        }
        .m3ScreenBackground()
        .miniPlayerTracksScroll()
        .onChange(of: enabled) {
            SponsorBlock.save(enabled: enabled)
        }
        .onChange(of: showButton) {
            SponsorBlock.showsSkipButton = showButton
        }
    }
}
