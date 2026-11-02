//
//  StatsView.swift
//  Resona
//
//  Library → Your stats: period picker, minutes / plays / streak, top
//  artists, songs and albums, listening by hour and weekday, the recap
//  stories and "Reset statistics" (non-destructive, undoable).
//

import Charts
import SwiftUI

struct StatsView: View {
    @Environment(\.m3) private var m3
    @Bindable private var store = ListeningStatsStore.shared
    @State private var showRecap = false
    @State private var confirmReset = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Period", selection: $store.period) {
                    ForEach(StatsPeriod.allCases) { period in
                        Text(period.title).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("stats.period")

                if store.stats.isEmpty && !store.isLoading {
                    emptyState
                } else {
                    recapCard
                    summaryTiles
                    ranking("Top artists", entries: store.stats.topArtists, round: true)
                    ranking("Top songs", entries: store.stats.topSongs, round: false)
                    ranking("Top albums", entries: store.stats.topAlbums, round: false)
                    hoursChart
                    weekdayChart
                }
                resetSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .miniPlayerTracksScroll()
        .navigationTitle("Your stats")
        .navigationBarTitleDisplayMode(.large)
        .task(id: store.period) { await store.load() }
        .fullScreenCover(isPresented: $showRecap) {
            RecapStoriesView(stats: store.stats, periodTitle: store.period.title)
        }
        .confirmationDialog("Reset statistics?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { Task { await store.reset() } }
        } message: {
            Text("Statistics start again from now. Your history, likes and recommendations stay unchanged.")
        }
        .accessibilityIdentifier("stats")
    }

