//
//  CanvasColorSampler.swift
//  Resona
//
//  Player background = only a colour gradient, never video (round 11).
//  With a Spotify canvas the clip plays invisibly (muted, no layer, looped by hand) and
//  about once a second a tiny frame (24×24) is quantised into four main
//  colours; the mesh gradient fades to them, so it moves with the canvas.
//  Sparing: tiny frames, paused with playback, while the player is hidden
//  and in Low Power Mode.
//

import AVFoundation
import Foundation
import Observation
import QuartzCore

enum CanvasColorQuantizer {
    /// Four main colours of a BGRA frame: 4-bit buckets per channel,
    /// scored by count and saturation (grey/black areas count less), the
    /// average of each of the best four buckets, ordered by luminance
    /// (darkest last) so the gradient keeps its layout from frame to frame.
    static func dominant(bgra: [UInt8], width: Int, height: Int, bytesPerRow: Int) -> [RGB] {
        struct Bucket { var r = 0.0, g = 0.0, b = 0.0, count = 0.0 }
        var buckets: [Int: Bucket] = [:]
        for y in 0..<height {
            for x in 0..<width {
                let i = y * bytesPerRow + x * 4
                guard i + 2 < bgra.count else { continue }
                let b = Double(bgra[i]) / 255, g = Double(bgra[i + 1]) / 255, r = Double(bgra[i + 2]) / 255
                let key = (Int(r * 15) << 8) | (Int(g * 15) << 4) | Int(b * 15)
                var bucket = buckets[key, default: Bucket()]
                bucket.r += r; bucket.g += g; bucket.b += b; bucket.count += 1
                buckets[key] = bucket
            }
        }
        let ranked = buckets.values.map { bucket -> (RGB, Double) in
            let rgb = RGB(r: bucket.r / bucket.count, g: bucket.g / bucket.count, b: bucket.b / bucket.count)
            let hsv = rgb.hsv
            // Very dark / grey pixels shouldn't win just by area.
            let weight = bucket.count * (0.25 + hsv.s) * (hsv.v < 0.08 ? 0.2 : 1)
            return (rgb, weight)
        }.sorted { $0.1 > $1.1 }
        var picked: [RGB] = []
        for (rgb, _) in ranked where picked.count < 4 {
            // Skip near-duplicates so the four colours differ.
            if picked.allSatisfy({ distance($0, rgb) > 0.12 }) { picked.append(rgb) }
        }
        guard let first = picked.first else { return [] }
        while picked.count < 4 { picked.append(picked[picked.count % max(1, picked.count)].mix(first, 0.3)) }
        return picked.sorted { $0.relativeLuminance > $1.relativeLuminance }
    }

    /// Keeps text and controls readable: no very bright or garish colours.
    static func readable(_ colors: [RGB]) -> [RGB] {
        colors.map { rgb in
            let hsv = rgb.hsv
            return RGB(h: hsv.h, s: min(hsv.s, 0.85), v: min(max(hsv.v, 0.12), 0.62))
        }
    }

    /// Exponential smoothing against the previous colours (no flicker).
    static func smoothed(_ new: [RGB], previous: [RGB]?, factor: Double = 0.45) -> [RGB] {
        guard let previous, previous.count == new.count else { return new }
        return zip(previous, new).map { $0.mix($1, factor) }
    }

    private static func distance(_ a: RGB, _ b: RGB) -> Double {
        abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b)
    }
}

@MainActor
@Observable
final class CanvasColorSampler {
    static let shared = CanvasColorSampler()

    /// Four gradient colours from the running canvas; nil = use the cover.
    private(set) var colors: [RGB]?

    private var url: URL?
    private var player: AVPlayer?
    private var output: AVPlayerItemVideoOutput?
    private var endObserver: NSObjectProtocol?
    private var loop: Task<Void, Never>?
    private var active = false

    static let interval: Double = 1.0
    static let frameSide = 24

    private init() {}

    /// Starts sampling `url` (no-op when it already runs).
    func start(url: URL) {
        if self.url == url, player != nil { return }
        stop()
        self.url = url
        let item = AVPlayerItem(url: url)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Self.frameSide,
            kCVPixelBufferHeightKey as String: Self.frameSide
        ])
        item.add(output)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.actionAtItemEnd = .none
        // One item, looped by hand (an output belongs to exactly one item).
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak player] _ in
            player?.seek(to: .zero)
        }
        self.player = player
        self.output = output
        Log.player.info("Canvas colours: sampling started")
        setActive(active)
    }

    /// Player visible + music playing + not in Low Power Mode.
    func setActive(_ value: Bool) {
        active = value
        let run = value && !ProcessInfo.processInfo.isLowPowerModeEnabled && player != nil
        if run {
            player?.play()
            guard loop == nil else { return }
            loop = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    self?.sample()
                    try? await Task.sleep(for: .seconds(Self.interval))
                }
            }
        } else {
            player?.pause()
            loop?.cancel()
            loop = nil
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        player?.pause()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player = nil
        output = nil
        url = nil
        colors = nil
    }

    private func sample() {
        guard let output else { return }
        let time = output.itemTime(forHostTime: CACurrentMediaTime())
        guard output.hasNewPixelBuffer(forItemTime: time),
              let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { return }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let bytes = Array(UnsafeBufferPointer(start: base.assumingMemoryBound(to: UInt8.self), count: bytesPerRow * height))
        let found = CanvasColorQuantizer.dominant(bgra: bytes, width: width, height: height, bytesPerRow: bytesPerRow)
        guard found.count == 4 else { return }
        colors = CanvasColorQuantizer.smoothed(CanvasColorQuantizer.readable(found), previous: colors)
    }
}
