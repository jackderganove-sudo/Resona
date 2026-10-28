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
            log.info("AISYNC wav \(Int(audioSeconds)) s (song \(Int(duration)) s), 16 kHz mono")

            // 3) Transcription with word timestamps (whole song).
            phase = .transcribing(0)
            let language = LyricsLanguage.detect(texts.map { LyricLine(text: $0, startTime: nil) })
            let words = try await Self.transcribe(samples: samples, pipe: pipe, language: language) { done in
                Task { @MainActor in
                    if case .transcribing = AILyricsSync.shared.phase { AILyricsSync.shared.phase = .transcribing(done) }
                }
            }
            try Task.checkCancellation()

            // 4) Forced alignment onto the known lyrics.
            phase = .aligning
            let aligned = LyricsAligner.align(lines: texts, recognized: words, duration: max(duration, audioSeconds))
            log.info("AISYNC matched \(Int(aligned.matchedRatio * 100)) % of \(texts.count) lines' words")
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

    /// Whisper over the WHOLE song with word timestamps.
    /// • noSpeechThreshold off: with it WhisperKit skips an entire 30 s
    ///   window when the "no speech" probability is high — typical for
    ///   singing over loud music (only a fraction of the words came back).
    /// • compression-ratio limit raised: repeated choruses are not
    ///   hallucinations.
    /// Logs words per 30 s window (counts and times only, never text).
    nonisolated static func transcribe(samples: [Float], pipe: WhisperKit, language: String?,
                                       progress: @escaping @Sendable (Double) -> Void) async throws -> [RecognizedWord] {
        let audioSeconds = Double(samples.count) / 16_000
        var options = DecodingOptions(
            language: language,
            detectLanguage: language == nil,
            wordTimestamps: true,
            chunkingStrategy: .vad
        )
        options.noSpeechThreshold = nil
        options.compressionRatioThreshold = 3.0
        let total = max(30, audioSeconds)
        let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options, callback: { report in
            progress(min(0.99, Double(report.windowId + 1) * 30 / total))
            return nil
        })
        let segments = results.flatMap(\.segments)
        let words = segments.flatMap { $0.words ?? [] }
            .map { RecognizedWord(text: $0.word, start: Double($0.start), end: Double($0.end)) }
            .sorted { $0.start < $1.start }
        var buckets = [Int](repeating: 0, count: max(1, Int(ceil(audioSeconds / 30))))
        for word in words { buckets[min(buckets.count - 1, max(0, Int(word.start / 30)))] += 1 }
        Log.player.info("AISYNC transcribed \(words.count) words in \(segments.count) segments / \(results.count) results (lang=\(language ?? "auto"), audio=\(Int(audioSeconds)) s, last word at \(Int(words.last?.start ?? 0)) s); words per 30 s: \(buckets.map(String.init).joined(separator: " "))")
        return words
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

    /// Whole pipeline on a local audio file (tests): convert, load model
    /// (downloaded on first use, no Wi-Fi check), transcribe.
    nonisolated static func transcribeFile(_ path: String, variant: String, language: String?) async throws
        -> (words: [RecognizedWord], audioSeconds: Double) {
        let wav = FileManager.default.temporaryDirectory.appendingPathComponent("aisync-test-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: wav) }
        try await convertToWhisperWAV(input: path, output: wav)
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: wav.path)
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("whisperkit", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let folder = try await WhisperKit.download(variant: variant, downloadBase: base)
        let pipe = try await WhisperKit(WhisperKitConfig(modelFolder: folder.path, verbose: false, download: false))
        let words = try await transcribe(samples: samples, pipe: pipe, language: language) { _ in }
        return (words, Double(samples.count) / 16_000)
    }

    /// Local download or stream → temporary 16 kHz mono WAV (ffmpeg).
    private static func prepareAudio(videoId: String) async throws -> URL {
        var input: String?
        var source = "download"
        if let local = await DownloadManager.shared.localURL(for: videoId) {
            input = local.path
        } else if let cached = await StreamCache.shared.get(videoId: videoId) {
            input = cached.streamUrl
            source = "stream (cached)"
        } else {
            var request = StreamResolveRequest.playback(videoId: videoId)
            request.options.audioQuality = await MainActor.run { SettingsStore.shared.audioQuality }
            let result = try await StreamFallback.resolveFirstValid(request, using: InnerTubeClient.tropShared, providers: .tropLive)
            input = result.streamUrl
            source = "stream (resolved)"
        }
        guard let input else { throw SyncError.message(String(localized: "No audio source found.")) }
        Log.player.info("AISYNC audio source: \(source)")
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("aisync-\(videoId).wav")
        try await convertToWhisperWAV(input: input, output: output)
        return output
    }

    /// ffmpeg → 16 kHz mono 16-bit WAV. Same network options as the
    /// download (CA bundle — ffmpeg-kit's OpenSSL has no system trust store
    /// —, user agent, timeout): without them HTTPS streams failed with
    /// "The audio could not be converted."
    nonisolated static func convertToWhisperWAV(input: String, output: URL) async throws {
        try? FileManager.default.removeItem(at: output)
        var arguments = ["-y"]
        if input.hasPrefix("http") {
            arguments += ["-rw_timeout", "30000000"]
            if let caPath = Bundle.main.path(forResource: "cacert", ofType: "pem") {
                arguments += ["-cafile", caPath]
            }
            arguments += ["-headers", "User-Agent: Mozilla/5.0\r\n"]
        }
        arguments += ["-i", input, "-vn", "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", output.path]
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            FFmpegKit.execute(withArgumentsAsync: arguments) { session in
                if ReturnCode.isSuccess(session?.getReturnCode()) {
                    continuation.resume()
                } else {
                    let code = session?.getReturnCode()?.getValue() ?? -1
                    let tail = (session?.getOutput() ?? "").split(separator: "\n").suffix(3).joined(separator: " | ")
                    Log.player.error("AISYNC ffmpeg failed rc=\(code): \(tail)")
                    continuation.resume(throwing: SyncError.message(String(localized: "The audio could not be converted.")))
                }
            }
        }
        let bytes = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        Log.player.info("AISYNC wav written: \(bytes / 32_000) s (\(bytes) bytes)")
    }
}
