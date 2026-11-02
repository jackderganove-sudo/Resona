//
//  WhatsNew.swift
//  Resona
//
//  "What's new" after an update (as in ArchiveTune 15): the release notes
//  of every version since the last one seen, sorted into New / Improved /
//  Fixed. Resona's notes are commit subjects ("Area: what changed"); docs,
//  tests and CI entries are left out. Shown once per version, never on the
//  first launch (onboarding instead) and never in UI tests; Settings →
//  About opens it any time.
//

import Foundation
import Observation
import SwiftUI

enum WhatsNewCategory: Int, CaseIterable, Identifiable, Sendable {
    case new, improved, fixed

    var id: Int { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .new: return "New"
        case .improved: return "Improved"
        case .fixed: return "Fixed"
        }
    }

    var icon: String {
        switch self {
        case .new: return "sparkles"
        case .improved: return "wand.and.stars"
        case .fixed: return "wrench.and.screwdriver"
        }
    }
}

struct WhatsNewEntry: Hashable, Sendable {
    /// "Lyrics" in "Lyrics: Binimum provider, …"
    var area: String?
    var text: String
}

struct WhatsNewSection: Identifiable, Hashable, Sendable {
    let category: WhatsNewCategory
    var entries: [WhatsNewEntry]
    var id: Int { category.rawValue }
}

struct WhatsNewRelease: Identifiable, Hashable, Sendable {
    let version: String
    let sections: [WhatsNewSection]
    let pageURL: URL?
    var id: String { version }
}

