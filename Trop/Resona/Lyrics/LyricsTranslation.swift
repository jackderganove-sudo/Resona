//
//  LyricsTranslation.swift
//  Resona
//
//  On-device lyrics translation into German (Apple Translation framework,
//  iOS 18): the lyrics' language is detected with NaturalLanguage; if it
//  isn't German and the provider didn't supply translations, the lines are
//  translated (Settings: Off / On request / Always; per song from the
//  lyrics menu) and cached per song.
//

import Foundation
import NaturalLanguage
import Observation
import SwiftUI
import Translation

enum LyricsTranslationMode: String, CaseIterable, Identifiable, SettingsOption {
    case off
    case onRequest
    case always

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .onRequest: return "On request"
        case .always: return "Always"
        }
    }
}

@MainActor
@Observable
final class LyricsTranslationState {
    static let shared = LyricsTranslationState()
    /// Songs the user asked to translate (mode "on request").
    var requested: Set<String> = []
    /// Detected source language per song (nil = unknown / German).
    var sourceLanguage: [String: String] = [:]
    var isTranslating = false
}

enum LyricsTranslationCache {
    private static var directory: URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("lyrics-translations", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func file(_ videoId: String) -> URL? {
        directory?.appendingPathComponent("\(videoId.replacingOccurrences(of: "/", with: "_")).json")
    }

    /// Line text → German translation.
    static func load(_ videoId: String) -> [String: String] {
        guard let url = file(videoId), let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return map
    }

    static func save(_ map: [String: String], for videoId: String) {
        guard let url = file(videoId), let data = try? JSONEncoder().encode(map) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

enum LyricsLanguage {
    /// Dominant language of the lyrics ("en", "es", "pt" …), nil if unclear.
    static func detect(_ lines: [LyricLine]) -> String? {
        let text = lines.map(\.text).joined(separator: "\n")
        guard text.count > 20 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage,
              let confidence = recognizer.languageHypotheses(withMaximum: 1)[language], confidence > 0.5 else { return nil }
        return language.rawValue
    }
}
