//
//  SearchSuggestions.swift
//  Resona
//
//  Live suggestions while typing: YouTube Music's own
//  music/get_search_suggestions endpoint (as used by the web client and
//  InnerTune/ArchiveTune). It returns text suggestions (already typo-
//  corrected) and direct hits — songs, artists, albums with artwork —
//  parsed with the regular responsive-list-item parser. Plus the
//  "did you mean" correction of a normal search response.
//

import Foundation
import SwiftyTube

enum SearchSuggestions {
    struct Result {
        var texts: [String] = []
        var items: [YTItem] = []
    }

    private static let endpoint = "https://music.youtube.com/youtubei/v1/music/get_search_suggestions?prettyPrint=false"

    /// Never throws; cancellation of the calling task cancels the request.
    static func fetch(_ input: String) async -> Result {
        guard let url = URL(string: endpoint) else { return Result() }
        let client = YouTubeClient.webRemix
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        let region = await MainActor.run { SettingsStore.shared.contentCountry }
        let body: [String: Any] = [
            "context": [
                "client": [
                    "clientName": client.clientName,
                    "clientVersion": client.clientVersion,
                    "hl": language,
                    "gl": region.isEmpty ? "US" : region
                ]
            ],
            "input": input
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 6
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(client.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://music.youtube.com/", forHTTPHeaderField: "Referer")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return Result() }
        return parse(json)
    }

    static func parse(_ json: [String: Any]) -> Result {
        var result = Result()
        let sections = (json["contents"] as? [[String: Any]]) ?? []
        for section in sections {
            guard let renderer = section["searchSuggestionsSectionRenderer"] as? [String: Any],
                  let contents = renderer["contents"] as? [[String: Any]] else { continue }
            for entry in contents {
                if let suggestion = (entry["searchSuggestionRenderer"] ?? entry["historySuggestionRenderer"]) as? [String: Any],
                   let text = suggestionText(suggestion), !result.texts.contains(text) {
                    result.texts.append(text)
                } else if let list = entry["musicResponsiveListItemRenderer"] as? [String: Any],
                          let item = YTItem.fromResponsiveListItem(list),
                          !result.items.contains(where: { $0.id == item.id }) {
                    result.items.append(item)
                }
            }
        }
        return result
    }

    private static func suggestionText(_ renderer: [String: Any]) -> String? {
        if let query = ((renderer["navigationEndpoint"] as? [String: Any])?["searchEndpoint"] as? [String: Any])?["query"] as? String,
           !query.isEmpty {
            return query
        }
        let runs = ((renderer["suggestion"] as? [String: Any])?["runs"] as? [[String: Any]]) ?? []
        let text = runs.compactMap { $0["text"] as? String }.joined()
        return text.isEmpty ? nil : text
    }

    /// "Did you mean …" / "Showing results for …" in a search response.
    static func correction(in value: Any, depth: Int = 0) -> String? {
        guard depth < 12 else { return nil }
        if let dict = value as? [String: Any] {
            for key in ["didYouMeanRenderer", "showingResultsForRenderer"] {
                if let renderer = dict[key] as? [String: Any] {
                    if let query = ((renderer["correctedQueryEndpoint"] as? [String: Any])?["searchEndpoint"] as? [String: Any])?["query"] as? String {
                        return query
                    }
                    let runs = ((renderer["correctedQuery"] as? [String: Any])?["runs"] as? [[String: Any]]) ?? []
                    let text = runs.compactMap { $0["text"] as? String }.joined()
                    if !text.isEmpty { return text }
                }
            }
            for nested in dict.values {
                if let found = correction(in: nested, depth: depth + 1) { return found }
            }
        } else if let array = value as? [Any] {
            for nested in array {
                if let found = correction(in: nested, depth: depth + 1) { return found }
            }
        }
        return nil
    }
}
