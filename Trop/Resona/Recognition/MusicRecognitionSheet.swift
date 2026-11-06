//
//  MusicRecognitionSheet.swift
//  Resona
//
//  The recognition sheet: listen, show the song, play it; earlier results below.
//

import SwiftUI

struct MusicRecognitionSheet: View {
    @Environment(\.m3) private var m3
    @Environment(\.dismiss) private var dismiss
    private let recognition = MusicRecognition.shared
    @State private var playFailed = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    stateView
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                if !recognition.history.isEmpty {
                    Section {
                        ForEach(recognition.history) { song in
                            Button {
                                open(song)
                            } label: {
                                songRow(song)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                        }
                    } header: {
                        HStack {
                            Text("Recognized songs")
                            Spacer()
                            Button("Clear", action: recognition.clearHistory)
                                .font(.m3(.labelMedium))
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .navigationTitle("Recognize music")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("recognition.close")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { if recognition.phase == .idle { recognition.start() } }
        .onDisappear { recognition.cancel() }
    }

    @ViewBuilder
    private var stateView: some View {
        switch recognition.phase {
        case .idle, .listening:
            let progress = if case .listening(let value) = recognition.phase { value } else { 0.0 }
            status(icon: "waveform", title: "Listening…", text: "Hold your iPad close to the music.")
            ProgressView(value: progress)
                .frame(maxWidth: 320)
                .padding(.top, 12)
        case .identifying:
            status(icon: "magnifyingglass", title: "Identifying…", text: nil)
            ProgressView()
                .padding(.top, 12)
        case .found(let song):
            found(song)
        case .noMatch:
            status(icon: "questionmark.circle", title: "No match found", text: "Try again closer to the music.")
            retry
        case .denied:
            status(icon: "mic.slash", title: "Microphone access is off", text: "Allow the microphone for Resona in the iPad's Settings app.")
        case .failed:
            status(icon: "exclamationmark.triangle", title: "Recognition failed", text: "Check your connection and try again.")
            retry
        }
    }

    private func status(icon: String, title: LocalizedStringKey, text: LocalizedStringKey?) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(m3.primary)
                .symbolEffect(.pulse, isActive: icon == "waveform")
            Text(title)
                .font(.m3(.titleMedium))
                .foregroundStyle(m3.onSurface)
            if let text {
                Text(text)
                    .font(.m3(.bodyMedium))
                    .foregroundStyle(m3.onSurfaceVariant)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func found(_ song: RecognizedSong) -> some View {
        VStack(spacing: 12) {
            cover(song, size: 160)
            VStack(spacing: 2) {
                Text(song.title)
                    .font(.m3(.titleLarge))
                    .foregroundStyle(m3.onSurface)
                    .accessibilityIdentifier("recognition.title")
                Text(song.artist)
                    .font(.m3(.bodyLarge))
                    .foregroundStyle(m3.onSurfaceVariant)
            }
            .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button {
                    open(song)
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(M3ButtonStyle(variant: .filled))
                .disabled(recognition.isOpeningSong)
                .accessibilityIdentifier("recognition.play")
                Button("Listen again", action: recognition.start)
                    .buttonStyle(M3ButtonStyle(variant: .tonal))
            }
            if playFailed {
                Text("Couldn't find this song on YouTube Music.")
                    .font(.m3(.bodyMedium))
                    .foregroundStyle(m3.error)
            }
        }
    }

    private var retry: some View {
        Button("Listen again", action: recognition.start)
            .buttonStyle(M3ButtonStyle(variant: .tonal))
            .padding(.top, 12)
    }

    private func songRow(_ song: RecognizedSong) -> some View {
        HStack(spacing: 12) {
            cover(song, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.m3(.titleSmall))
                    .foregroundStyle(m3.onSurface)
                    .lineLimit(1)
                Text(song.artist)
                    .font(.m3(.bodySmall))
                    .foregroundStyle(m3.onSurfaceVariant)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private func cover(_ song: RecognizedSong, size: CGFloat) -> some View {
        AsyncImage(url: song.coverURL.flatMap(URL.init(string:))) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            m3.surfaceContainerHighest
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size > 100 ? M3Shape.large : M3Metrics.thumbnailRadius, style: .continuous))
        .accessibilityHidden(true)
    }

    private func open(_ song: RecognizedSong) {
        playFailed = false
        Task {
            if await recognition.play(song) {
                dismiss()
            } else {
                playFailed = true
            }
        }
    }
}
