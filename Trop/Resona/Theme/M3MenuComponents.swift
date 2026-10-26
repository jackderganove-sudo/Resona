//
//  M3MenuComponents.swift
//  Resona
//
//  Pieces of the reference app's song/player menu sheet: the "Now playing"
//  header card, the volume card and the 3-column action tile grid.
//

import SwiftUI

/// Header card: artwork + optional eyebrow ("Now Playing") + title + artist.
struct M3MenuHeaderCard: View {
    @Environment(\.m3) private var m3
    let title: String
    let subtitle: String
    var eyebrow: LocalizedStringKey?
    var image: UIImage?
    var thumbnailURL: String?

    var body: some View {
        HStack(spacing: 18) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    AsyncImageView(url: thumbnailURL)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: M3Metrics.thumbnailRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                if let eyebrow {
                    Text(eyebrow)
                        .font(.m3(.titleMedium, weight: .regular))
                        .foregroundStyle(m3.primary)
                }
                MarqueeText(text: title, font: .m3(.titleLarge), frameHeight: 28, textColor: m3.onSurface)
                Text(subtitle)
                    .font(.m3(.titleMedium, weight: .regular))
                    .foregroundStyle(m3.onSurfaceVariant)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(m3.surfaceContainerLow, in: RoundedRectangle(cornerRadius: M3Shape.extraLarge, style: .continuous))
    }
}

/// "Volume  20%" card with an expressive slider between mute/speaker icons.
struct M3VolumeCard: View {
    @Environment(\.m3) private var m3
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Volume")
                    .font(.m3(.titleMedium, weight: .regular))
                    .foregroundStyle(m3.onSurface)
                Spacer()
                Text("\(Int((value * 100).rounded()))%")
                    .font(.m3(.titleMedium, weight: .regular))
                    .foregroundStyle(m3.primary)
                    .contentTransition(.numericText())
                    .animation(M3Motion.fastEffects, value: value)
            }
            HStack(spacing: 16) {
                Button { value = 0 } label: {
                    Image(systemName: "speaker.slash")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(m3.onSurfaceVariant)
                }
                .buttonStyle(.expressive)
                .accessibilityLabel(Text("Mute"))
                ExpressiveSlider(
                    value: $value,
                    trackHeight: 16,
                    handleHeight: 28,
                    activeColor: m3.primary,
                    inactiveColor: m3.surfaceVariant
                )
                Button { value = 1 } label: {
                    Image(systemName: "speaker.wave.2")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(m3.onSurfaceVariant)
                }
                .buttonStyle(.expressive)
                .accessibilityLabel(Text("Maximum volume"))
            }
            .padding(.horizontal, 18)
            .frame(height: 56)
            .background(m3.surfaceContainerHigh, in: RoundedRectangle(cornerRadius: M3Shape.large, style: .continuous))
        }
        .padding(16)
        .background(m3.surfaceContainerLow, in: RoundedRectangle(cornerRadius: M3Shape.extraLarge, style: .continuous))
    }
}

struct M3ActionTile: Identifiable {
    let id = UUID()
    let icon: String
    let title: LocalizedStringKey
    let action: () -> Void
}

/// 3-column grid of tonal action tiles inside a rounded container.
struct M3ActionTileGrid: View {
    @Environment(\.m3) private var m3
    let tiles: [M3ActionTile]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(tiles) { tile in
                Button(action: tile.action) {
                    VStack(spacing: 10) {
                        Image(systemName: tile.icon)
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(m3.onSurfaceVariant)
                        Text(tile.title)
                            .font(.m3(.bodyMedium))
                            .foregroundStyle(m3.onSurface)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity)
                    .frame(height: 92)
                    .background(m3.surfaceContainerHigh, in: RoundedRectangle(cornerRadius: M3Shape.largeIncreased, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: M3Shape.largeIncreased, style: .continuous))
                }
                .buttonStyle(.expressive)
            }
        }
        .padding(12)
        .background(m3.surfaceContainerLow, in: RoundedRectangle(cornerRadius: M3Shape.extraLarge, style: .continuous))
    }
}
