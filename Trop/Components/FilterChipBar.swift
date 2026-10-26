//
//  FilterChipBar.swift
//  Trop
//
//  Created by 686udjie on 18/08/2026.
//

import SwiftUI

/// Horizontal scrollable row of capsule filter chips.
/// Replaces the duplicated chip rows in Home, Library and Search.
struct FilterChipBar<Item, ID: Hashable>: View {
    @Environment(\.m3) private var m3
    let items: [Item]
    let id: KeyPath<Item, ID>
    let title: (Item) -> String
    let isSelected: (Item) -> Bool
    let onTap: (Item) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(items, id: id) { item in
                    let selected = isSelected(item)
                    Button {
                        withAnimation(M3Motion.defaultSpatial) { onTap(item) }
                    } label: {
                        HStack(spacing: 6) {
                            if selected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .transition(.scale.combined(with: .opacity))
                            }
                            Text(LocalizedStringKey(title(item)))
                                .font(.m3(.labelLarge, weight: .regular))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 18)
                        .frame(height: 40)
                        .foregroundStyle(selected ? m3.onPrimary : m3.onSurfaceVariant)
                        .background(selected ? m3.primary : m3.surfaceContainerHigh, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.expressive)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }
}
