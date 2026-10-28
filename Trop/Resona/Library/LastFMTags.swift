//
//  LastFMTags.swift
//  Resona
//
//  Genre / mood for "Split playlist": YouTube Music has no genre per song,
//  Last.fm has community tags. track.getTopTags (falls back to / is topped
//  up with artist.getTopTags) — unsigned GET calls that need only the API
//  key, no login. Results are cached on disk for 30 days (also "no tags"),
//  artist tags are shared by all songs of an artist. The tags are mapped
//  onto a fixed set of genre/mood groups by GenreMoodClassifier.
//

import Foundation

struct LastFMTag: Codable, Hashable, Sendable {
    let name: String
    /// Last.fm weight 0…100 (relative to the item's top tag).
    let count: Int
}

enum GenreMood: String, CaseIterable, Sendable {
    case phonk, hipHop, chillSad, electronic, rock, metal, pop, rnb, indieFolk, latin, jazz, classical, country

    var title: String {
        switch self {
        case .phonk: return "Phonk"
        case .hipHop: return "Hip-Hop"
        case .chillSad: return String(localized: "Chill/Sad")
        case .electronic: return String(localized: "Electronic")
        case .rock: return "Rock"
        case .metal: return "Metal"
        case .pop: return "Pop"
        case .rnb: return "R&B/Soul"
        case .indieFolk: return "Indie/Folk"
        case .latin: return "Latin"
        case .jazz: return "Jazz"
        case .classical: return String(localized: "Classical")
        case .country: return "Country"
        }
    }

    /// Tags (lower-case, hyphens/spaces normalized) that mean this group.
    var keywords: [String] {
        switch self {
        case .phonk: return ["phonk", "drift phonk", "brazilian phonk", "memphis phonk", "memphis rap", "cowbell"]
        case .hipHop: return ["hip hop", "rap", "trap", "drill", "grime", "boom bap", "deutschrap", "cloud rap",
                              "gangsta rap", "east coast rap", "west coast rap", "conscious hip hop", "emo rap", "plugg"]
        case .chillSad: return ["chill", "chillout", "chillhop", "lofi", "lo fi", "sad", "melancholic", "melancholy",
                                "mellow", "relax", "relaxing", "sleep", "ambient", "downtempo", "dream pop", "emotional",
                                "depressing", "calm", "slowed", "slowed and reverb", "bedroom pop", "sadcore"]
        case .electronic: return ["electronic", "edm", "house", "deep house", "techno", "dubstep", "drum and bass", "dnb",
                                  "trance", "electro", "hardstyle", "future bass", "dance", "synthwave", "garage",
                                  "uk garage", "breakbeat", "jersey club", "hyperpop", "eurodance", "electronica", "idm"]
        case .rock: return ["rock", "alternative rock", "hard rock", "punk", "pop punk", "grunge", "indie rock",
                            "post hardcore", "emo", "classic rock", "post punk", "alternative", "garage rock"]
        case .metal: return ["metal", "metalcore", "heavy metal", "death metal", "black metal", "nu metal",
                             "deathcore", "djent", "thrash metal"]
        case .pop: return ["pop", "dance pop", "synthpop", "synth pop", "electropop", "k pop", "kpop", "j pop",
                           "teen pop", "europop", "schlager", "german pop", "art pop"]
        case .rnb: return ["rnb", "r&b", "r and b", "soul", "neo soul", "contemporary r&b", "funk", "motown"]
        case .indieFolk: return ["indie", "indie folk", "folk", "singer songwriter", "acoustic", "indie pop", "americana"]
        case .latin: return ["latin", "reggaeton", "latin pop", "urbano latino", "bachata", "salsa", "dembow", "cumbia"]
        case .jazz: return ["jazz", "smooth jazz", "jazz hop", "bossa nova", "swing", "blues"]
        case .classical: return ["classical", "piano", "orchestral", "soundtrack", "score", "instrumental", "opera"]
        case .country: return ["country", "bluegrass", "country pop"]
        }
    }
}

enum GenreMoodClassifier {
    static func normalize(_ tag: String) -> String {
        tag.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ").joined(separator: " ")
            .replacingOccurrences(of: "hiphop", with: "hip hop")
    }

    private static let exact: [String: GenreMood] = {
        var map: [String: GenreMood] = [:]
        for group in GenreMood.allCases {
            for keyword in group.keywords where map[keyword] == nil { map[keyword] = group }
        }
        return map
    }()

    /// Group of a single tag: exact keyword first, then the last word(s)
    /// ("german hip hop" → hip hop, "alternative metal" → metal).
    static func group(of tag: String) -> GenreMood? {
        let t = normalize(tag)
        if let hit = exact[t] { return hit }
        let words = t.split(separator: " ")
        guard words.count > 1 else { return nil }
        for start in 1..<words.count {
            if let hit = exact[words[start...].joined(separator: " ")] { return hit }
        }
        return nil
    }

