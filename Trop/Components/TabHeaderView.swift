//
//  TabHeaderView.swift
//  Trop
//
//  Created by 686udjie on 18/08/2026.
//

import SwiftUI

/// Shared large-title header with history and account buttons,
/// used by the Home and Library tabs.
struct TabHeaderView: View {
    let title: String
    var accountIsLoggedIn: Bool = false
    var accountImageUrl: String?
    var onHistory: () -> Void
    var onAccount: () -> Void

    var body: some View {
        // Resona shows its brand bar on every tab (reference app style);
        // history / settings live in the account dropdown.
        ResonaTopBar()
    }
}
