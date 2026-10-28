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

/// What Whisper heard: all words, and the words grouped per segment
/// (used as lines for "lyrics from audio").
struct Transcription: Sendable {
    let words: [RecognizedWord]
    let segments: [[RecognizedWord]]
    let audioSeconds: Double
}

@MainActor
@Observable
final class AILyricsSync {
    static let shared = AILyricsSync()

    /// auto: synced lyrics are calibrated when the fit is good, otherwise
    /// (and for plain text) fully synced.
    enum Mode: Equatable { case auto, calibrate, fullSync }

    enum Phase: Equatable {
        case idle
        case downloadingModel(Double)
        case preparingAudio
        case transcribing(Double)
        case aligning
        case done(matched: Double)
        /// Synced lyrics kept, mapped onto this recording.
        case calibrated(TempoCalibration)
        /// Calibration only (slowed check) without a reliable fit.
        case calibrationFailed(anchors: Int)
        /// Little of the lyrics is sung here (remix / wrong lyrics).
        case lowMatch(ratio: Double, partialLines: Int)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var videoId: String?
    private var task: Task<Void, Never>?
    private var pipe: WhisperKit?
    private var loadedVariant: String?
    /// Last transcription (per song) for the options after a low match.
    private var lastTranscription: (videoId: String, transcription: Transcription, texts: [String])?
    /// Songs whose automatic calibration already ran in this session.
    private(set) var autoCalibrated: Set<String> = []

    static let providerName = "AI-synced"
    static let transcribedProviderName = "AI-transcribed"

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

