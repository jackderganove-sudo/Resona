//
//  LyricsSyncSheet.swift
//  Resona
//
//  "Sync yourself" for lyrics without timestamps: the song plays from the
//  start (or the current position), the next line to time is shown large,
//  and a tap anywhere — or the big Tap button — stamps it with the current
//  playback time. Undo and −2 s help fix mistakes; a preview shows all
//  timestamps before saving. Saved lyrics are stored per song as custom
//  lyrics ("Self-synced"), which take priority over the providers.
//

import SwiftUI

struct LyricsSyncSheet: View {
    let videoId: String
    let songTitle: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.m3) private var m3
    @State private var texts: [String] = []
    @State private var stamps: [TimeInterval] = []
    @State private var phase: Phase = .intro
    @State private var tapCount = 0

    private enum Phase { case intro, tapping, preview }
    private let player = PlayerController.shared
    private let np = NowPlaying.shared

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .intro: intro
                case .tapping: tapping
                case .preview: preview
                }
            }
            .padding(20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Sync lyrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationBackground { ResonaGlassBackground() }
        .task {
            let lines = await LyricsService.shared.currentLines(videoId: videoId)
            texts = lines.map(\.text).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: tapCount)
    }

    // MARK: Intro

    private var intro: some View {
        VStack(spacing: 18) {
            Image(systemName: "hand.tap")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(m3.primary)
            Text("Tap along with the song")
                .font(.m3(.headlineSmall))
                .foregroundStyle(m3.onSurface)
            Text("Each tap sets the start of the highlighted line to the current playback time and moves on to the next line. Use Undo or −2 s if you were off.")
                .font(.m3(.bodyLarge))
                .foregroundStyle(m3.onSurfaceVariant)
                .multilineTextAlignment(.center)
            Text(String(format: String(localized: "%d lines"), texts.count))
                .font(.m3(.labelLarge))
                .foregroundStyle(m3.onSurfaceVariant)
            Spacer()
            Button {
                start(at: 0)
            } label: {
                Label("Start from the beginning", systemImage: "backward.end.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.m3Filled)
            .disabled(texts.isEmpty)
            if np.currentTime > 5 {
                Button {
                    start(at: np.currentTime)
                } label: {
                    Label("Start at the current position", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.m3Tonal)
                .disabled(texts.isEmpty)
            }
        }
    }

    private func start(at time: TimeInterval) {
        stamps = []
        player.seek(to: time)
        player.setPaused(false)
        withAnimation(M3Motion.defaultSpatial) { phase = .tapping }
    }

    // MARK: Tapping

    private var tapping: some View {
        VStack(spacing: 16) {
            PlaybackProgressReader { time, _ in
                Text(Self.stamp(time))
                    .font(.m3(.titleMedium).monospacedDigit())
                    .foregroundStyle(m3.onSurfaceVariant)
            }
            Text(String(format: String(localized: "Line %d of %d"), min(stamps.count + 1, texts.count), texts.count))
                .font(.m3(.labelLarge))
                .foregroundStyle(m3.onSurfaceVariant)

            // Previous, NEXT TO TAP (large), upcoming.
            VStack(spacing: 14) {
                line(stamps.count - 1, size: 17, opacity: 0.4)
                line(stamps.count, size: 30, opacity: 1, highlighted: true)
                line(stamps.count + 1, size: 19, opacity: 0.5)
                line(stamps.count + 2, size: 17, opacity: 0.3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { tap() }
            .animation(M3Motion.defaultSpatial, value: stamps.count)

            Button(action: tap) {
                Text("Tap")
                    .font(.m3(.headlineMedium, weight: .medium))
                    .foregroundStyle(m3.onPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 110)
                    .background(m3.primary, in: RoundedRectangle(cornerRadius: M3Shape.extraLarge, style: .continuous))
            }
            .buttonStyle(.expressive(scale: 0.96))

            HStack(spacing: 12) {
                Button {
                    if !stamps.isEmpty { stamps.removeLast() }
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.m3Tonal)
                .disabled(stamps.isEmpty)

                Button {
                    let target = max(0, PlaybackClock.shared.now() - 2)
                    player.seek(to: target)
                    // Lines stamped after the new position must be set again.
                    stamps.removeAll { $0 > target }
                } label: {
                    Label("−2 s", systemImage: "gobackward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.m3Tonal)
            }
        }
    }

    private func line(_ index: Int, size: CGFloat, opacity: Double, highlighted: Bool = false) -> some View {
        Text(texts.indices.contains(index) ? texts[index] : " ")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(highlighted ? m3.primary : m3.onSurface.opacity(opacity))
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .id(index)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func tap() {
        guard stamps.count < texts.count else { return }
        tapCount += 1
        // Monotonic: never earlier than the previous line.
        stamps.append(max(PlaybackClock.shared.now(), stamps.last ?? 0))
        if stamps.count == texts.count {
            withAnimation(M3Motion.defaultSpatial) { phase = .preview }
        }
    }

    // MARK: Preview

    private var preview: some View {
        VStack(spacing: 14) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(zip(stamps, texts).enumerated()), id: \.offset) { _, pair in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(Self.stamp(pair.0))
                                .font(.m3(.labelLarge).monospacedDigit())
                                .foregroundStyle(m3.primary)
                            Text(pair.1)
                                .font(.m3(.bodyLarge))
                                .foregroundStyle(m3.onSurface)
                        }
                    }
                }
            }
            HStack(spacing: 12) {
                Button("Start over") {
                    withAnimation(M3Motion.defaultSpatial) { phase = .intro }
                }
                .buttonStyle(.m3Tonal)
                Button("Save") { save() }
                    .buttonStyle(.m3Filled)
            }
        }
    }

    private func save() {
        let lrc = zip(stamps, texts).map { "[\(Self.stamp($0.0))]\($0.1)" }.joined(separator: "\n")
        Task {
            await LyricsService.shared.saveCustom(videoId: videoId, rawText: lrc, providerName: LyricsSyncSheet.providerName)
        }
        dismiss()
    }

    static let providerName = "Self-synced"

    static func stamp(_ t: TimeInterval) -> String {
        let minutes = Int(t) / 60
        let seconds = Int(t) % 60
        let centis = Int(((t - floor(t)) * 100).rounded(.down))
        return String(format: "%02d:%02d.%02d", minutes, seconds, centis)
    }
}
