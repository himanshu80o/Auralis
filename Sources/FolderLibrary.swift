import AVFoundation
import SwiftUI

/// Scans user-chosen Files folders. Access is saved as security-scoped bookmarks so the user picks once.
@MainActor final class FolderLibrary: ObservableObject {
    @Published var tracks: [Track] = []
    @Published var folderNames: [String] = []
    @Published var scanning = false
    private let key = "folderBookmarks"
    private var open: [URL] = []
    private var bookmarks: [Data] {
        get { UserDefaults.standard.array(forKey: key) as? [Data] ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
    static let exts: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "alac", "flac"]

    init() { Task { await rescan() } }

    func add(_ url: URL) async {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        if let d = try? url.bookmarkData() { bookmarks.append(d) }
        await rescan()
    }
    func removeAll() {
        open.forEach { $0.stopAccessingSecurityScopedResource() }; open = []
        bookmarks = []; tracks = []; folderNames = []
    }
    func rescan() async {
        scanning = true; defer { scanning = false }
        open.forEach { $0.stopAccessingSecurityScopedResource() }; open = []
        var found: [Track] = [], names: [String] = [], fresh: [Data] = []
        for data in bookmarks {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale),
                  url.startAccessingSecurityScopedResource() else { continue }
            open.append(url)   // keep access open while files may be playing
            names.append(url.lastPathComponent)
            fresh.append(stale ? ((try? url.bookmarkData()) ?? data) : data)
            for f in Self.audioFiles(in: url) { found.append(await Self.makeTrack(f)) }
        }
        bookmarks = fresh; folderNames = names
        var seen = Set<UInt64>()
        tracks = found.filter { seen.insert($0.id).inserted }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func delete(_ t: Track) {
        guard let u = t.url, u.isFileURL else { return }
        try? FileManager.default.removeItem(at: u)
        tracks.removeAll { $0.id == t.id }
    }
    nonisolated static func audioFiles(in dir: URL) -> [URL] {
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        return e.compactMap { $0 as? URL }.filter { exts.contains($0.pathExtension.lowercased()) }
    }
    nonisolated static func makeTrack(_ url: URL) async -> Track {
        let asset = AVURLAsset(url: url)
        let meta = (try? await asset.load(.commonMetadata)) ?? []
        func text(_ id: AVMetadataIdentifier) async -> String? {
            guard let m = AVMetadataItem.metadataItems(from: meta, filteredByIdentifier: id).first else { return nil }
            return try? await m.load(.stringValue)
        }
        var art: Data?
        if let m = AVMetadataItem.metadataItems(from: meta, filteredByIdentifier: .commonIdentifierArtwork).first { art = try? await m.load(.dataValue) }
        let dur = (try? await asset.load(.duration).seconds) ?? 0
        var h: UInt64 = 14695981039346656037          // stable FNV-1a id from path
        for b in url.path.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return Track(id: h, title: await text(.commonIdentifierTitle) ?? url.deletingPathExtension().lastPathComponent,
                     artist: await text(.commonIdentifierArtist) ?? "Unknown Artist",
                     album: await text(.commonIdentifierAlbumName) ?? url.deletingLastPathComponent().lastPathComponent,
                     duration: dur.isFinite ? dur : 0, url: url, item: nil, artworkData: art)
    }
}
