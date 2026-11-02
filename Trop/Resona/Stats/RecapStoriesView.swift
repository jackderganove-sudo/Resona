//
//  RecapStoriesView.swift
//  Resona
//
//  Recap stories (after ArchiveTune 15's Year in Music): full-screen
//  slides with progress bars that advance on their own — artwork wall,
//  minutes counting up, top artist, top songs, listening type, summary.
//  Tap right/left to skip, hold to pause, share the summary as an image.
//

import SwiftUI

struct RecapStoriesView: View {
    let stats: ListeningStats
    let periodTitle: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.m3) private var m3
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var progress: Double = 0
    @State private var paused = false
    @State private var appeared = false

    static let slideDuration: Double = 6

    private var slides: [RecapSlide] { RecapSlide.slides(for: stats) }

    var body: some View {
        let slides = self.slides
        ZStack {
            background
            if slides.indices.contains(index) {
                slideView(slides[index])
                    .id(index)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 1.04)), removal: .opacity))
            }
            VStack(spacing: 12) {
                progressBars(count: slides.count)
                HStack {
                    Text(verbatim: "Resona · \(periodTitle)")
                        .font(.m3(.labelLarge))
                        .foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.white.opacity(0.15), in: Circle())
                    }
                    .accessibilityLabel(Text("Close"))
                    .accessibilityIdentifier("recap.close")
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture().onEnded { value in
                // Left third: back, rest: forward (the close button wins).
                step(value.location.x < 160 ? -1 : 1)
            }
        )
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.25)
                .onChanged { _ in paused = true }
                .onEnded { _ in paused = false }
        )
        .task(id: index) { await runTimer() }
        .onAppear { appeared = true }
        .statusBarHidden()
        .accessibilityIdentifier("recap")
    }

    // MARK: Timer

    private func runTimer() async {
        progress = 0
        let tick = 0.05
        while progress < 1 {
            try? await Task.sleep(for: .seconds(tick))
            if Task.isCancelled { return }
            if !paused { progress = min(1, progress + tick / Self.slideDuration) }
        }
        step(1)
    }

    private func step(_ delta: Int) {
        let next = index + delta
        if next >= slides.count {
            dismiss()
        } else {
            withAnimation(M3Motion.defaultSpatial) { index = max(0, next) }
        }
    }

    // MARK: Chrome

    private var background: some View {
        ZStack {
            LinearGradient(colors: [m3.primaryContainer, Color.black], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [m3.tertiary.opacity(0.45), .clear], center: .topTrailing, startRadius: 20, endRadius: 520)
        }
        .ignoresSafeArea()
    }

    private func progressBars(count: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { slide in
                GeometryReader { geo in
                    Capsule().fill(.white.opacity(0.3))
                    Capsule().fill(.white)
                        .frame(width: geo.size.width * (slide < index ? 1 : (slide == index ? progress : 0)))
                }
                .frame(height: 3)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Slides

    @ViewBuilder
    private func slideView(_ slide: RecapSlide) -> some View {
        switch slide {
        case .intro:
            VStack(spacing: 24) {
                ArtworkWall(urls: stats.topSongs.compactMap(\.thumbnailUrl) + stats.topAlbums.compactMap(\.thumbnailUrl), columns: 4)
                    .frame(width: 320, height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .rotationEffect(.degrees(appeared && !reduceMotion ? -4 : 0))
                    .shadow(color: .black.opacity(0.4), radius: 30, y: 16)
                    .animation(.spring(duration: 1.2), value: appeared)
                storyText(title: "Your recap", subtitle: String(format: String(localized: "%@ in music"), periodTitle))
            }
        case .minutes:
            VStack(spacing: 12) {
                CountUpText(target: stats.totalMinutes)
                    .font(.system(size: 96, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                storyText(title: "minutes of music",
                          subtitle: String(format: String(localized: "%d plays, %d different songs"), stats.plays, stats.distinctSongs))
            }
        case .topArtist(let artist):
            VStack(spacing: 22) {
                AsyncImageView(url: artist.thumbnailUrl)
                    .frame(width: 240, height: 240)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 2))
                    .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
                storyText(title: LocalizedStringKey(artist.title),
                          subtitle: String(format: String(localized: "Your top artist · %d min"), artist.minutes))
            }
        case .topSongs(let songs):
            VStack(alignment: .leading, spacing: 14) {
                Text("Your top songs")
                    .font(.m3(.headlineMedium, weight: .bold))
                    .foregroundStyle(.white)
                ForEach(Array(songs.enumerated()), id: \.element.id) { offset, song in
                    HStack(spacing: 14) {
                        Text("\(offset + 1)")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 34)
                        AsyncImageView(url: song.thumbnailUrl)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title).font(.m3(.titleMedium, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                            Text(song.subtitle ?? "").font(.m3(.bodyMedium)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                        }
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxWidth: 460)
            .padding(.horizontal, 28)
        case .listener(let type, let hour):
            VStack(spacing: 18) {
                Image(systemName: hour >= 5 && hour < 17 ? "sun.max.fill" : "moon.stars.fill")
                    .font(.system(size: 88))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse, isActive: !reduceMotion)
                storyText(title: LocalizedStringKey(type),
                          subtitle: String(format: String(localized: "You listen most around %d:00"), hour))
            }
        case .summary:
            VStack(spacing: 20) {
                RecapSummaryCard(stats: stats, periodTitle: periodTitle)
                    .frame(width: 340)
                Button {
                    shareSummary()
                } label: {
                    Label("Share as image", systemImage: "square.and.arrow.up")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.m3Filled)
                .accessibilityIdentifier("recap.share")
            }
        }
    }

    private func storyText(title: LocalizedStringKey, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.m3(.displaySmall, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.m3(.titleMedium))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
    }

    @MainActor
    private func shareSummary() {
        paused = true
        let renderer = ImageRenderer(content: RecapSummaryCard(stats: stats, periodTitle: periodTitle)
            .frame(width: 360)
            .environment(\.m3, m3))
        renderer.scale = 3
        guard let image = renderer.uiImage else { return }
        presentShareSheet(items: [image]) { paused = false }
    }
}

enum RecapSlide: Hashable {
    case intro, minutes
    case topArtist(RankedEntry)
    case topSongs([RankedEntry])
    case listener(String, hour: Int)
    case summary

    static func slides(for stats: ListeningStats) -> [RecapSlide] {
        guard !stats.isEmpty else { return [.intro, .summary] }
        var slides: [RecapSlide] = [.intro, .minutes]
        if let artist = stats.topArtists.first { slides.append(.topArtist(artist)) }
        if !stats.topSongs.isEmpty { slides.append(.topSongs(Array(stats.topSongs.prefix(5)))) }
        if let type = stats.listenerType, let hour = stats.peakHour { slides.append(.listener(type, hour: hour)) }
        slides.append(.summary)
        return slides
    }
}

/// Number counting up from 0 when it appears.
struct CountUpText: View {
    let target: Int
    @State private var value: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text("\(Int(value))")
            .contentTransition(.numericText(value: value))
            .monospacedDigit()
            .onAppear {
                if reduceMotion {
                    value = Double(target)
                } else {
                    withAnimation(.easeOut(duration: 1.6)) { value = Double(target) }
                }
            }
            .accessibilityLabel(Text("\(target)"))
    }
}

/// The shareable summary (also rendered to an image).
struct RecapSummaryCard: View {
    let stats: ListeningStats
    let periodTitle: String
    @Environment(\.m3) private var m3

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(verbatim: "Resona")
                    .font(.system(size: 20, weight: .bold, design: .serif).italic())
                Spacer()
                Text(periodTitle)
                    .font(.m3(.labelLarge))
            }
            .foregroundStyle(m3.onPrimaryContainer)
            HStack(alignment: .top, spacing: 16) {
                column("Top artists", stats.topArtists.prefix(5).map(\.title))
                column("Top songs", stats.topSongs.prefix(5).map(\.title))
            }
            HStack(spacing: 24) {
                figure("\(stats.totalMinutes)", "Minutes")
                figure("\(stats.plays)", "Plays")
                figure("\(stats.longestStreakDays)", "Day streak")
            }
        }
        .padding(20)
        .background(m3.primaryContainer, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func column(_ title: LocalizedStringKey, _ names: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.m3(.labelLarge, weight: .semibold))
                .foregroundStyle(m3.onPrimaryContainer.opacity(0.7))
            ForEach(Array(names.enumerated()), id: \.offset) { offset, name in
                Text(verbatim: "\(offset + 1). \(name)")
                    .font(.m3(.bodyMedium, weight: .semibold))
                    .foregroundStyle(m3.onPrimaryContainer)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func figure(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: 26, weight: .black, design: .rounded))
            Text(label)
                .font(.m3(.labelMedium))
                .opacity(0.75)
        }
        .foregroundStyle(m3.onPrimaryContainer)
    }
}
