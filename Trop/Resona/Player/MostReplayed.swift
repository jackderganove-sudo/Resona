//
//  MostReplayed.swift
//  Resona
//
//  YouTube's "Most replayed" heatmap: the WEB client's `next` response
//  carries it under frameworkUpdates → macroMarkersListEntity
//  (markerType MARKER_TYPE_HEATMAP; older responses: markersMap →
//  heatMarkers). Loaded per song (cached, also "no data"), drawn as a soft
//  wave behind the player's progress bar and used for "Jump to the drop".
//

import Foundation
import SwiftUI
import SwiftyTube

struct Heatmap: Sendable, Equatable, Codable {
    /// Normalized intensities (0…1) of equally long segments.
    let values: [Double]
    /// Length the segments cover (seconds).
    let duration: Double

    /// Start of the most replayed part, a few seconds early. The first ~6 %
    /// are ignored (everyone starts at the beginning) and the last 3 %.
    var dropTime: Double? {
        guard values.count >= 10, duration > 0 else { return nil }
        let from = Int(Double(values.count) * 0.06), to = Int(Double(values.count) * 0.97)
        guard to > from, let peak = (from..<to).max(by: { values[$0] < values[$1] }) else { return nil }
        let segment = duration / Double(values.count)
        return max(0, Double(peak) * segment - 3)
    }
}

actor MostReplayedService {
    static let shared = MostReplayedService()

    private var cache: [String: Heatmap?] = [:]
    private var inFlight: [String: Task<Heatmap?, Never>] = [:]

    func heatmap(for videoId: String) async -> Heatmap? {
        if let cached = cache[videoId] { return cached }
        if let task = inFlight[videoId] { return await task.value }
        let task = Task { await Self.fetch(videoId: videoId) }
        inFlight[videoId] = task
        let result = await task.value
        inFlight.removeValue(forKey: videoId)
        cache[videoId] = .some(result)
        return result
    }

    private static func fetch(videoId: String) async -> Heatmap? {
        guard let url = URL(string: "https://www.youtube.com/youtubei/v1/next?prettyPrint=false") else { return nil }
        let client = YouTubeClient.web
        let body: [String: Any] = [
            "context": ["client": ["clientName": client.clientName, "clientVersion": client.clientVersion, "hl": "en", "gl": "US"]],
            "videoId": videoId
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(client.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return parse(json)
    }

    static func parse(_ json: Any) -> Heatmap? {
        // Current format.
        if let list = find("macroMarkersListEntity", in: json) as? [String: Any],
           let markers = (list["markersList"] as? [String: Any]),
           (markers["markerType"] as? String) == "MARKER_TYPE_HEATMAP",
           let items = markers["markers"] as? [[String: Any]], !items.isEmpty {
            func num(_ any: Any?) -> Double? {
                if let n = any as? NSNumber { return n.doubleValue }
                if let s = any as? String { return Double(s) }
                return nil
            }
            let values = items.map { num($0["intensityScoreNormalized"]) ?? 0 }
            let end = items.last.flatMap { item -> Double? in
                guard let start = num(item["startMillis"]), let length = num(item["durationMillis"]) else { return nil }
                return (start + length) / 1000
            } ?? 0
            return end > 0 ? Heatmap(values: values, duration: end) : nil
        }
        // Older format.
        if let heat = find("heatMarkers", in: json) as? [[String: Any]], !heat.isEmpty {
            let renderers = heat.compactMap { $0["heatMarkerRenderer"] as? [String: Any] }
            let values = renderers.map { ($0["heatMarkerIntensityScoreNormalized"] as? NSNumber)?.doubleValue ?? 0 }
            let end = renderers.last.map {
                (($0["timeRangeStartMillis"] as? NSNumber)?.doubleValue ?? 0) + (($0["markerDurationMillis"] as? NSNumber)?.doubleValue ?? 0)
            } ?? 0
            return end > 0 ? Heatmap(values: values, duration: end / 1000) : nil
        }
        return nil
    }

    private static func find(_ key: String, in value: Any, depth: Int = 0) -> Any? {
        guard depth < 30 else { return nil }
        if let dict = value as? [String: Any] {
            if let hit = dict[key] { return hit }
            for nested in dict.values {
                if let found = find(key, in: nested, depth: depth + 1) { return found }
            }
        } else if let array = value as? [Any] {
            for nested in array {
                if let found = find(key, in: nested, depth: depth + 1) { return found }
            }
        }
        return nil
    }
}

/// Soft wave of the heatmap (cover accent, low opacity), drawn behind the
/// progress bar.
struct HeatmapWave: View {
    let heatmap: Heatmap
    var color: Color

    var body: some View {
        Canvas { ctx, size in
            let values = heatmap.values
            guard values.count > 1 else { return }
            let step = size.width / CGFloat(values.count - 1)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height))
            for (i, v) in values.enumerated() {
                let point = CGPoint(x: CGFloat(i) * step, y: size.height * (1 - CGFloat(min(1, max(0, v)))))
                if i == 0 {
                    path.addLine(to: point)
                } else {
                    let prev = CGPoint(x: CGFloat(i - 1) * step, y: size.height * (1 - CGFloat(min(1, max(0, values[i - 1])))))
                    let mid = CGPoint(x: (prev.x + point.x) / 2, y: (prev.y + point.y) / 2)
                    path.addQuadCurve(to: mid, control: prev)
                    if i == values.count - 1 { path.addLine(to: point) }
                }
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
            ctx.fill(path, with: .linearGradient(
                Gradient(colors: [color.opacity(0.35), color.opacity(0.08)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)
            ))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
