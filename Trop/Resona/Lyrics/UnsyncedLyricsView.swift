//
//  UnsyncedLyricsView.swift
//  Resona
//
//  Lyrics without timestamps: clean readable text with a small "Not
//  synced" note, no (wrong) highlighting. The list follows the song slowly
//  — scroll position proportional to playback progress — and stays where
//  the user puts it for a few seconds after touching it.
//

import SwiftUI

struct UnsyncedLyricsView<Header: View>: View {
    let lines: [LyricLine]
    let fontSize: Double
    let alignment: LyricsAlignment
    @ViewBuilder var header: () -> Header

    private let np = NowPlaying.shared
    @State private var position = ScrollPosition(edge: .top)
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @State private var pausedUntil = Date.distantPast

    var body: some View {
        ScrollView {
            LazyVStack(alignment: alignment.textAlignment.horizontal, spacing: fontSize * 0.7) {
                header()
                Label("Not synced", systemImage: "text.alignleft")
                    .font(.poppins(12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.12), in: Capsule())
                    .frame(maxWidth: .infinity, alignment: alignment.textAlignment)
                    .padding(.horizontal, 28)
                ForEach(lines) { line in
                    LyricsLineText(text: line.text, fontSize: fontSize, alignment: alignment)
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: alignment.textAlignment)
                        .padding(.horizontal, 28)
                }
            }
            .padding(.vertical, 24)
        }
        .scrollIndicators(.hidden)
        .scrollPosition($position)
        .onScrollGeometryChange(for: CGSize.self) { geo in
            CGSize(width: geo.contentSize.height, height: geo.containerSize.height)
        } action: { _, size in
            contentHeight = size.width
            viewportHeight = size.height
        }
        .onScrollPhaseChange { _, phase in
            // The user is reading elsewhere: leave the list alone for a bit.
            if phase == .interacting || phase == .tracking || phase == .decelerating {
                pausedUntil = Date().addingTimeInterval(3)
            }
        }
        .task(id: lines.count) { await follow() }
    }

    /// Glides towards progress × scrollable height every half second.
    private func follow() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(500))
            guard np.isPlaying, np.duration > 0, Date() >= pausedUntil else { continue }
            let scrollable = max(0, contentHeight - viewportHeight)
            guard scrollable > 0 else { continue }
            // Start moving after the first ~10 % and finish a bit before
            // the end, so the visible text roughly matches what is sung.
            let progress = min(max((np.currentTime / np.duration - 0.1) / 0.8, 0), 1)
            withAnimation(.linear(duration: 0.5)) {
                position.scrollTo(y: scrollable * progress)
            }
        }
    }
}
