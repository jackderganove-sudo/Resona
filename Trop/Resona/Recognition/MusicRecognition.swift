//
//  MusicRecognition.swift
//  Resona
//
//  "What's playing here?" like on Android: 8.4 s from the microphone, signature,
//  the same Shazam endpoint, then play the match from YouTube Music. Nothing is
//  recorded or kept: the audio only lives in memory until the signature exists.
//

import AVFoundation
import Foundation
import Observation

struct RecognizedSong: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var artist: String
    var album: String?
    var coverURL: String?
    var recognizedAt: Date
}

enum ShazamClient {
    enum Failure: Error, Equatable {
        case noMatch
        case tooManyRequests
        case service(Int)
    }

    /// Same request as the Android app. Location and time zone say nothing about
    /// the user: the location is random, like on Android.
    static func request(signature: ShazamSignature, now: Date = Date(), id: UUID = UUID(), tag: UUID = UUID()) -> URLRequest {
        var components = URLComponents(string: "https://amp.shazam.com/discovery/v5/en/US/android/-/tag/\(id.uuidString.uppercased())/\(tag.uuidString.lowercased())")!
        components.queryItems = [
            ("sync", "true"), ("webv3", "true"), ("sampling", "true"), ("connected", ""),
            ("shazamapiversion", "v3"), ("sharehub", "true"), ("video", "v3")
        ].map { URLQueryItem(name: $0.0, value: $0.1) }
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("en_US", forHTTPHeaderField: "Content-Language")
        request.setValue("Dalvik/2.1.0 (Linux; U; Android 5.1.1; SM-P905V Build/LMY47X)", forHTTPHeaderField: "User-Agent")
        let timestamp = Int(now.timeIntervalSince1970)
        let body: [String: Any] = [
            "geolocation": [
                "altitude": Double.random(in: 100...500),
                "latitude": Double.random(in: -90...90),
                "longitude": Double.random(in: -180...180)
            ],
            "signature": ["samplems": signature.sampleDurationMs, "timestamp": timestamp, "uri": signature.uri],
            "timestamp": timestamp,
            "timezone": "Europe/Berlin"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func parse(_ data: Data, now: Date = Date()) throws -> RecognizedSong {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let track = json["track"] as? [String: Any],
              let title = track["title"] as? String, !title.isEmpty else { throw Failure.noMatch }
        let images = track["images"] as? [String: Any]
        let sections = track["sections"] as? [[String: Any]] ?? []
        let songMetadata = sections.first { $0["type"] as? String == "SONG" }?["metadata"] as? [[String: Any]] ?? []
        // The album is the first metadata row of the SONG section.
        let album = songMetadata.first?["text"] as? String
        return RecognizedSong(
            id: track["key"] as? String ?? UUID().uuidString,
            title: title,
            artist: track["subtitle"] as? String ?? "",
            album: album,
            coverURL: images?["coverarthq"] as? String ?? images?["coverart"] as? String,
            recognizedAt: now
        )
    }

    static func recognize(_ signature: ShazamSignature) async throws -> RecognizedSong {
        let (data, response) = try await URLSession.shared.data(for: request(signature: signature))
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200..<300: return try parse(data)
        case 404: throw Failure.noMatch
        case 429: throw Failure.tooManyRequests
        case let code: throw Failure.service(code)
        }
    }
}

/// Microphone → 16 kHz mono PCM.
final class MicrophoneCapture: @unchecked Sendable {
    enum Failure: Error { case denied, unavailable }

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Int16] = []
    private var finished = false
    private var continuation: CheckedContinuation<[Int16], Error>?