    /// Weighted vote over the tags. Phonk wins whenever it is clearly
    /// tagged (it is usually also tagged hip-hop/trap); chill/sad (mood)
    /// gets a small boost so moody songs don't drown in their genre.
    static func classify(_ tags: [LastFMTag]) -> GenreMood? {
        var score: [GenreMood: Double] = [:]
        let top = Double(max(1, tags.map(\.count).max() ?? 1))
        for (rank, tag) in tags.prefix(10).enumerated() {
            guard let group = group(of: tag.name) else { continue }
            let weight = max(0.05, Double(tag.count) / top) * (rank < 3 ? 1.2 : 1)
            score[group, default: 0] += weight
        }
        if let phonk = score[.phonk], phonk >= 0.3 { return .phonk }
        if let mood = score[.chillSad] { score[.chillSad] = mood * 1.25 }
        return score.max { a, b in a.value == b.value ? a.key.rawValue > b.key.rawValue : a.value < b.value }?.key
    }
}

actor LastFMTagService {
    static let shared = LastFMTagService()

    private struct Entry: Codable {
        let tags: [LastFMTag]
        let date: Date
    }

    private var cache: [String: Entry] = [:]
    private var loaded = false
    private var dirty = false
    private static let maxAge: TimeInterval = 30 * 24 * 3600

    /// Tags are usable when the build has an API key (release builds) or
    /// the user connected Last.fm.
    @MainActor static var isAvailable: Bool {
        !LastFMDefaults.apiKey.isEmpty || LastFMIntegration.shared.isLoggedIn
    }

    private static var file: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("lastfm-tags.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        if let url = Self.file, let data = try? Data(contentsOf: url),
           let stored = try? JSONDecoder().decode([String: Entry].self, from: data) {
            cache = stored.filter { Date().timeIntervalSince($0.value.date) < Self.maxAge }
        }
    }

    func persist() {
        guard dirty, let url = Self.file, let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: url, options: .atomic)
        dirty = false
    }

    /// Track tags, topped up with the artist's tags when the track has few.
    func tags(artist: String, track: String) async -> [LastFMTag] {
        loadIfNeeded()
        let trackTags = await cached("track:\(artist.lowercased())|\(track.lowercased())") {
            await Self.fetch(method: "track.getTopTags", params: ["artist": artist, "track": track])
        }
        if trackTags.filter({ $0.count >= 10 }).count >= 3 { return trackTags }
        let artistTags = await cached("artist:\(artist.lowercased())") {
            await Self.fetch(method: "artist.getTopTags", params: ["artist": artist])
        }
        // Artist tags weigh a bit less than the song's own.
        return trackTags + artistTags.map { LastFMTag(name: $0.name, count: $0.count * 2 / 3) }
    }

    private func cached(_ key: String, _ load: () async -> [LastFMTag]?) async -> [LastFMTag] {
        if let hit = cache[key] { return hit.tags }
        guard let fresh = await load() else { return [] }   // network error: not cached
        cache[key] = Entry(tags: fresh, date: Date())
        dirty = true
        return fresh
    }

    /// nil = request failed (retry next time); [] = no tags.
    private static func fetch(method: String, params: [String: String]) async -> [LastFMTag]? {
        let key = LastFMDefaults.apiKey
        guard !key.isEmpty, var components = URLComponents(string: LastFMDefaults.baseUrl) else { return nil }
        components.queryItems = [URLQueryItem(name: "method", value: method)]
            + params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            + [URLQueryItem(name: "autocorrect", value: "1"),
               URLQueryItem(name: "api_key", value: key),
               URLQueryItem(name: "format", value: "json")]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return parse(json)
    }

    /// `{"toptags": {"tag": [{"name": "rock", "count": 100}, …]}}`; an
    /// error object (e.g. 6 = unknown track) means "no tags".
    static func parse(_ json: [String: Any]) -> [LastFMTag] {
        guard let top = json["toptags"] as? [String: Any] else { return [] }
        let raw: [[String: Any]]
        if let list = top["tag"] as? [[String: Any]] {
            raw = list
        } else if let single = top["tag"] as? [String: Any] {
            raw = [single]
        } else {
            raw = []
        }
        return raw.compactMap { item in
            guard let name = item["name"] as? String, !name.isEmpty else { return nil }
            let count = (item["count"] as? NSNumber)?.intValue ?? Int(item["count"] as? String ?? "") ?? 0
            return LastFMTag(name: name, count: count)
        }
        .filter { $0.count >= 5 }
        .prefix(12)
        .map { $0 }
    }

    /// Genre/mood group name per video id (4 requests in parallel).
    func groups(for songs: [SongItem], progress: @escaping @Sendable (Int) async -> Void) async -> [String: String] {
        var result: [String: String] = [:]
        var done = 0
        let other = String(localized: "Other")
        await withTaskGroup(of: (String, GenreMood?).self) { group in
            var iterator = songs.makeIterator()
            func addNext() -> Bool {
                guard let song = iterator.next() else { return false }
                let artist = song.artists.first?.name ?? ""
                let title = song.title
                group.addTask {
                    guard !artist.isEmpty else { return (song.videoId, nil) }
                    let tags = await self.tags(artist: artist, track: title)
                    return (song.videoId, GenreMoodClassifier.classify(tags))
                }
                return true
            }
            for _ in 0..<4 where addNext() {}
            for await (videoId, mood) in group {
                result[videoId] = mood?.title ?? other
                done += 1
                await progress(done)
                _ = addNext()
            }
        }
        persist()
        return result
    }
}
