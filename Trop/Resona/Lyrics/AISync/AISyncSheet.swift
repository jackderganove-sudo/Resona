//
//  AISyncSheet.swift
//  Resona
//
//  Progress UI for "Sync with AI". The job keeps running when the sheet is
//  closed (as long as the app is open).
//

import SwiftUI

struct AISyncSheet: View {
    let videoId: String
    let duration: Double

    @Environment(\.dismiss) private var dismiss
    @Environment(\.m3) private var m3
    @Environment(SettingsStore.self) private var settings
    private let engine = AILyricsSync.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(m3.primary)
                Text("Sync with AI")
                    .font(.m3(.headlineSmall))
                    .foregroundStyle(m3.onSurface)
                Text("The song is transcribed on this device (WhisperKit) and the words are matched to the lyrics. Result: word-synced lyrics for this song, stored locally.")
                    .font(.m3(.bodyMedium))
                    .foregroundStyle(m3.onSurfaceVariant)
                    .multilineTextAlignment(.center)

                status
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(m3.surfaceContainerHighest, in: RoundedRectangle(cornerRadius: M3Shape.large, style: .continuous))

                Spacer()

                if engine.isRunning, engine.videoId == videoId {
                    Button(role: .destructive) { engine.cancel() } label: {
                        Text("Cancel").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.m3Tonal)
                } else if case .done = engine.phase, engine.videoId == videoId {
                    Button { dismiss() } label: { Text("Done").frame(maxWidth: .infinity) }
                        .buttonStyle(.m3Filled)
                } else {
                    Button {
                        Task {
                            let lines = await LyricsService.shared.currentLines(videoId: videoId)
                            engine.start(videoId: videoId, lines: lines, duration: duration)
                        }
                    } label: {
                        Label("Start", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.m3Filled)
                    .disabled(engine.isRunning)
                }
            }
            .padding(20)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .navigationTitle("Sync with AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(engine.isRunning ? String(localized: "Keep running") : String(localized: "Close")) { dismiss() }
                }
            }
        }
        .presentationBackground { ResonaGlassBackground() }
        .onAppear { if engine.videoId != videoId { engine.reset() } }
    }

    @ViewBuilder
    private var status: some View {
        let mine = engine.videoId == videoId
        switch mine ? engine.phase : .idle {
        case .idle:
            VStack(spacing: 6) {
                Text(String(format: String(localized: "Model: %@"), String(localized: String.LocalizationValue(settings.aiSyncModel.displayName))))
                Text("Downloaded once on Wi-Fi, then works offline.")
                    .foregroundStyle(m3.onSurfaceVariant)
            }
            .font(.m3(.bodyMedium))
        case .downloadingModel(let fraction):
            progress("Downloading the AI model…", fraction)
        case .preparingAudio:
            progress("Preparing the audio…", nil)
        case .transcribing(let fraction):
            progress("Listening to the song…", fraction)
        case .aligning:
            progress("Matching words to the lyrics…", nil)
        case .done(let matched):
            Label(String(format: String(localized: "Done — %d %% of the words recognized."), Int(matched * 100)), systemImage: "checkmark.circle")
                .font(.m3(.bodyLarge))
                .foregroundStyle(m3.primary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.m3(.bodyMedium))
                .foregroundStyle(m3.error)
        }
    }

    private func progress(_ title: LocalizedStringKey, _ fraction: Double?) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.m3(.bodyLarge))
                .foregroundStyle(m3.onSurface)
            if let fraction {
                ProgressView(value: fraction)
                    .tint(m3.primary)
                Text("\(Int(fraction * 100)) %")
                    .font(.m3(.labelMedium).monospacedDigit())
                    .foregroundStyle(m3.onSurfaceVariant)
            } else {
                ProgressView()
                    .tint(m3.primary)
            }
        }
    }
}
