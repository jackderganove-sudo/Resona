//
//  AISyncSheet.swift
//  Resona
//
//  "Sync with AI" for every song. Synced lyrics are first CALIBRATED
//  (kept, only tempo + offset fitted to this recording); when that has no
//  good fit — and for plain text — the lyrics are fully synced word by
//  word. When little of the lyrics is sung (remix / wrong lyrics) the user
//  chooses: sync only the matching lines, lyrics from audio, or search
//  other lyrics. The job keeps running when the sheet is closed.
//

import SwiftUI

struct AISyncSheet: View {
    let videoId: String
    let duration: Double

    @Environment(\.dismiss) private var dismiss
    @Environment(\.m3) private var m3
    @Environment(SettingsStore.self) private var settings
    private let engine = AILyricsSync.shared
    private let np = NowPlaying.shared
    @State private var currentSynced = false
    @State private var showSearch = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 44, weight: .medium))
                        .foregroundStyle(m3.primary)
                    Text("Sync with AI")
                        .font(.m3(.headlineSmall))
                        .foregroundStyle(m3.onSurface)
                    Text(currentSynced
                         ? LocalizedStringKey("The song is transcribed on this device (WhisperKit). Synced lyrics are kept and only their tempo and offset are fitted to this recording; if that doesn't fit, they are synced word by word.")
                         : LocalizedStringKey("The song is transcribed on this device (WhisperKit) and the words are matched to the lyrics. Result: word-synced lyrics for this song, stored locally."))
                        .font(.m3(.bodyMedium))
                        .foregroundStyle(m3.onSurfaceVariant)
                        .multilineTextAlignment(.center)

                    status
                        .frame(maxWidth: .infinity)
                        .padding(16)
                        .background(m3.surfaceContainerHighest, in: RoundedRectangle(cornerRadius: M3Shape.large, style: .continuous))

                    actions
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Sync with AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(engine.isRunning ? String(localized: "Keep running") : String(localized: "Close")) { dismiss() }
                }
            }
        }
        .presentationBackground { ResonaGlassBackground() }
        .sheet(isPresented: $showSearch) {
            SearchLyricsSheet(videoId: videoId, defaultTitle: np.title, defaultArtist: np.displayArtist, duration: duration)
        }
        .onAppear { if engine.videoId != videoId { engine.reset() } }
        .task {
            let lines = await LyricsService.shared.currentLines(videoId: videoId)
            currentSynced = lines.contains { $0.startTime != nil }
        }
    }

    // MARK: Buttons

    @ViewBuilder
    private var actions: some View {
        let mine = engine.videoId == videoId
        if engine.isRunning, mine {
            Button(role: .destructive) { engine.cancel() } label: {
                Text("Cancel").frame(maxWidth: .infinity)
            }
            .buttonStyle(.m3Tonal)
        } else if mine, case .lowMatch(_, let partialLines) = engine.phase {
            VStack(spacing: 10) {
                if partialLines >= 2 {
                    Button {
                        Task { await engine.savePartialSync() }
                    } label: {
                        Label("Only sync the matching lines", systemImage: "text.line.first.and.arrowtriangle.forward")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.m3Filled)
                }
                Button {
                    Task { await engine.saveTranscriptionAsLyrics() }
                } label: {
                    Label("Create lyrics from the audio", systemImage: "waveform.and.mic")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.m3Tonal)
                Button {
                    showSearch = true
                } label: {
                    Label("Search other lyrics", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.m3Tonal)
            }
        } else if mine, isFinished {
            Button { dismiss() } label: { Text("Done").frame(maxWidth: .infinity) }
                .buttonStyle(.m3Filled)
        } else {
            VStack(spacing: 10) {
                Button {
                    start(.auto)
                } label: {
                    Label(currentSynced ? LocalizedStringKey("Calibrate with AI") : LocalizedStringKey("Start"), systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.m3Filled)
                .disabled(engine.isRunning)
                if currentSynced {
                    Button {
                        start(.fullSync)
                    } label: {
                        Text("Sync word by word instead").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.m3Tonal)
                    .disabled(engine.isRunning)
                }
            }
        }
    }

    private var isFinished: Bool {
        switch engine.phase {
        case .done, .calibrated: return true
        default: return false
        }
    }

    private func start(_ mode: AILyricsSync.Mode) {
        Task {
            let lines = await LyricsService.shared.currentLines(videoId: videoId)
            engine.start(videoId: videoId, lines: lines, duration: duration, mode: mode)
        }
    }

    // MARK: Status

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
        case .calibrated(let calibration):
            Label(String(format: String(localized: "Calibrated: tempo %@, offset %@ (%d anchor points). The lyrics stay as they are."),
                         String(format: "%.3f×", calibration.factor), String(format: "%+.1f s", calibration.offset), calibration.anchors),
                  systemImage: "checkmark.circle")
                .font(.m3(.bodyLarge))
                .foregroundStyle(m3.primary)
        case .calibrationFailed(let anchors):
            Label(String(format: String(localized: "AI calibration: only %d reliable anchor points — the calculated tempo stays."), anchors),
                  systemImage: "exclamationmark.triangle")
                .font(.m3(.bodyMedium))
                .foregroundStyle(m3.onSurfaceVariant)
        case .lowMatch(let ratio, _):
            Label(String(format: String(localized: "Only %d %% of the lyrics are sung in this song — maybe a remix or the wrong lyrics?"), Int(ratio * 100)),
                  systemImage: "questionmark.circle")
                .font(.m3(.bodyMedium))
                .foregroundStyle(m3.onSurface)
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
