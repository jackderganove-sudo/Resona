//
//  PlayerLyricsPreview.swift
//  Resona
//
//  Three-line lyrics preview for the "Small cover + lyrics" player style:
//  previous line dimmed, current line bright, next line dimmed. Tap opens
//  the full lyrics.
//

import SwiftUI

struct PlayerLyricsPreview: View {
    let onOpen: () -> Void
    private let np = NowPlaying.shared
    @Environment(SettingsStore.self) private var settings
    @State private var lines: [LyricLine] = []

    var body: some View {
        Button(action: onOpen) {
            PlaybackProgressReader { time, _ in
                let index = Self.index(in: lines, at: time + settings.lyricsOffsetSeconds)
                VStack(spacing: 6) {
                    if lines.isEmpty {
                        Text("No synced lyrics")
                            .font(.poppins(15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                    } else {
                        line(index - 1, opacity: 0.35, size: 15)
                        line(index, opacity: 1, size: 19)
                        line(index + 1, opacity: 0.45, size: 15)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(M3Motion.defaultSpatial, value: index)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task(id: np.videoId) {
            guard let id = np.videoId else { lines = []; return }
            let fetched = (try? await LyricsService.shared.fetchLyrics(videoId: id)) ?? []
            lines = fetched.contains(where: { $0.startTime != nil }) ? fetched.filter { $0.startTime != nil } : []
        }
        .accessibilityLabel(Text("Lyrics"))
    }

    @ViewBuilder
    private func line(_ i: Int, opacity: Double, size: CGFloat) -> some View {
        Text(lines.indices.contains(i) ? lines[i].text : " ")
            .font(.poppins(size, weight: .semibold))
            .foregroundStyle(.white.opacity(opacity))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .multilineTextAlignment(.center)
            .id(lines.indices.contains(i) ? lines[i].id : "empty-\(i)")
            .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private static func index(in lines: [LyricLine], at t: TimeInterval) -> Int {
        var result = -1
        for (i, line) in lines.enumerated() {
            guard let start = line.startTime else { continue }
            if start <= t { result = i } else { break }
        }
        return result
    }
}
