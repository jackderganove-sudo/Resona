//
//  LocalMusic.swift
//  Resona
//
//  Local music (round 10, after ArchiveTune 15's local songs): audio files
//  imported from the Files app are copied into Documents/LocalMusic with
//  their metadata (title, artist, album, duration, cover) and play like
//  downloads — offline, through the same player. Ids start with "local-",
//  so YouTube lookups (lyrics by title/artist still work) never confuse
//  them with videos.
//

import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct LocalTrack: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var artist: String
    var album: String?
    var duration: Int
    var fileName: String
    var artworkFileName: String?
    var addedAt: Date

    var songItem: SongItem {
        SongItem(videoId: id, title: title, artists: artist.isEmpty ? [] : [YTArtist(name: artist)], album: album,
                 duration: duration, thumbnailUrl: artworkFileName.map { LocalMusicLibrary.folder.appendingPathComponent($0).absoluteString },
                 isExplicit: false)
    }
}

@MainActor
@Observable
final class LocalMusicLibrary {
    static let shared = LocalMusicLibrary()
    static let idPrefix = "local-"

    private(set) var tracks: [LocalTrack] = []
    private(set) var isImporting = false
    private(set) var lastError: String?

    nonisolated static var folder: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("LocalMusic", isDirectory: true)
    }

    nonisolated static var indexURL: URL { folder.appendingPathComponent("index.json") }

    private init() {
        tracks = Self.loadIndex()
    }

    nonisolated static func isLocal(_ id: String) -> Bool { id.hasPrefix(idPrefix) }

    nonisolated static let mpvOnlyExtensions: Set<String> = ["ogg", "oga", "opus", "webm", "mka"]

    /// File of a local track for the player (nil = not local / missing).
    nonisolated static func fileURL(for id: String) -> URL? {
        guard isLocal(id),
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path),
              let name = names.first(where: { $0.hasPrefix(id + ".") && !$0.hasSuffix(".jpg") }) else { return nil }
        return folder.appendingPathComponent(name)
    }

    func importFiles(_ urls: [URL]) async {
        isImporting = true
        lastError = nil
        defer { isImporting = false }
        var failed = 0
        for url in urls {
            if let track = await Self.importFile(url) {
                tracks.insert(track, at: 0)
            } else {
                failed += 1
            }
        }
        save()
        if failed > 0 {
            lastError = String(format: String(localized: "%d files could not be imported."), failed)
        }
        Log.downloadManager.info("Local music import: \(urls.count - failed) ok, \(failed) failed")
    }

    func delete(_ track: LocalTrack) {
        tracks.removeAll { $0.id == track.id }
        if let url = Self.fileURL(for: track.id) { try? FileManager.default.removeItem(at: url) }
        if let art = track.artworkFileName { try? FileManager.default.removeItem(at: Self.folder.appendingPathComponent(art)) }
        save()
    }

    private func save() {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(tracks) { try? data.write(to: Self.indexURL, options: .atomic) }
    }

    nonisolated private static func loadIndex() -> [LocalTrack] {
        guard let data = try? Data(contentsOf: indexURL),
              let tracks = try? JSONDecoder().decode([LocalTrack].self, from: data) else { return [] }
        return tracks.filter { fileURL(for: $0.id) != nil }
    }

    /// Copies the file and reads its metadata; nil when it isn't playable audio.
    nonisolated static func importFile(_ source: URL) async -> LocalTrack? {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let id = idPrefix + UUID().uuidString.lowercased()
        let ext = source.pathExtension.isEmpty ? "m4a" : source.pathExtension.lowercased()
        let target = folder.appendingPathComponent("\(id).\(ext)")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: target)
        } catch {
            return nil
        }
        let asset = AVURLAsset(url: target)
        // AVFoundation can't read Ogg/Opus/Matroska, mpv plays them anyway.
        let playable = (try? await asset.load(.isPlayable)) ?? false
        guard playable || mpvOnlyExtensions.contains(ext) else {
            try? FileManager.default.removeItem(at: target)
            return nil
        }
        let duration = (try? await asset.load(.duration)).map { CMTimeGetSeconds($0) } ?? 0
        let metadata = (try? await asset.load(.commonMetadata)) ?? []
        func string(_ key: AVMetadataKey) async -> String? {
            guard let item = AVMetadataItem.metadataItems(from: metadata, withKey: key, keySpace: .common).first else { return nil }
            return (try? await item.load(.stringValue))?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let fallback = parseFileName(source.deletingPathExtension().lastPathComponent)
        let title = await string(.commonKeyTitle) ?? fallback.title
        let artist = await string(.commonKeyArtist) ?? fallback.artist ?? ""
        let album = await string(.commonKeyAlbumName)
        var artworkName: String?
        if let item = AVMetadataItem.metadataItems(from: metadata, withKey: AVMetadataKey.commonKeyArtwork, keySpace: .common).first,
           let data = try? await item.load(.dataValue), let image = UIImage(data: data),
           let jpeg = image.jpegData(compressionQuality: 0.85) {
            artworkName = "\(id).jpg"
            try? jpeg.write(to: folder.appendingPathComponent(artworkName!))
        }
        return LocalTrack(id: id, title: title.isEmpty ? fallback.title : title, artist: artist, album: album,
                          duration: duration.isFinite ? Int(duration.rounded()) : 0,
                          fileName: target.lastPathComponent, artworkFileName: artworkName, addedAt: Date())
    }

    /// "Artist - Title" (also "01 Artist - Title") from a file name.
    nonisolated static func parseFileName(_ name: String) -> (title: String, artist: String?) {
        var base = name.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
        if let range = base.range(of: #"^\d{1,3}[\s.\-]+"#, options: .regularExpression) { base.removeSubrange(range) }
        let parts = base.components(separatedBy: " - ")
        if parts.count >= 2 {
            return (parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces),
                    parts[0].trimmingCharacters(in: .whitespaces))
        }
        return (base, nil)
    }
}