    // MARK: Parts

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(m3.primary)
            Text("No listening data yet")
                .font(.m3(.titleMedium))
                .foregroundStyle(m3.onSurface)
            Text("Play some music and your stats appear here.")
                .font(.m3(.bodyMedium))
                .foregroundStyle(m3.onSurfaceVariant)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private var recapCard: some View {
        Button {
            showRecap = true
        } label: {
            HStack(spacing: 16) {
                ArtworkWall(urls: store.stats.topSongs.compactMap(\.thumbnailUrl), columns: 3, spacing: 3)
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: M3Shape.large, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your recap")
                        .font(.m3(.titleLarge, weight: .semibold))
                        .foregroundStyle(m3.onPrimaryContainer)
                    Text(String(format: String(localized: "Stories for %@ – tap to play"), store.period.title))
                        .font(.m3(.bodyMedium))
                        .foregroundStyle(m3.onPrimaryContainer.opacity(0.8))
                }
                Spacer(minLength: 0)
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(m3.onPrimaryContainer)
            }
            .padding(16)
            .background(m3.primaryContainer, in: RoundedRectangle(cornerRadius: M3Shape.extraLarge, style: .continuous))
        }
        .buttonStyle(.expressive(scale: 0.97))
        .accessibilityIdentifier("stats.recap")
    }

    private var summaryTiles: some View {
        let stats = store.stats
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            tile("\(stats.totalMinutes)", "Minutes", "clock")
            tile("\(stats.plays)", "Plays", "play.circle")
            tile("\(stats.distinctArtists)", "Artists", "music.mic")
            tile("\(stats.longestStreakDays)", "Day streak", "flame")
        }
    }

    private func tile(_ value: String, _ label: LocalizedStringKey, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(m3.primary)
            Text(value)
                .font(.m3(.headlineMedium, weight: .bold))
                .foregroundStyle(m3.onSurface)
                .contentTransition(.numericText())
            Text(label)
                .font(.m3(.labelLarge))
                .foregroundStyle(m3.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(m3.surfaceContainerHigh, in: RoundedRectangle(cornerRadius: M3Shape.large, style: .continuous))
    }

    @ViewBuilder
    private func ranking(_ title: LocalizedStringKey, entries: [RankedEntry], round: Bool) -> some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.m3(.titleMedium, weight: .semibold))
                    .foregroundStyle(m3.onSurface)
                VStack(spacing: 0) {
                    ForEach(Array(entries.prefix(5).enumerated()), id: \.element.id) { index, entry in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.m3(.titleMedium, weight: .bold).monospacedDigit())
                                .foregroundStyle(m3.primary)
                                .frame(width: 24)
                            AsyncImageView(url: entry.thumbnailUrl)
                                .frame(width: 48, height: 48)
                                .clipShape(round ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 10, style: .continuous)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.title)
                                    .font(.m3(.bodyLarge))
                                    .foregroundStyle(m3.onSurface)
                                    .lineLimit(1)
                                Text(detail(entry))
                                    .font(.m3(.bodySmall))
                                    .foregroundStyle(m3.onSurfaceVariant)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                    }
                }
                .background(m3.surfaceContainer, in: RoundedRectangle(cornerRadius: M3Shape.large, style: .continuous))
            }
        }
    }

    private func detail(_ entry: RankedEntry) -> String {
        let plays = String(format: String(localized: "%d plays"), entry.plays)
        let minutes = String(format: String(localized: "%d min"), entry.minutes)
        return [entry.subtitle, plays, minutes].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " • ")
    }

    private var hoursChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("By time of day")
                .font(.m3(.titleMedium, weight: .semibold))
            if let type = store.stats.listenerType {
                Text(type)
                    .font(.m3(.bodyMedium))
                    .foregroundStyle(m3.onSurfaceVariant)
            }
            Chart(Array(store.stats.hours.enumerated()), id: \.offset) { hour, minutes in
                BarMark(x: .value("Hour", hour), y: .value("Minutes", minutes))
                    .foregroundStyle(hour == store.stats.peakHour ? m3.primary : m3.primary.opacity(0.45))
                    .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                    AxisValueLabel { Text("\(value.as(Int.self) ?? 0):00") }
                }
            }
            .frame(height: 140)
        }
        .padding(16)
        .background(m3.surfaceContainer, in: RoundedRectangle(cornerRadius: M3Shape.large, style: .continuous))
    }

    private var weekdayChart: some View {
        let symbols = Self.mondayFirstWeekdaySymbols()
        return VStack(alignment: .leading, spacing: 8) {
            Text("By weekday")
                .font(.m3(.titleMedium, weight: .semibold))
            Chart(Array(store.stats.weekdays.enumerated()), id: \.offset) { index, minutes in
                BarMark(x: .value("Day", symbols[index]), y: .value("Minutes", minutes))
                    .foregroundStyle(m3.tertiary)
                    .cornerRadius(4)
            }
            .frame(height: 120)
        }
        .padding(16)
        .background(m3.surfaceContainer, in: RoundedRectangle(cornerRadius: M3Shape.large, style: .continuous))
    }

    static func mondayFirstWeekdaySymbols(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.shortWeekdaySymbols   // Sunday first
        return Array(symbols[1...]) + [symbols[0]]
    }

    private var resetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(role: .destructive) {
                confirmReset = true
            } label: {
                Label("Reset statistics", systemImage: "arrow.counterclockwise")
            }
            .accessibilityIdentifier("stats.reset")
            if let date = store.resetDate {
                HStack {
                    Text(String(format: String(localized: "Counting since %@"), date.formatted(date: .abbreviated, time: .shortened)))
                        .font(.m3(.bodySmall))
                        .foregroundStyle(m3.onSurfaceVariant)
                    Spacer()
                    Button("Undo") { Task { await store.undoReset() } }
                        .font(.m3(.labelLarge))
                }
            }
        }
        .padding(.top, 8)
    }
}

/// Grid of covers (recap card, story intro).
struct ArtworkWall: View {
    let urls: [String]
    var columns = 4
    var spacing: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let side = (geo.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            let rows = max(1, Int((geo.size.height + spacing) / (side + spacing)))
            let count = columns * rows
            let filled = urls.isEmpty ? [] : (0..<count).map { urls[$0 % urls.count] }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(side), spacing: spacing), count: columns), spacing: spacing) {
                ForEach(filled.indices, id: \.self) { index in
                    AsyncImageView(url: filled[index])
                        .frame(width: side, height: side)
                        .clipped()
                }
            }
        }
        .background(Color.black.opacity(0.2))
        .accessibilityHidden(true)
    }
}