    func start(videoId: String, lines: [LyricLine], duration: Double, mode: Mode = .auto) {
        guard !isRunning else { return }
        self.videoId = videoId
        if mode == .calibrate { autoCalibrated.insert(videoId) }
        let texts = lines.map(\.text).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard texts.count >= 2 else {
            phase = .failed(String(localized: "No lyrics text to align."))
            return
        }
        // Calibration works on the provider's ORIGINAL times (automatic
        // slowed/sped-up scaling undone).
        let auto = LyricsState.shared.autoTempo[videoId] ?? 1
        let synced = lines.contains { $0.startTime != nil }
        let originals = synced ? LyricLine.scaled(lines, by: 1 / auto) : []
        task = Task { [weak self] in
            await self?.run(videoId: videoId, texts: texts, originals: originals, duration: duration, mode: mode)
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

    private func run(videoId: String, texts: [String], originals: [LyricLine], duration: Double, mode: Mode) async {
        let log = Log.player
        do {
            let transcription = try await transcribeSong(videoId: videoId, duration: duration)
            lastTranscription = (videoId, transcription, texts)
            let audioSeconds = transcription.audioSeconds

            // A) Calibrate synced lyrics (keep them, fix tempo + offset).
            if !originals.isEmpty, mode != .fullSync {
                phase = .aligning
                let anchors = LyricsAligner.anchors(lines: originals, recognized: transcription.words)
                let outcome = TempoCalibrator.fit(anchors)
                switch outcome {
                case .fitted(let calibration):
                    log.info("AISYNC calibration factor=\(String(format: "%.4f", calibration.factor)) offset=\(String(format: "%.2f", calibration.offset)) s inliers=\(calibration.anchors)/\(anchors.count) rms=\(String(format: "%.2f", calibration.rms))")
                    LyricsCalibrationStore.shared.set(calibration, for: videoId)
                    LyricsState.shared.refreshToken += 1
                    phase = .calibrated(calibration)
                    return
                case .tooFewAnchors(let count):
                    log.info("AISYNC calibration: only \(count) anchors")
                    if mode == .calibrate { phase = .calibrationFailed(anchors: count); return }
                case .poorFit(let calibration):
                    log.info("AISYNC calibration: poor fit (factor \(String(format: "%.3f", calibration.factor)), rms \(String(format: "%.2f", calibration.rms)), \(calibration.anchors) inliers)")
                    if mode == .calibrate { phase = .calibrationFailed(anchors: calibration.anchors); return }
                }
            }

            // B) Full sync: the lyrics' words matched to the recognition.
            phase = .aligning
            let aligned = LyricsAligner.align(lines: texts, recognized: transcription.words, duration: max(duration, audioSeconds))
            log.info("AISYNC matched \(Int(aligned.matchedRatio * 100)) % of \(texts.count) lines' words")
            if aligned.matchedRatio >= 0.3 {
                let raw = LyricsParsing.serializeLines(aligned.lines)
                await LyricsService.shared.saveCustom(videoId: videoId, rawText: raw, providerName: Self.providerName)
                phase = .done(matched: aligned.matchedRatio)
                return
            }
            // Little matches: probably a remix (only parts of the lyrics)
            // or the wrong lyrics — offer partial sync / transcription.
            let occurrences = LyricsAligner.lineOccurrences(lines: texts, recognized: transcription.words)
            log.info("AISYNC low match: \(occurrences.count) sung line occurrences found")
            phase = .lowMatch(ratio: aligned.matchedRatio, partialLines: occurrences.count)
        } catch is CancellationError {
            phase = .idle
        } catch let SyncError.message(text) {
            phase = .failed(text)
        } catch {
            log.error("AISYNC failed: \(error)")
            phase = .failed(error.localizedDescription)
        }
    }

    /// "Only sync the matching lines": every sung occurrence (repeats
    /// included) becomes a timed line; the rest of the lyrics is left out.
    func savePartialSync() async {
        guard let last = lastTranscription, last.videoId == videoId else { return }
        let occurrences = LyricsAligner.lineOccurrences(lines: last.texts, recognized: last.transcription.words)
        guard occurrences.count >= 2 else { return }
        let lines = occurrences.map {
            LyricLine(text: last.texts[$0.lineIndex], startTime: $0.start, words: $0.words.count > 1 ? $0.words : nil)
        }
        await LyricsService.shared.saveCustom(videoId: last.videoId, rawText: LyricsParsing.serializeLines(lines), providerName: Self.providerName)
        Log.player.info("AISYNC partial sync saved: \(lines.count) lines")
        phase = .done(matched: Double(lines.count) / Double(max(1, last.texts.count)))
    }

    /// "Lyrics from audio": the transcription itself, one line per Whisper
    /// segment, marked as AI-transcribed.
    func saveTranscriptionAsLyrics() async {
        guard let last = lastTranscription, last.videoId == videoId else { return }
        let lines: [LyricLine] = last.transcription.segments.compactMap { segment in
            let words = segment.filter { !LyricsAligner.normalize($0.text).isEmpty }
            guard let first = words.first else { return nil }
            let lyricWords = words.enumerated().map { index, word in
                LyricWord(text: word.text.trimmingCharacters(in: .whitespaces) + (index < words.count - 1 ? " " : ""),
                          start: word.start, end: max(word.end, word.start + 0.05))
            }
            let text = lyricWords.map(\.text).joined().trimmingCharacters(in: .whitespaces)
            return LyricLine(text: text, startTime: first.start, words: lyricWords.count > 1 ? lyricWords : nil)
        }
        guard !lines.isEmpty else { return }
        await LyricsService.shared.saveCustom(videoId: last.videoId, rawText: LyricsParsing.serializeLines(LyricLine.monotonicTiming(lines)),
                                              providerName: Self.transcribedProviderName)
        Log.player.info("AISYNC transcription saved as lyrics: \(lines.count) lines")
        phase = .done(matched: 1)
    }

    /// Model + audio + Whisper (larger model when the small one hears too
    /// little: fewer than 3 words per 10 s).
    private func transcribeSong(videoId: String, duration: Double) async throws -> Transcription {
        let log = Log.player
        let variant = SettingsStore.shared.aiSyncModel.variant
        if pipe == nil || loadedVariant != variant {
            let folder = try await modelFolder(variant: variant)
            try Task.checkCancellation()
            phase = .downloadingModel(1)
            pipe = try await WhisperKit(WhisperKitConfig(modelFolder: folder.path, verbose: false, download: false))
            loadedVariant = variant
        }
        guard let pipe else { throw SyncError.message(String(localized: "Model could not be loaded.")) }

        phase = .preparingAudio
        let wav = try await Self.prepareAudio(videoId: videoId)
        defer { try? FileManager.default.removeItem(at: wav) }
        try Task.checkCancellation()
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: wav.path)
        let audioSeconds = Double(samples.count) / 16_000
        log.info("AISYNC wav \(Int(audioSeconds)) s (song \(Int(duration)) s), 16 kHz mono")

        phase = .transcribing(0)
        let current = await LyricsService.shared.currentLines(videoId: videoId)
        let language = LyricsLanguage.detect(current)
        let progress: @Sendable (Double) -> Void = { done in
            Task { @MainActor in
                if case .transcribing = AILyricsSync.shared.phase { AILyricsSync.shared.phase = .transcribing(done) }
            }
        }
        var result = try await Self.transcribe(samples: samples, pipe: pipe, language: language, progress: progress)
        try Task.checkCancellation()
        if Double(result.words.count) < audioSeconds * 0.3, variant == AISyncModel.fast.variant {
            let larger = AISyncModel.accurate.variant
            log.info("AISYNC few words with \(variant) → trying \(larger)")
            if let folder = try? await modelFolder(variant: larger) {
                let largePipe = try await WhisperKit(WhisperKitConfig(modelFolder: folder.path, verbose: false, download: false))
                phase = .transcribing(0)
                let second = try await Self.transcribe(samples: samples, pipe: largePipe, language: language, progress: progress)
                if second.words.count > result.words.count { result = second }
            } else {
                log.info("AISYNC larger model not available (Wi-Fi needed for the download)")
            }
        }
        return Transcription(words: result.words, segments: result.segments, audioSeconds: audioSeconds)
    }

    /// Whisper over the WHOLE song with word timestamps.
    /// • noSpeechThreshold off: with it WhisperKit skips an entire 30 s
    ///   window when the "no speech" probability is high — typical for
    ///   singing over loud music (only a fraction of the words came back).
    /// • compression-ratio limit raised: repeated choruses are not
    ///   hallucinations.
    /// Logs words per 30 s window (counts and times only, never text).
    nonisolated static func transcribe(samples: [Float], pipe: WhisperKit, language: String?,
                                       progress: @escaping @Sendable (Double) -> Void) async throws
        -> (words: [RecognizedWord], segments: [[RecognizedWord]]) {
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
        let segments = results.flatMap(\.segments).sorted { $0.start < $1.start }
        let grouped = segments.map { segment in
            (segment.words ?? []).map { RecognizedWord(text: $0.word, start: Double($0.start), end: Double($0.end)) }
        }
        let words = grouped.flatMap { $0 }.sorted { $0.start < $1.start }
        var buckets = [Int](repeating: 0, count: max(1, Int(ceil(audioSeconds / 30))))
        for word in words { buckets[min(buckets.count - 1, max(0, Int(word.start / 30)))] += 1 }
        Log.player.info("AISYNC transcribed \(words.count) words in \(segments.count) segments / \(results.count) results (lang=\(language ?? "auto"), audio=\(Int(audioSeconds)) s, last word at \(Int(words.last?.start ?? 0)) s); words per 30 s: \(buckets.map(String.init).joined(separator: " "))")
        return (words, grouped)
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
        let result = try await transcribe(samples: samples, pipe: pipe, language: language) { _ in }
        return (result.words, Double(samples.count) / 16_000)
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