    static func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func capture(seconds: Double, progress: @escaping @Sendable (Double) -> Void) async throws -> [Int16] {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0,
              let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: format, to: target) else { throw Failure.unavailable }
        let wanted = Int(seconds * 16_000)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
                    guard let self else { return }
                    let capacity = AVAudioFrameCount(Double(buffer.frameLength) * 16_000 / format.sampleRate) + 32
                    guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
                    var supplied = false
                    converter.convert(to: output, error: nil) { _, status in
                        if supplied {
                            status.pointee = .noDataNow
                            return nil
                        }
                        supplied = true
                        status.pointee = .haveData
                        return buffer
                    }
                    guard let channel = output.int16ChannelData?[0] else { return }
                    self.add(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)), wanted: wanted, progress: progress)
                }
                do {
                    engine.prepare()
                    try engine.start()
                } catch {
                    finish(.failure(error))
                }
            }
        } onCancel: {
            self.finish(.failure(CancellationError()))
        }
    }

    private func add(_ pcm: UnsafeBufferPointer<Int16>, wanted: Int, progress: @Sendable (Double) -> Void) {
        lock.lock()
        samples.append(contentsOf: pcm)
        let count = samples.count
        lock.unlock()
        progress(min(1, Double(count) / Double(wanted)))
        if count >= wanted { finish(.success(())) }
    }

    private func finish(_ result: Result<Void, Error>) {
        lock.lock()
        let waiting = finished ? nil : continuation
        finished = true
        continuation = nil
        let captured = samples
        lock.unlock()
        guard let waiting else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        switch result {
        case .success: waiting.resume(returning: captured)
        case .failure(let error): waiting.resume(throwing: error)
        }
    }
}

@MainActor
@Observable
final class MusicRecognition {
    static let shared = MusicRecognition()

    enum Phase: Equatable {
        case idle
        case listening(Double)
        case identifying
        case found(RecognizedSong)
        case noMatch
        case denied
        case failed
    }

    private(set) var phase: Phase = .idle
    private(set) var history: [RecognizedSong] = []
    private(set) var isOpeningSong = false
    private var task: Task<Void, Never>?

    static let recordingSeconds = 8.4
    private static let historyKey = "resona.recognition.history"
    private static let historyLimit = 50

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.historyKey),
           let saved = try? JSONDecoder().decode([RecognizedSong].self, from: data) {
            history = saved
        }
    }

    func start() {
        cancel()
        phase = .listening(0)
        task = Task { await run() }
    }

    func cancel() {
        task?.cancel()
        task = nil
        phase = .idle
    }

    func clearHistory() {
        history = []
        UserDefaults.standard.removeObject(forKey: Self.historyKey)
    }

    private func run() async {
        #if DEBUG
        if let fake = TestMode.recognitionResult {
            try? await Task.sleep(for: .seconds(1))
            finish(fake)
            return
        }
        #endif
        guard await MicrophoneCapture.requestPermission() else {
            phase = .denied
            return
        }
        // The app's own music would only drown out what we're listening for.
        let player = PlayerController.shared
        let wasPlaying = NowPlaying.shared.isPlaying
        if wasPlaying { player.togglePlayPause() }
        defer {
            player.assertAudioSession()
            if wasPlaying { player.togglePlayPause() }
        }
        do {
            let pcm = try await MicrophoneCapture().capture(seconds: Self.recordingSeconds) { value in
                Task { @MainActor in
                    if case .listening = MusicRecognition.shared.phase { MusicRecognition.shared.phase = .listening(value) }
                }
            }
            try Task.checkCancellation()
            phase = .identifying
            let signature = await Task.detached { ShazamSignatureGenerator.signature(pcm: pcm) }.value
            guard let signature else {
                phase = .noMatch
                return
            }
            finish(try await ShazamClient.recognize(signature))
        } catch is CancellationError {
            return
        } catch ShazamClient.Failure.noMatch {
            phase = .noMatch
        } catch {
            if Task.isCancelled { return }
            Log.player.error("Recognition failed: \(String(describing: type(of: error)))")
            phase = .failed
        }
    }

    private func finish(_ song: RecognizedSong) {
        phase = .found(song)
        history.removeAll { $0.id == song.id }
        history.insert(song, at: 0)
        if history.count > Self.historyLimit { history.removeLast(history.count - Self.historyLimit) }
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: Self.historyKey)
        }
    }

    /// Finds the song on YouTube Music (same matching as Spotify's saved tracks) and plays it.
    func play(_ song: RecognizedSong) async -> Bool {
        isOpeningSong = true
        defer { isOpeningSong = false }
        let track = SpotifySavedTrack(id: "recognized:\(song.id)", title: song.title, artists: [song.artist], album: song.album, coverURL: song.coverURL, durationMs: 0)
        guard let match = await SpotifyMatcher.shared.match(track) else { return false }
        PlaybackQueue.play([match], log: Log.player, context: "Recognized song")
        return true
    }
}