// MARK: - View

struct LocalMusicView: View {
    @Environment(\.m3) private var m3
    private let library = LocalMusicLibrary.shared
    @State private var showImporter = false

    var body: some View {
        let songs = library.tracks.map(\.songItem)
        List {
            if library.tracks.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 42, weight: .light))
                        .foregroundStyle(m3.primary)
                    Text("No local music yet")
                        .font(.m3(.titleMedium))
                    Text("Import audio files (MP3, M4A, FLAC, WAV …) from the Files app. They play offline like downloads.")
                        .font(.m3(.bodyMedium))
                        .foregroundStyle(m3.onSurfaceVariant)
                        .multilineTextAlignment(.center)
                    Button("Import files") { showImporter = true }
                        .buttonStyle(.m3Filled)
                        .padding(.top, 6)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                HStack(spacing: 12) {
                    Button { PlaybackQueue.play(songs, log: Log.downloadManager, context: "Local music") } label: {
                        Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.m3Filled)
                    Button { PlaybackQueue.playShuffled(songs, log: Log.downloadManager, context: "Local music shuffle") } label: {
                        Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.m3Tonal)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                ForEach(Array(library.tracks.enumerated()), id: \.element.id) { index, track in
                    Button {
                        PlaybackQueue.play(songs, startIndex: index, log: Log.downloadManager, context: "Local music")
                    } label: {
                        HStack(spacing: 12) {
                            AsyncImageView(url: track.songItem.thumbnailUrl)
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay {
                                    if track.artworkFileName == nil { ArtworkPlaceholder(title: track.title).clipShape(RoundedRectangle(cornerRadius: 8)) }
                                }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title).font(.m3(.bodyLarge)).foregroundStyle(m3.onSurface).lineLimit(1)
                                Text([track.artist, track.album ?? ""].filter { !$0.isEmpty }.joined(separator: " • "))
                                    .font(.m3(.bodySmall)).foregroundStyle(m3.onSurfaceVariant).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Text(PlaylistCSV.duration(track.duration))
                                .font(.m3(.bodySmall).monospacedDigit())
                                .foregroundStyle(m3.onSurfaceVariant)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .swipeActions {
                        Button(role: .destructive) { library.delete(track) } label: { Label("Remove", systemImage: "trash") }
                    }
                }
            }
            if let error = library.lastError {
                Text(error)
                    .font(.m3(.bodySmall))
                    .foregroundStyle(m3.error)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .miniPlayerTracksScroll()
        .navigationTitle("Local music")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if library.isImporting {
                    ProgressView()
                } else {
                    Button { showImporter = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel(Text("Import files"))
                        .accessibilityIdentifier("localMusic.import")
                }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            Task { await library.importFiles(urls) }
        }
        .accessibilityIdentifier("localMusic")
    }
}
