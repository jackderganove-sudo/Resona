//
//  FeatherInstaller.swift
//  Resona
//
//  Installs updates through Feather (github.com/khcrysalis/Feather).
//  Verified in Feather's source (FeatherApp._handleURL, Info.plist,
//  commit 31ab6de):
//  - scheme `feather` (CFBundleURLSchemes)
//  - feather://install/<https URL of an .ipa> → "Install?" → download
//  - feather://source/<https URL>               → adds the source
//  The URL is appended as is and must start with https:// (validatedScheme).
//  Feather also owns the .ipa document type, so a downloaded IPA can be
//  handed to it from the share sheet.
//
//  Fallback when Feather doesn't answer the scheme: download the IPA here
//  (with progress) and open the share sheet with the file — no Safari.
//

import Foundation
import Observation
import UIKit

enum FeatherLinks {
    static func install(_ ipa: URL) -> URL? {
        guard ipa.scheme == "https" else { return nil }
        return URL(string: "feather://install/" + ipa.absoluteString)
    }

    static func addSource(_ source: URL) -> URL? {
        guard source.scheme == "https" else { return nil }
        return URL(string: "feather://source/" + source.absoluteString)
    }
}

@MainActor
@Observable
final class FeatherInstaller: NSObject {
    static let shared = FeatherInstaller()

    enum Phase: Equatable {
        case idle
        case downloading(Double)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private var task: URLSessionDownloadTask?
    private var version = ""
    private var observation: NSKeyValueObservation?

    /// "Install in Feather": Feather's install scheme; if Feather doesn't
    /// open, download + share sheet.
    func install(_ update: AvailableUpdate) {
        guard let link = FeatherLinks.install(update.ipaURL) else {
            downloadAndShare(update)
            return
        }
        UIApplication.shared.open(link, options: [:]) { [weak self] opened in
            guard !opened else { return }
            Task { @MainActor in self?.downloadAndShare(update) }
        }
    }

    func addSourceToFeather() {
        guard let source = URL(string: UpdateChecker.sourceURL), let link = FeatherLinks.addSource(source) else { return }
        UIApplication.shared.open(link)
    }

    /// Downloads the IPA into the temporary folder and shows the share sheet.
    func downloadAndShare(_ update: AvailableUpdate) {
        guard task == nil else { return }
        version = update.version
        phase = .downloading(0)
        let download = URLSession.shared.downloadTask(with: update.ipaURL) { [weak self] location, response, error in
            // The file at `location` is gone once this handler returns.
            var result: Result<URL, Error>
            if let location, (response as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) ?? false {
                do {
                    result = .success(try Self.keep(location, version: update.version))
                } catch {
                    result = .failure(error)
                }
            } else {
                result = .failure(error ?? URLError(.badServerResponse))
            }
            Task { @MainActor in self?.finish(result) }
        }
        observation = download.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            let fraction = progress.fractionCompleted
            Task { @MainActor in
                if case .downloading = self?.phase { self?.phase = .downloading(fraction) }
            }
        }
        task = download
        download.resume()
    }

    func cancel() {
        task?.cancel()
        task = nil
        observation = nil
        phase = .idle
    }

    private func finish(_ result: Result<URL, Error>) {
        task = nil
        observation = nil
        switch result {
        case .success(let file):
            phase = .idle
            presentShareSheet(items: [file])
        case .failure(let error):
            if (error as? URLError)?.code == .cancelled {
                phase = .idle
            } else {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    nonisolated private static func keep(_ location: URL, version: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ResonaUpdate", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent("Resona-\(version).ipa")
        try FileManager.default.moveItem(at: location, to: target)
        return target
    }
}
