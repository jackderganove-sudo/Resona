//
//  QueueRecommendations.swift
//  Resona
//
//  YouTube Music's recommendation chips for the queue (as in ArchiveTune
//  15's queue redesign): the radio of the playing song comes with chips
//  like "Popular", "Discover", "Deep cuts" or genres. Picking one replaces
//  the upcoming songs with that flavour of the radio; the playing song and
//  the history stay. Plus the queue edits "play next" (move, not copy) and
//  removing several songs at once.
//

import Foundation
import SwiftyTube

struct QueueChip: Identifiable, Equatable, Sendable {
    struct Endpoint: Equatable, Sendable {
        var videoId: String?
        var playlistId: String?
        var params: String?
        var playerParams: String?
    }

    let id: String
    let title: String
    var isSelected: Bool
    let endpoint: Endpoint
    let deselectEndpoint: Endpoint?
}

enum QueueChipParser {
    /// musicQueueRenderer of a `next` response.
    static func queueRenderer(_ json: [String: Any]) -> [String: Any]? {
        let contents = json["contents"] as? [String: Any]
        let single = contents?["singleColumnMusicWatchNextResultsRenderer"] as? [String: Any]
        let tabbed = single?["tabbedRenderer"] as? [String: Any]
        let watchNext = tabbed?["watchNextTabbedResultsRenderer"] as? [String: Any]
        let tab = (watchNext?["tabs"] as? [[String: Any]])?.first?["tabRenderer"] as? [String: Any]
        return (tab?["content"] as? [String: Any])?["musicQueueRenderer"] as? [String: Any]
    }

    static func chips(from json: [String: Any]) -> [QueueChip] {
        let cloud = (queueRenderer(json)?["subHeaderChipCloud"] as? [String: Any])?["chipCloudRenderer"] as? [String: Any]
        let entries = cloud?["chips"] as? [[String: Any]] ?? []
        return entries.enumerated().compactMap { index, entry in
            guard let renderer = entry["chipCloudChipRenderer"] as? [String: Any],
                  let title = text(renderer["text"]), !title.isEmpty else { return nil }
            let deselect = endpoint(renderer["onDeselectedCommand"] as? [String: Any])
            guard let target = endpoint(renderer["navigationEndpoint"] as? [String: Any]) ?? deselect else { return nil }
            return QueueChip(id: "\(renderer["uniqueId"] as? String ?? title):\(index)", title: title,
                             isSelected: renderer["isSelected"] as? Bool ?? false,
                             endpoint: target, deselectEndpoint: deselect)
        }
    }

    /// queueUpdateCommand.fetchContentsCommand.watchEndpoint, or a plain
    /// watch(Playlist)Endpoint.
    static func endpoint(_ command: [String: Any]?) -> QueueChip.Endpoint? {
        guard let command else { return nil }
        let fetch = (command["queueUpdateCommand"] as? [String: Any])?["fetchContentsCommand"] as? [String: Any]
        let watch = (fetch?["watchEndpoint"] ?? fetch?["watchPlaylistEndpoint"]
            ?? command["watchEndpoint"] ?? command["watchPlaylistEndpoint"]) as? [String: Any]
        guard let watch else { return nil }
        let result = QueueChip.Endpoint(videoId: watch["videoId"] as? String, playlistId: watch["playlistId"] as? String,
                                        params: watch["params"] as? String, playerParams: watch["playerParams"] as? String)
        guard result.videoId?.isEmpty == false || result.playlistId?.isEmpty == false else { return nil }
        return result
    }

