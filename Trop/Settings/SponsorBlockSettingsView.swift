//
//  SponsorBlockSettingsView.swift
//  Trop
//
//  Created by 686udjie on 23/10/2026.
//

import SwiftUI

struct SponsorBlockSettingsView: View {
    @State private var enabled = SponsorBlock.isEnabled

    var body: some View {
        M3Form(title: "SponsorBlock") {
            M3Section {
                Toggle("Skip Segments", isOn: $enabled)
            } footer: {
                Text("Skips non-music parts of music videos, like talking intros, skits and long outros.")
            }
        }
        .m3ScreenBackground()
        .miniPlayerTracksScroll()
        .onChange(of: enabled) {
            SponsorBlock.save(enabled: enabled)
        }
    }
}
