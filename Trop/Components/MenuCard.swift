//
//  MenuCard.swift
//  Trop
//
// Created by 686udjie on 12/09/2026.
//

import SwiftUI

/// Standard chrome for menu sheets: NavigationStack + padded card column on
/// the grouped background with medium/large detents and a drag indicator.
/// Content needing `navigationDestination` should wrap itself in a `Group`
/// carrying that modifier (it must live inside the NavigationStack).
struct SheetChrome<Content: View>: View {
    @Environment(\.m3) private var m3
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    content
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(M3Shape.extraLarge)
        .presentationBackground {
            FrostedSurface(tint: m3.surface, tintOpacity: 0.82, material: .regularMaterial)
        }
    }
}

/// Rounded grouped-background card stacking menu rows with no spacing.
struct MenuCard<Content: View>: View {
    @Environment(\.m3) private var m3
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: M3Shape.extraLarge, style: .continuous)
                .fill(m3.surfaceContainerLow)
        )
        .clipShape(RoundedRectangle(cornerRadius: M3Shape.extraLarge, style: .continuous))
        .tint(m3.primary)
    }
}

/// Tappable menu row: accent icon + title + optional subtitle.
struct MenuRow: View {
    let icon: String
    let title: String
    var subtitle: String?
    var destructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MenuRowLabel(icon: icon, title: title, subtitle: subtitle, destructive: destructive)
        }
        .buttonStyle(.plain)
    }
}

/// The label half of `MenuRow`, for rows embedded in a `NavigationLink`.
struct MenuRowLabel: View {
    @Environment(\.m3) private var m3

    let icon: String
    let title: String
    var subtitle: String?
    var destructive: Bool = false

    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(destructive ? m3.error : m3.onSurfaceVariant)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(.m3(.titleMedium, weight: .regular))
                    .foregroundStyle(destructive ? m3.error : m3.onSurface)
                if let subtitle, !subtitle.isEmpty {
                    Text(LocalizedStringKey(subtitle))
                        .font(.m3(.bodyMedium))
                        .foregroundStyle(m3.onSurfaceVariant)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }
}

/// Inset divider used between rows of an M3 grouped card.
struct M3RowDivider: View {
    @Environment(\.m3) private var m3
    var body: some View {
        Rectangle()
            .fill(m3.outlineVariant)
            .frame(height: 1)
            .padding(.leading, 68)
    }
}