    private static func text(_ any: Any?) -> String? {
        guard let dict = any as? [String: Any] else { return nil }
        if let simple = dict["simpleText"] as? String { return simple }
        return (dict["runs"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined()
    }

    /// Chips after a chip request: the server's own selection when it sent
    /// one, otherwise the requested chip turns on (or off) by hand.
    static func accept(returned: [QueueChip], previous: [QueueChip], requested: QueueChip) -> [QueueChip] {
        let available = returned.isEmpty ? previous : returned
        if returned.contains(where: \.isSelected) { return available }
        return available.map { chip in
            var chip = chip
            let matches = (chip.id == requested.id && chip.title == requested.title) || chip.endpoint == requested.endpoint
            chip.isSelected = !requested.isSelected && matches
            return chip
        }
    }
}

/// Queue edits shared by the queue sheet, its multi-selection and the
/// song menu's "Play next" from inside the queue.
enum QueueEditing {
    /// Moves the songs at `indices` right behind the current one, in queue
    /// order. The current song never moves.
    static func movingToNext(_ songs: [SongItem], current: Int, indices: IndexSet) -> (songs: [SongItem], current: Int) {
        let movable = indices.filter { songs.indices.contains($0) && $0 != current }
        guard !movable.isEmpty, songs.indices.contains(current) else { return (songs, current) }
        let moving = movable.sorted().map { songs[$0] }
        var rest = songs.enumerated().filter { !movable.contains($0.offset) }.map(\.element)
        let newCurrent = current - movable.filter { $0 < current }.count
        rest.insert(contentsOf: moving, at: min(newCurrent + 1, rest.count))
        return (rest, newCurrent)
    }

    /// Removes the songs at `indices`, never the current one.
    static func removing(_ songs: [SongItem], current: Int, indices: IndexSet) -> (songs: [SongItem], current: Int) {
        let removable = indices.filter { songs.indices.contains($0) && $0 != current }
        guard !removable.isEmpty else { return (songs, current) }
        let rest = songs.enumerated().filter { !removable.contains($0.offset) }.map(\.element)
        let newCurrent = current - removable.filter { $0 < current }.count
        return (rest, min(max(newCurrent, 0), max(rest.count - 1, 0)))
    }

    /// History + current song + the recommendations (without the current
    /// song and without duplicates of what was already played).
    static func replacingUpcoming(_ songs: [SongItem], current: Int, with recommendations: [SongItem]) -> [SongItem] {
        guard songs.indices.contains(current) else { return recommendations }
        let kept = Array(songs[...current])
        let keptIds = Set(kept.map(\.videoId))
        var seen = Set<String>()
        let upcoming = recommendations.filter { !keptIds.contains($0.videoId) && seen.insert($0.videoId).inserted }
        return kept + upcoming
    }
}

@MainActor
@Observable
final class QueueRecommendationStore {
    static let shared = QueueRecommendationStore()

    private(set) var chips: [QueueChip] = []
    private(set) var seedVideoId: String?
    private(set) var isLoading = false
    private(set) var pendingChipId: String?
    private(set) var failed = false
    private var lastRequest: (() async -> Void)?

    private init() {}

    /// Chips of the playing song's radio; cached until the song changes.
    func load(for videoId: String?) async {
        guard let videoId, !videoId.isEmpty else {
            chips = []
            seedVideoId = nil
            return
        }
        guard seedVideoId != videoId || (chips.isEmpty && !isLoading) else { return }
        seedVideoId = videoId
        chips = []
        failed = false
        isLoading = true
        lastRequest = { [weak self] in await self?.load(for: videoId) }
        let json = try? await Self.next(QueueChip.Endpoint(videoId: videoId, playlistId: "RDAMVM\(videoId)"))
        guard seedVideoId == videoId else { return }
        isLoading = false
        guard let json else {
            failed = true
            return
        }
        chips = QueueChipParser.chips(from: json)
        Log.nowPlaying.info("Queue chips: \(self.chips.count)")
    }

    /// Replaces the upcoming songs with the chip's radio.
    func select(_ chip: QueueChip) async {
        guard pendingChipId == nil, let seed = seedVideoId else { return }
        let target = chip.isSelected ? chip.deselectEndpoint : chip.endpoint
        guard let target else { return }
        pendingChipId = chip.id
        failed = false
        lastRequest = { [weak self] in await self?.select(chip) }
        defer { pendingChipId = nil }
        let np = NowPlaying.shared
        guard let json = try? await Self.next(target) else {
            failed = true
            return
        }
        let songs = await PersonalizationService.shared.songs(fromNextResponse: json)
        // The song changed while loading: the chips belong to the old one.
        guard seedVideoId == seed, np.videoId == seed, !songs.isEmpty else {
            if songs.isEmpty { failed = true }
            return
        }
        np.replaceUpcoming(with: songs)
        chips = QueueChipParser.accept(returned: QueueChipParser.chips(from: json), previous: chips, requested: chip)
        Log.nowPlaying.info("Queue chip applied: \(songs.count) songs")
    }

    func retry() async {
        guard let lastRequest else { return }
        await lastRequest()
    }

    /// `next` with the chip's params (the shared client has no params).
    nonisolated static func next(_ endpoint: QueueChip.Endpoint) async throws -> [String: Any] {
        guard let url = URL(string: "https://music.youtube.com/youtubei/v1/next?prettyPrint=false") else {
            throw URLError(.badURL)
        }
        let client = YouTubeClient.webRemix
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        let region = await MainActor.run { SettingsStore.shared.contentCountry }
        var body: [String: Any] = [
            "context": [
                "client": [
                    "clientName": client.clientName,
                    "clientVersion": client.clientVersion,
                    "hl": language,
                    "gl": region.isEmpty ? "US" : region
                ]
            ]
        ]
        if let value = endpoint.videoId { body["videoId"] = value }
        if let value = endpoint.playlistId { body["playlistId"] = value }
        if let value = endpoint.params { body["params"] = value }
        if let value = endpoint.playerParams { body["playerParams"] = value }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(client.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://music.youtube.com/", forHTTPHeaderField: "Referer")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.badServerResponse)
        }
        return json
    }
}
