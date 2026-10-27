//
//  PlaybackControlsView.swift
//  Trop
//
//  Created by 686udjie on 2/07/2026.
//

import SwiftUI

/// Shuffle / play / more circular buttons shared by every detail header.
/// Canonicalizes on the PlaylistHeaderView styling (48/64pt, grouped
/// background, accent glow shadow).
struct PlaybackControlsView: View {
    var accent: Color = .m3Primary
    var showsShuffle: Bool = true
    var showsMore: Bool = false
    var onPlay: () -> Void
    var onShuffle: () -> Void = {}
    var onMore: () -> Void = {}

    /// Resona: same action row as the detail hero (shuffle · Play · more).
    var body: some View {
        MediaDetailActions(
            onShuffle: showsShuffle ? onShuffle : nil,
            onPlay: onPlay,
            secondaryIcon: showsMore ? "ellipsis" : nil,
            onSecondary: showsMore ? onMore : nil
        )
        .padding(.top, 4)
    }
}
