//
//  AILyricsTranslation.swift
//  Resona
//
//  Optional lyrics translation with an AI model through OpenRouter (as in
//  ArchiveTune 15's AI integration): own API key (Keychain), model and an
//  optional own prompt appended to the default one. The lines are sent as
//  a JSON array and must come back as an array of the same length. The
//  lyrics never reach the logs — only counts.
//

import Foundation

enum LyricsTranslationEngine: String, CaseIterable, Identifiable, SettingsOption {
    case apple
    case openRouter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apple: return "Apple (on device)"
        case .openRouter: return "AI via OpenRouter"
        }
    }
}

/// Where the translation shown for a song came from.
enum LyricsTranslationSource: String, Codable, Sendable {
    case provider
    case apple
    case ai
}

enum AILyricsTranslator {
    static let defaultModel = "google/gemini-2.5-flash"
    static let endpoint = "https://openrouter.ai/api/v1/chat/completions"

    enum TranslationError: LocalizedError {
        case notConfigured
        case http(Int)
        case badResponse(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return String(localized: "No OpenRouter API key set.")
            case .http(let code): return String(format: String(localized: "OpenRouter answered with HTTP %d."), code)
            case .badResponse(let reason): return reason
            }
        }
    }

    static func systemPrompt(targetLanguage: String, count: Int, customPrompt: String) -> String {
        var prompt = """
        You are an expert song lyrics translator.
        Translate each input string into \(targetLanguage) with natural, accurate lyric phrasing.
        Preserve meaning, tone, profanity level, names, repeated hooks, and line-level intent.
        Do not add timestamps, IDs, markdown, explanations, or extra lines.
        Return only a JSON array of strings with exactly \(count) items in the same order.
        """
        let custom = customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { prompt += "\n\n" + custom }
        return prompt
    }

    /// Translations in the same order as `lines`.
    static func translate(_ lines: [String], targetLanguage: String = "German", model: String, customPrompt: String,
                          apiKey: String) async throws -> [String] {
        guard !lines.isEmpty else { return [] }
        guard !apiKey.isEmpty, let url = URL(string: endpoint) else { throw TranslationError.notConfigured }
        let payload = String(decoding: try JSONSerialization.data(withJSONObject: lines), as: UTF8.self)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://github.com/jackderganove-sudo/Resona", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Resona", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model.isEmpty ? defaultModel : model,
            "temperature": 0.15,
            "max_tokens": 8192,
            "messages": [
                ["role": "system", "content": systemPrompt(targetLanguage: targetLanguage, count: lines.count, customPrompt: customPrompt)],
                ["role": "user", "content": payload]
            ]
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else { throw TranslationError.http(status) }
        guard let content = messageContent(data) else {
            throw TranslationError.badResponse(String(localized: "The AI returned no text."))
        }
        let translated = try jsonArray(in: content)
        guard translated.count == lines.count else {
            throw TranslationError.badResponse(String(localized: "The AI changed the number of lines."))
        }
        return translated
    }

    /// choices[0].message.content (string or list of text parts).
    static func messageContent(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = ((json["choices"] as? [[String: Any]])?.first)?["message"] as? [String: Any] else { return nil }
        if let text = message["content"] as? String { return text }
        if let parts = message["content"] as? [[String: Any]] {
            return parts.compactMap { ($0["type"] as? String) == "text" ? $0["text"] as? String : nil }.joined()
        }
        return nil
    }

    /// The first JSON array of strings in the reply (models sometimes wrap
    /// it in ```json fences or a sentence).
    static func jsonArray(in text: String) throws -> [String] {
        guard let start = text.firstIndex(of: "["), let end = text.lastIndex(of: "]"), start < end else {
            throw TranslationError.badResponse(String(localized: "The AI reply was not a list of lines."))
        }
        let slice = String(text[start...end])
        guard let array = try? JSONSerialization.jsonObject(with: Data(slice.utf8)) as? [Any] else {
            throw TranslationError.badResponse(String(localized: "The AI reply was not a list of lines."))
        }
        let strings = array.compactMap { $0 as? String }
        guard strings.count == array.count else {
            throw TranslationError.badResponse(String(localized: "The AI reply was not a list of lines."))
        }
        return strings
    }
}

/// Translation source per song, persisted with the translation cache.
enum LyricsTranslationSourceStore {
    private static let key = "resona.lyrics.translationSource"

    static func source(for videoId: String) -> LyricsTranslationSource? {
        (UserDefaults.standard.dictionary(forKey: key) as? [String: String])?[videoId].flatMap(LyricsTranslationSource.init(rawValue:))
    }

    static func set(_ source: LyricsTranslationSource?, for videoId: String) {
        var map = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        map[videoId] = source?.rawValue
        UserDefaults.standard.set(map, forKey: key)
    }
}
