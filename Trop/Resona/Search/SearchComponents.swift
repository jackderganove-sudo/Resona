//
//  SearchComponents.swift
//  Resona
//
//  Search screen pieces from the reference (screenshot 01): the large pill
//  search bar, the "Explore / Suggestions" primary tabs with a sliding
//  indicator, and the colourful mood & genre tiles.
//

import SwiftUI

// MARK: - Search bar

struct M3SearchBar<Trailing: View>: View {
    @Environment(\.m3) private var m3
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    var onSubmit: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(m3.onSurface)
            TextField(
                "",
                text: $text,
                prompt: Text("Search YouTube Music").foregroundStyle(m3.onSurfaceVariant)
            )
            .font(.m3(.bodyLarge))
            .foregroundStyle(m3.onSurface)
            .focused(focus)
            .submitLabel(.search)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onSubmit(onSubmit)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(m3.onSurfaceVariant)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.expressive)
                .accessibilityLabel(Text("Clear search"))
                .transition(.scale.combined(with: .opacity))
            }
            trailing()
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .frame(height: 56)
        .background(m3.surfaceContainerHigh, in: Capsule())
        .animation(M3Motion.fastSpatial, value: text.isEmpty)
    }
}

// MARK: - Primary tabs

struct M3PrimaryTabs<Tab: Hashable>: View {
    @Environment(\.m3) private var m3
    let tabs: [(tab: Tab, title: LocalizedStringKey, icon: String)]
    @Binding var selection: Tab
    @Namespace private var indicator

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(tabs.indices, id: \.self) { index in
                    let entry = tabs[index]
                    let isSelected = entry.tab == selection
                    Button {
                        withAnimation(M3Motion.defaultSpatial) { selection = entry.tab }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: entry.icon)
                                .font(.system(size: 22, weight: .regular))
                                .symbolEffect(.bounce, value: isSelected)
                            Text(entry.title)
                                .font(.m3(.titleMedium, weight: .regular))
                                .fixedSize()
                                .overlay(alignment: .bottom) {
                                    if isSelected {
                                        UnevenRoundedRectangle(cornerRadii: .init(topLeading: 3, topTrailing: 3))
                                            .fill(m3.primary)
                                            .frame(height: 3)
                                            .offset(y: 13)
                                            .matchedGeometryEffect(id: "indicator", in: indicator)
                                    }
                                }
                        }
                        .foregroundStyle(isSelected ? m3.primary : m3.primary.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Rectangle()
                .fill(m3.surfaceVariant)
                .frame(height: 1)
                .padding(.top, 2)
        }
    }
}

// MARK: - Genre tile

/// Mood/genre tile: diagonal tonal gradient, a decorative inner rounded
/// square and the title in white, colour derived from the title.
struct GenreTile: View {
    let title: String

    var body: some View {
        let base = Self.color(for: title)
        let hsv = base.hsv
        let light = RGB(h: hsv.h, s: max(0.3, hsv.s * 0.75), v: min(0.95, hsv.v * 1.08))
        let dark = RGB(h: hsv.h, s: min(1, hsv.s * 1.05), v: hsv.v * 0.62)

        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [dark.color, light.color], startPoint: .topLeading, endPoint: .bottomTrailing)
            // Name gets the full width and may wrap to two lines (the empty
            // decorative square that looked like a missing image is gone).
            Text(LocalizedStringKey(title))
                .font(.m3(.titleMedium, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.leading)
                .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
                .frame(maxWidth: .infinity, alignment: .bottomLeading)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
        .frame(height: 92)
        .clipShape(RoundedRectangle(cornerRadius: M3Shape.extraLarge, style: .continuous))
    }

    /// Deterministic colour per title from a palette close to YouTube
    /// Music's mood colours (amber, rust, green, red, blue, purple, …).
    static func color(for title: String) -> RGB {
        let palette: [UInt32] = [0xB89524, 0xA8452A, 0x6FAE77, 0x8C2424, 0x2F7FA8, 0x7A4FA0, 0xB0476E, 0x3E8F87, 0xC2702C, 0x5B6FB5]
        var hash: UInt64 = 1469598103934665603
        for byte in title.lowercased().utf8 {
            hash = (hash ^ UInt64(byte)) &* 1099511628211
        }
        return RGB(hex: palette[Int(hash % UInt64(palette.count))])
    }
}
