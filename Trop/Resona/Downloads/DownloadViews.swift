//
//  DownloadViews.swift
//  Resona
//
//  Download status UI driven live by DownloadManager:
//  • DownloadStatusIndicator — per-song badge (queued clock, progress ring,
//    downloaded check) for every song list.
//  • CollectionDownloadButton — playlist/album header button with the
//    overall progress ring; tap to download, cancel or remove.
//

import SwiftUI

// MARK: - Per-song indicator

struct DownloadStatusIndicator: View {
    @Environment(\.m3) private var m3
    @ObservedObject private var manager = DownloadManager.shared
    let videoId: String
    var size: CGFloat = 14

    var body: some View {
        Group {
            switch manager.state(for: videoId) {
            case .notStarted:
                EmptyView()
            case .queued:
                Image(systemName: "clock")
                    .font(.system(size: size * 0.85, weight: .semibold))
                    .foregroundStyle(m3.onSurfaceVariant.opacity(0.7))
                    .accessibilityLabel(Text("Waiting to download"))
            case .downloading(let progress):
                ZStack {
                    Circle().stroke(m3.primary.opacity(0.25), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: max(0.03, progress))
                        .stroke(m3.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(M3Motion.fastEffects, value: progress)
                }
                .frame(width: size, height: size)
                .accessibilityLabel(Text("Downloading"))
                .accessibilityValue(Text("\(Int(progress * 100)) %"))
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(m3.primary)
                    .accessibilityLabel(Text("Downloaded"))
            case .failed:
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(m3.error)
                    .accessibilityLabel(Text("Download failed"))
            }
        }
        .transition(.scale.combined(with: .opacity))
        .animation(M3Motion.fastSpatial, value: manager.state(for: videoId))
    }
}

// MARK: - Collection button

/// Aggregate download state of a set of songs.
struct CollectionDownloadStatus: Equatable {
    var total = 0
    var completed = 0
    var active = 0
    var partial: Double = 0

    var isComplete: Bool { total > 0 && completed == total }
    var isRunning: Bool { active > 0 }
    /// Finished songs / all songs (running songs count fractionally so the
    /// ring moves smoothly between song completions).
    var fraction: Double { total == 0 ? 0 : (Double(completed) + partial) / Double(total) }

    @MainActor
    init(songs: [SongItem], manager: DownloadManager) {
        total = songs.count
        for song in songs {
            switch manager.state(for: song.videoId) {
            case .completed: completed += 1
            case .queued: active += 1
            case .downloading(let p):
                active += 1
                partial += p
            case .notStarted, .failed: break
            }
        }
    }
}

struct CollectionDownloadButton: View {
    @Environment(\.m3) private var m3
    @ObservedObject private var manager = DownloadManager.shared
    let songs: [SongItem]
    var diameter: CGFloat = 52
    /// YouTube playlist this button belongs to: downloading it registers the
    /// playlist for automatic updates, removing the downloads unregisters it.
    var collection: (id: String, title: String)?

    @State private var confirmRemove = false

    var body: some View {
        let status = CollectionDownloadStatus(songs: songs, manager: manager)
        Button {
            if status.isRunning {
                manager.cancel(videoIds: songs.map(\.videoId))
            } else if status.isComplete {
                confirmRemove = true
            } else {
                manager.enqueue(songs)
                if let collection {
                    DownloadedPlaylistStore.shared.register(id: collection.id, title: collection.title, songIds: songs.map(\.videoId))
                }
            }
        } label: {
            ZStack {
                Circle().fill(status.isComplete ? m3.primaryContainer : .white.opacity(0.16))
                if status.isRunning {
                    Circle()
                        .stroke(.white.opacity(0.22), lineWidth: 3)
                        .padding(3)
                    Circle()
                        .trim(from: 0, to: max(0.02, status.fraction))
                        .stroke(m3.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(3)
                        .animation(M3Motion.defaultEffects, value: status.fraction)
                }
                Image(systemName: icon(for: status))
                    .font(.system(size: status.isRunning ? 15 : 20, weight: .semibold))
                    .foregroundStyle(status.isComplete ? m3.onPrimaryContainer : .white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: diameter, height: diameter)
        }
        .buttonStyle(.expressive(scale: 0.88))
        .sensoryFeedback(.success, trigger: status.isComplete) { _, done in done }
        .accessibilityLabel(Text(accessibility(for: status)))
        .confirmationDialog("Remove downloads?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove Download", role: .destructive) {
                Task { await manager.delete(videoIds: songs.map(\.videoId)) }
                if let collection { DownloadedPlaylistStore.shared.unregister(id: collection.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The songs stay in the playlist and stream again when online.")
        }
    }

    private func icon(for status: CollectionDownloadStatus) -> String {
        if status.isRunning { return "stop.fill" }
        if status.isComplete { return "checkmark" }
        return "arrow.down"
    }

    private func accessibility(for status: CollectionDownloadStatus) -> LocalizedStringKey {
        if status.isRunning { return "Cancel download" }
        if status.isComplete { return "Downloaded" }
        return "Download"
    }
}
