//
//  AILyricsSync.swift
//  Resona
//
//  "Sync with AI": WhisperKit (on-device, Neural Engine) transcribes the
//  song with word timestamps; LyricsAligner maps those onto the existing
//  lyrics; the result is saved per song as word-synced custom lyrics
//  ("AI-synced", priority over providers, resettable, re-syncable).
//
//  • Model: downloaded on first use (Wi-Fi only) into Application Support,
//    never bundled. "Fast (small)" = whisper base, "Accurate (larger)" =
//    whisper small.
//  • Audio: the downloaded file, otherwise the stream (resolved URL) —
//    converted with ffmpeg to 16 kHz mono WAV in a temp file. Slowed /
//    sped-up uploads are transcribed as they are (no scaling needed).
//  • Runs in the background while the app is open; cancellable.
//

import Foundation
import NaturalLanguage
import Observation
import WhisperKit
import ffmpegkit

enum AISyncModel: String, CaseIterable, Identifiable, SettingsOption {
    case fast
    case accurate

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fast: return "Fast (small, ~150 MB)"
        case .accurate: return "Accurate (larger, ~500 MB)"
        }
    }

    var variant: String {
        switch self {
        case .fast: return "openai_whisper-base"
        case .accurate: return "openai_whisper-small"
        }
    }
}

@MainActor
@Observable
final class AILyricsSync {
    static let shared = AILyricsSync()

    enum Phase: Equatable {
        case idle
        case downloadingModel(Double)
        case preparingAudio
        case transcribing(Double)
        case aligning
        case done(matched: Double)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var videoId: String?
    private var task: Task<Void, Never>?
    private var pipe: WhisperKit?
    private var loadedVariant: String?

    static let providerName = "AI-synced"

    var isRunning: Bool {
        switch phase {
        case .downloadingModel, .preparingAudio, .transcribing, .aligning: return true
        default: return false
        }
    }

    private static var modelBase: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("whisperkit", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func start(videoId: String, lines: [LyricLine], duration: Double) {
        guard !isRunning else { return }
        self.videoId = videoId
        let texts = lines.map(\.text).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard texts.count >= 2 else {
            phase = .failed(String(localized: "No lyrics text to align."))
            return
        }
        task = Task { [weak self] in
            await self?.run(videoId: videoId, texts: texts, duration: duration)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        phase = .idle
    }

    func reset() {
        if !isRunning { phase = .idle }
    }

    // MARK: Pipeline

    private func run(videoId: String, texts: [String], duration: Double) async {
        let log = Log.player
        do {
            // 1) Model (Wi-Fi only for the download).
            let variant = SettingsStore.shared.aiSyncModel.variant
            if pipe == nil || loadedVariant != variant {
                let folder = try await modelFolder(variant: variant)
                try Task.checkCancellation()
                phase = .downloadingModel(1)
                pipe = try await WhisperKit(WhisperKitConfig(modelFolder: folder.path, verbose: false, download: false))
                loadedVariant = variant
            }
            guard let pipe else { throw SyncError.message(String(localized: "Model could not be loaded.")) }

            // 2) Audio → 16 kHz mono WAV.
            phase = .preparingAudio
            let wav = try await Self.prepareAudio(videoId: videoId)
            defer { try? FileManager.default.removeItem(at: wav) }
            try Task.checkCancellation()
            let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: wav.path)
            let audioSeconds = Double(samples.count) / 16_000

            // 3) Transcription with word timestamps.
            phase = .transcribing(0)
            let language = LyricsLanguage.detect(texts.map { LyricLine(text: $0, startTime: nil) })
            let options = DecodingOptions(
                language: language,
                detectLanguage: language == nil,
                wordTimestamps: true,
                chunkingStrategy: .vad
            )
            let total = max(30, audioSeconds)
            let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options, callback: { progress in
                let done = min(0.99, Double(progress.windowId + 1) * 30 / total)
                Task { @MainActor in
                    if case .transcribing = AILyricsSync.shared.phase { AILyricsSync.shared.phase = .transcribing(done) }
                }
                return Task.isCancelled ? false : nil
            })
            try Task.checkCancellation()
            let words = results.flatMap(\.segments).flatMap { $0.words ?? [] }
                .map { RecognizedWord(text: $0.word, start: Double($0.start), end: Double($0.end)) }
            log.info("AISYNC transcribed \(words.count) words (lang=\(language ?? "auto"), audio=\(Int(audioSeconds)) s)")

            // 4) Forced alignment onto the known lyrics.
            phase = .aligning
            let aligned = LyricsAligner.align(lines: texts, recognized: words, duration: max(duration, audioSeconds))
            log.info("AISYNC matched \(Int(aligned.matchedRatio * 100)) % of lyric words")
            guard aligned.matchedRatio >= 0.3 else {
                throw SyncError.message(String(format: String(localized: "Only %d %% of the words were recognized — not reliable enough."), Int(aligned.matchedRatio * 100)))
            }

            // 5) Save as word-synced custom lyrics.
            let raw = LyricsParsing.serializeLines(aligned.lines)
            await LyricsService.shared.saveCustom(videoId: videoId, rawText: raw, providerName: Self.providerName)
            phase = .done(matched: aligned.matchedRatio)
        } catch is CancellationError {
            phase = .idle
        } catch let SyncError.message(text) {
            phase = .failed(text)
        } catch {
            log.error("AISYNC failed: \(error)")
            phase = .failed(error.localizedDescription)
        }
    }

    private enum SyncError: Error { case message(String) }

    /// Downloaded model folder (downloads it on Wi-Fi when missing).
    private func modelFolder(variant: String) async throws -> URL {
        let marker = Self.modelBase.appendingPathComponent("\(variant).ready")
        if let path = try? String(contentsOf: marker, encoding: .utf8),
           FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        guard DownloadManager.shared.isOnWiFi else {
            throw SyncError.message(String(localized: "The AI model is downloaded on Wi-Fi only. Connect to Wi-Fi and try again."))
        }
        phase = .downloadingModel(0)
        let folder = try await WhisperKit.download(variant: variant, downloadBase: Self.modelBase) { progress in
            let fraction = progress.fractionCompleted
            Task { @MainActor in AILyricsSync.shared.phase = .downloadingModel(fraction) }
        }
        try? folder.path.write(to: marker, atomically: true, encoding: .utf8)
        return folder
    }

    /// Local download or stream → temporary 16 kHz mono WAV (ffmpeg).
    private static func prepareAudio(videoId: String) async throws -> URL {
        var input: String?
        if let local = await DownloadManager.shared.localURL(for: videoId) {
            input = local.path
        } else if let cached = await StreamCache.shared.get(videoId: videoId) {
            input = cached.streamUrl
        } else {
            var request = StreamResolveRequest.playback(videoId: videoId)
            request.options.audioQuality = await MainActor.run { SettingsStore.shared.audioQuality }
            let result = try await StreamFallback.resolveFirstValid(request, using: InnerTubeClient.tropShared, providers: .tropLive)
            input = result.streamUrl
        }
        guard let input else { throw SyncError.message(String(localized: "No audio source found.")) }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("aisync-\(videoId).wav")
        try? FileManager.default.removeItem(at: output)
        let arguments = ["-y", "-i", input, "-vn", "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", output.path]
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            FFmpegKit.execute(withArgumentsAsync: arguments) { session in
                if ReturnCode.isSuccess(session?.getReturnCode()) {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: SyncError.message(String(localized: "The audio could not be converted.")))
                }
            }
        }
        return output
    }
}
