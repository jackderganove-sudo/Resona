//
//  ArtistNameResolver.swift
//  Resona
//
//  Some songs (user uploads, phonk/remix videos, cache-repaired queue items)
//  arrive without artist credits, so mini player, player and queue showed
//  only the title. This keeps the YouTube parsing untouched and fills the
//  gap on the UI side:
//  1. the author that stream resolution already returns is remembered,
//  2. otherwise the uploader is looked up once via YouTube's public oEmbed
//     endpoint (no key, tiny JSON) and cached on disk.
//

import Foundation
import Observation

@MainActor
@Observable
final class ArtistNameResolver {
    static let shared = ArtistNameResolver()

    private(set) var names: [String: String]
    @ObservationIgnored private var inflight: Set<String> = []
    @ObservationIgnored private var failed: Set<String> = []
    private static let storeKey = "resona.resolvedArtistNames"
    private static let limit = 1000

    private init() {
        names = UserDefaults.standard.dictionary(forKey: Self.storeKey) as? [String: String] ?? [:]
    }

    /// Artist line for a song: its own credits, else a resolved name. Starts
    /// a background lookup when nothing is known yet (views update when it
    /// arrives because `names` is observed).
    func artist(for song: SongItem) -> String {
        let own = artistDisplayString(from: song.artists)
        if !own.isEmpty { return own }
        return artist(forVideoId: song.videoId)
    }

    func artist(forVideoId videoId: String) -> String {
        if let known = names[videoId] { return known }
        resolve(videoId)
        return ""
    }

    func cached(_ videoId: String) -> String? { names[videoId] }

    func remember(_ name: String?, for videoId: String?) {
        guard let videoId, let name else { return }
        let cleaned = cleanArtistDisplay(name).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, names[videoId] != cleaned else { return }
        names[videoId] = cleaned
        if names.count > Self.limit, let drop = names.keys.first(where: { $0 != videoId }) {
            names.removeValue(forKey: drop)
        }
        UserDefaults.standard.set(names, forKey: Self.storeKey)
    }

    private func resolve(_ videoId: String) {
        guard !videoId.isEmpty, !inflight.contains(videoId), !failed.contains(videoId) else { return }
        inflight.insert(videoId)
        Task.detached(priority: .utility) {
            let name = await Self.fetchOEmbedAuthor(videoId: videoId)
            await MainActor.run {
                let resolver = ArtistNameResolver.shared
                resolver.inflight.remove(videoId)
                if let name { resolver.remember(name, for: videoId) } else { resolver.failed.insert(videoId) }
            }
        }
    }

    private nonisolated static func fetchOEmbedAuthor(videoId: String) async -> String? {
        var components = URLComponents(string: "https://www.youtube.com/oembed")
        components?.queryItems = [
            URLQueryItem(name: "url", value: "https://www.youtube.com/watch?v=\(videoId)"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let author = json["author_name"] as? String,
              !author.isEmpty else { return nil }
        return author
    }
}
