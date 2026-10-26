//
//  SectionLabel.swift
//  Trop
//
//  Created by 686udjie on 28/08/2026.
//

import SwiftUI

struct SectionLabel: View {
    @Environment(\.m3) private var m3
    let title: String
    let systemImage: String

    var body: some View {
        Label(LocalizedStringKey(title), systemImage: systemImage)
            .font(.m3(.labelLarge, weight: .medium))
            .foregroundStyle(m3.primary)
            .textCase(nil)
            .padding(.leading, 4)
            .padding(.bottom, 4)
    }
}
