//
//  LyricsProviderOrderView.swift
//  Trop
//
//  Created by 686udjie on 20/08/2026.
//

import SwiftUI

struct LyricsProviderOrderView: View {
    @Environment(\.m3) private var m3
    @State private var settings = LyricsSettings.shared
    @State private var order: [String] = LyricsSettings.shared.providerOrder

    private var providers: [LyricsProvider] {
        order.compactMap { LyricsProviderRegistry.provider(for: $0) }
    }

    var body: some View {
        List {
            ForEach(providers, id: \.id) { provider in
                Text(provider.name)
            }
            .onMove(perform: move)
        }
        // Same centred column as the other settings pages.
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .navigationTitle("Lyrics Providers")
        .m3ScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, .constant(.active))
        .safeAreaInset(edge: .bottom) {
            Text("Drag to reorder providers")
                .font(.footnote)
                .foregroundStyle(m3.onSurfaceVariant)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background { ResonaGlassBackground() }
        }
        .miniPlayerTracksScroll()
        .onAppear {
            var merged = settings.providerOrder
            for provider in LyricsProviderRegistry.all where !merged.contains(provider.id) {
                merged.append(provider.id)
            }
            order = merged
        }
        .onDisappear { settings.saveProviderOrder(order) }
    }

    private func move(from source: IndexSet, to destination: Int) {
        order.move(fromOffsets: source, toOffset: destination)
    }
}