enum WhatsNewParser {
    /// Bullet lines of a release body → sections in New / Improved / Fixed
    /// order. Headings ("## Fixes") set the category of the lines below.
    static func sections(from markdown: String) -> [WhatsNewSection] {
        var buckets: [WhatsNewCategory: [WhatsNewEntry]] = [:]
        var headingCategory: WhatsNewCategory?
        var skipSection = false
        for raw in markdown.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") {
                let title = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces).lowercased()
                skipSection = title.range(of: #"contributor|credit|full changelog|download|internal|dependenc"#, options: .regularExpression) != nil
                headingCategory = category(ofHeading: title)
                continue
            }
            guard !skipSection, line.hasPrefix("- ") || line.hasPrefix("* ") else { continue }
            var text = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            // GitHub's generated notes: "… by @user in https://…"
            if let range = text.range(of: #" by @[\w-]+ in https?://\S+$"#, options: .regularExpression) {
                text.removeSubrange(range)
            }
            guard !text.isEmpty, !isNoise(text) else { continue }
            let entry = split(text)
            let category = headingCategory ?? category(ofChange: text)
            if !(buckets[category]?.contains(entry) ?? false) {
                buckets[category, default: []].append(entry)
            }
        }
        return WhatsNewCategory.allCases.compactMap { category in
            guard let entries = buckets[category], !entries.isEmpty else { return nil }
            return WhatsNewSection(category: category, entries: entries)
        }
    }

    static func category(ofHeading title: String) -> WhatsNewCategory? {
        if title.range(of: #"\b(fix(es|ed)?|bugs?|resolved)\b"#, options: .regularExpression) != nil { return .fixed }
        if title.range(of: #"\b(improvements?|enhancements?|performance|polish)\b"#, options: .regularExpression) != nil { return .improved }
        if title.range(of: #"\b(features?|additions?|new|highlights)\b"#, options: .regularExpression) != nil { return .new }
        return nil
    }

    static func category(ofChange text: String) -> WhatsNewCategory {
        let lower = text.lowercased()
        let body = lower.split(separator: ":", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces) } ?? lower
        func starts(_ pattern: String, _ s: String) -> Bool {
            s.range(of: "^(" + pattern + ")\\b", options: .regularExpression) != nil
        }
        let fix = "fix(es|ed)?|correct(s|ed)?|resolve[ds]?|prevent(s|ed)?|repair(s|ed)?|restore[ds]?"
        let improve = "improve[ds]?|enhance[ds]?|optimi[sz]e[ds]?|refine[ds]?|update[ds]?|reduce[ds]?|simplif(y|ied)|rework(ed)?|faster|smoother"
        if starts(fix, lower) || starts(fix, body) { return .fixed }
        if starts(improve, lower) || starts(improve, body) { return .improved }
        return .new
    }

    /// Docs, tests, CI and merge commits are of no interest on the iPad.
    static func isNoise(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.range(of: #"^(docs?|tests?|ci|build|chore|merge|bump|revert|readme|workflow)\b"#, options: .regularExpression) != nil
            || lower.contains("[skip ci]")
    }

    /// "Area: description" (area short, without sentence punctuation).
    static func split(_ text: String) -> WhatsNewEntry {
        if let colon = text.firstIndex(of: ":") {
            let area = text[..<colon].trimmingCharacters(in: .whitespaces)
            let rest = text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if !area.isEmpty, area.count <= 48, !rest.isEmpty, !area.contains("http") {
                return WhatsNewEntry(area: area, text: rest.prefix(1).uppercased() + rest.dropFirst())
            }
        }
        return WhatsNewEntry(area: nil, text: text)
    }
}

@MainActor
@Observable
final class WhatsNewCenter {
    static let shared = WhatsNewCenter()

    /// Sheet content; nil = nothing to show.
    var presented: [WhatsNewRelease]?

    nonisolated static let lastSeenKey = "resona.whatsNew.lastSeenVersion"

    private init() {}

    /// Launch: after an update, the notes since the last seen version.
    /// First launch only records the version (the onboarding greets).
    func checkOnLaunch(isFirstLaunch: Bool) {
        guard !TestMode.isUITest, !Self.isUnitTestHost else { return }
        let installed = UpdateChecker.installedVersion
        let defaults = UserDefaults.standard
        let lastSeen = defaults.string(forKey: Self.lastSeenKey)
        guard !isFirstLaunch else {
            defaults.set(installed, forKey: Self.lastSeenKey)
            return
        }
        // Users from before this feature: show this version's notes once.
        let since = lastSeen ?? Self.previousVersion(of: installed)
        guard lastSeen == nil || UpdateChecker.isNewer(installed, than: since) else { return }
        Task {
            let releases = await Self.releases(after: since, upTo: installed)
            guard !releases.isEmpty else { return }
            presented = releases
        }
    }

    func acknowledge() {
        UserDefaults.standard.set(UpdateChecker.installedVersion, forKey: Self.lastSeenKey)
        presented = nil
    }

    nonisolated static var isUnitTestHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// "0.8.11" → "0.8.10" (patch − 1; the release just before).
    nonisolated static func previousVersion(of version: String) -> String {
        var parts = version.split(separator: ".").map { Int($0) ?? 0 }
        guard !parts.isEmpty else { return version }
        if parts[parts.count - 1] > 0 { parts[parts.count - 1] -= 1 }
        return parts.map(String.init).joined(separator: ".")
    }

    /// Releases newer than `since` and not newer than `installed`, newest
    /// first (at most 5).
    nonisolated static func releases(after since: String, upTo installed: String) async -> [WhatsNewRelease] {
        guard let url = URL(string: "https://api.github.com/repos/\(UpdateChecker.repository)/releases?per_page=30") else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return select(list, after: since, upTo: installed)
    }

    nonisolated static func select(_ list: [[String: Any]], after since: String, upTo installed: String) -> [WhatsNewRelease] {
        let releases: [(String, WhatsNewRelease)] = list.compactMap { json in
            guard json["draft"] as? Bool != true, json["prerelease"] as? Bool != true,
                  let tag = json["tag_name"] as? String else { return nil }
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            guard UpdateChecker.isNewer(version, than: since), !UpdateChecker.isNewer(version, than: installed) else { return nil }
            let sections = WhatsNewParser.sections(from: json["body"] as? String ?? "")
            guard !sections.isEmpty else { return nil }
            let page = (json["html_url"] as? String).flatMap(URL.init(string:))
            return (version, WhatsNewRelease(version: version, sections: sections, pageURL: page))
        }
        return releases
            .sorted { UpdateChecker.isNewer($0.0, than: $1.0) }
            .prefix(5)
            .map(\.1)
    }
}

// MARK: - Sheet

struct WhatsNewSheet: View {
    let releases: [WhatsNewRelease]
    /// Default: the launch sheet, which records the version as seen.
    var onContinue: () -> Void = { WhatsNewCenter.shared.acknowledge() }
    @Environment(\.m3) private var m3
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        M3IconCircle(size: 56) { Image(systemName: "sparkles") }
                        Text("What's new in Resona")
                            .font(.m3(.headlineMedium))
                            .foregroundStyle(m3.onSurface)
                            .padding(.top, 6)
                    }
                    ForEach(releases) { release in
                        releaseView(release)
                    }
                }
                .padding(24)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    onContinue()
                } label: {
                    Text("Continue").frame(maxWidth: 320)
                }
                .buttonStyle(.m3Filled)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
                .accessibilityIdentifier("whatsNew.continue")
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(M3Shape.extraLarge)
        .presentationBackground { ResonaGlassBackground() }
        .interactiveDismissDisabled(false)
    }

    @ViewBuilder
    private func releaseView(_ release: WhatsNewRelease) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(verbatim: "Resona \(release.version)")
                    .font(.m3(.titleLarge))
                    .foregroundStyle(m3.onSurface)
                Spacer()
                if let page = release.pageURL {
                    Button("On GitHub") { openURL(page) }
                        .buttonStyle(.m3Text)
                }
            }
            if release.sections.isEmpty {
                Text("No release notes for this version.")
                    .font(.m3(.bodyMedium))
                    .foregroundStyle(m3.onSurfaceVariant)
            }
            ForEach(release.sections) { section in
                VStack(alignment: .leading, spacing: 8) {
                    Label(section.category.title, systemImage: section.category.icon)
                        .font(.m3(.titleSmall))
                        .foregroundStyle(m3.primary)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(section.entries.enumerated()), id: \.offset) { index, entry in
                            if index > 0 { M3RowDivider() }
                            VStack(alignment: .leading, spacing: 2) {
                                if let area = entry.area {
                                    Text(area)
                                        .font(.m3(.labelLarge))
                                        .foregroundStyle(m3.onSurface)
                                }
                                Text(entry.text)
                                    .font(.m3(.bodyMedium))
                                    .foregroundStyle(m3.onSurfaceVariant)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                    }
                    .background(m3.surfaceContainerHigh.opacity(0.7), in: RoundedRectangle(cornerRadius: M3Shape.large, style: .continuous))
                }
            }
        }
    }
}
