//
//  MediaDetailHero.swift
//  Resona
//
//  Detail-page hero from the reference app: the artwork fills the top of the
//  page and fades into the surface; centred title, subtitle, description and
//  metadata sit at the bottom, followed by the primary action row.
//

import SwiftUI

struct MediaDetailHero<Subtitle: View, Actions: View>: View {
    @Environment(\.m3) private var m3
    let title: String
    let artworkURL: String?
    var mosaic: [String] = []
    var description: String?
    var metadata: String?
    @ViewBuilder var subtitle: () -> Subtitle
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        ZStack(alignment: .bottom) {
            artwork
                .frame(maxWidth: .infinity)
                .frame(height: 560)
                .clipped()

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.42), location: 0),
                    .init(color: .clear, location: 0.18),
                    .init(color: .clear, location: 0.42),
                    .init(color: m3.surface.opacity(0.78), location: 0.72),
                    .init(color: m3.surface, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 0) {
                Text(title)
                    .font(.m3(.headlineLarge, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 2)

                subtitle()
                    .font(.m3(.titleMedium, weight: .regular))
                    .foregroundStyle(.white.opacity(0.82))
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)

                if let description, !description.isEmpty {
                    Text(description)
                        .font(.m3(.bodyMedium))
                        .foregroundStyle(.white.opacity(0.76))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.top, 8)
                }

                if let metadata, !metadata.isEmpty {
                    Text(metadata)
                        .font(.m3(.labelMedium, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                        .padding(.top, 16)
                }

                actions()
                    .padding(.top, 14)
            }
            .frame(maxWidth: 720)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(height: 560)
    }

    @ViewBuilder
    private var artwork: some View {
        if let artworkURL {
            AsyncImageView(url: ArtworkLoader.highRes(artworkURL) ?? artworkURL)
        } else if mosaic.count >= 4 {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        cell(mosaic[0], geo.size)
                        cell(mosaic[1], geo.size)
                    }
                    HStack(spacing: 0) {
                        cell(mosaic[2], geo.size)
                        cell(mosaic[3], geo.size)
                    }
                }
            }
        } else if let first = mosaic.first {
            AsyncImageView(url: first)
        } else {
            ZStack {
                m3.surfaceContainerHigh
                Image(systemName: "music.note.list")
                    .font(.system(size: 96))
                    .foregroundStyle(m3.onSurfaceVariant)
            }
        }
    }

    private func cell(_ url: String, _ size: CGSize) -> some View {
        AsyncImageView(url: url)
            .frame(width: size.width / 2, height: size.height / 2)
            .clipped()
    }
}

/// Primary actions under a detail hero: shuffle · Play pill · extra.
struct MediaDetailActions: View {
    @Environment(\.m3) private var m3
    var onShuffle: (() -> Void)?
    var onPlay: (() -> Void)?
    var secondaryIcon: String?
    var secondaryLabel: LocalizedStringKey = "More"
    var onSecondary: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            if let onShuffle {
                circle("shuffle", label: "Shuffle", action: onShuffle)
            }
            if let onPlay {
                Button(action: onPlay) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 18, weight: .bold))
                        Text("Play")
                            .font(.m3(.titleMedium, weight: .medium))
                    }
                    .foregroundStyle(m3.surface)
                    .padding(.horizontal, 28)
                    .frame(height: 56)
                    .background(.white, in: Capsule())
                }
                .buttonStyle(MorphPressStyle())
            }
            if let secondaryIcon, let onSecondary {
                circle(secondaryIcon, label: secondaryLabel, action: onSecondary)
            }
        }
    }

    private func circle(_ icon: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(.white.opacity(0.16), in: Circle())
        }
        .buttonStyle(.expressive(scale: 0.88))
        .accessibilityLabel(Text(label))
    }
}

/// Pill that tightens its corners and squishes slightly while pressed.
private struct MorphPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .clipShape(RoundedRectangle(cornerRadius: configuration.isPressed ? 16 : 28, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(M3Motion.fastSpatial, value: configuration.isPressed)
    }
}

extension View {
    /// Lets a detail page's hero run under the status/navigation bar.
    func heroDetailChrome() -> some View {
        self
            .ignoresSafeArea(edges: .top)
            .toolbarBackground(.hidden, for: .navigationBar)
    }
}
