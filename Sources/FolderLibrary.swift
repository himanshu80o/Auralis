import AVFoundation
import SwiftUI

/// Scans user-chosen Files folders (security-scoped bookmarks). Scanning runs off the main thread, in parallel,
/// and results are cached by file modification date, so re-opening the app is instant even with thousands of songs.
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
    nonisolated static let exts: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "alac", "flac"]

    struct Meta: Codable, Sendable { let path: String; let mtime: Double; let title, artist, album: String; let duration: Double }
    nonisolated private static var cacheURL: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("folder-meta.json") }

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
        guard !scanning else { return }
        scanning = true; defer { scanning = false }
        open.forEach { $0.stopAccessingSecurityScopedResource() }; open = []
        var names: [String] = [], fresh: [Data] = []
        for data in bookmarks {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale),
                  url.startAccessingSecurityScopedResource() else { continue }
            open.append(url)   // keep access open while files may be playing
            names.append(url.lastPathComponent)
            fresh.append(stale ? ((try? url.bookmarkData()) ?? data) : data)
        }
        bookmarks = fresh; folderNames = names
        let roots = open
        let metas = await Task.detached(priority: .userInitiated) { await Self.scan(roots) }.value
        var seen = Set<UInt64>()
        tracks = metas.map { m in
            Track(id: fnv(m.path), title: m.title, artist: m.artist, album: m.album, duration: m.duration, url: URL(fileURLWithPath: m.path), item: nil)
        }.filter { seen.insert($0.id).inserted }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func delete(_ t: Track) {
        guard let u = t.url, u.isFileURL else { return }
        try? FileManager.default.removeItem(at: u)
        tracks.removeAll { $0.id == t.id }
    }

    // MARK: background scanning
    nonisolated static func scan(_ roots: [URL]) async -> [Meta] {
        let files = audioFiles(in: roots)
        var cache: [String: Meta] = [:]
        if let d = try? Data(contentsOf: cacheURL), let l = try? JSONDecoder().decode([Meta].self, from: d) { l.forEach { cache[$0.path] = $0 } }
        var out: [Meta] = []
        for start in stride(from: 0, to: files.count, by: 8) {      // 8 files in parallel
            let batch = Array(files[start..<min(start + 8, files.count)])
            let part = await withTaskGroup(of: Meta.self) { g -> [Meta] in
                for f in batch { g.addTask { await meta(f, cache[f.path]) } }
                var r: [Meta] = []; for await m in g { r.append(m) }; return r
            }
            out += part
        }
        if let d = try? JSONEncoder().encode(out) { try? d.write(to: cacheURL) }
        return out
    }
    nonisolated static func audioFiles(in roots: [URL]) -> [URL] {   // sync on purpose (NSEnumerator is not async-safe)
        var files: [URL] = []
        for r in roots {
            guard let e = FileManager.default.enumerator(at: r, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { continue }
            while let o = e.nextObject() { if let u = o as? URL, exts.contains(u.pathExtension.lowercased()) { files.append(u) } }
        }
        return files
    }
    nonisolated static func meta(_ url: URL, _ cached: Meta?) async -> Meta {
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate?.timeIntervalSince1970) ?? 0
        if let c = cached, c.mtime == mtime { return c }
        let asset = AVURLAsset(url: url)
        let meta = (try? await asset.load(.commonMetadata)) ?? []
        func text(_ id: AVMetadataIdentifier) async -> String? {
            guard let m = AVMetadataItem.metadataItems(from: meta, filteredByIdentifier: id).first else { return nil }
            return try? await m.load(.stringValue)
        }
        let dur = (try? await asset.load(.duration).seconds) ?? 0
        return Meta(path: url.path, mtime: mtime,
                    title: await text(.commonIdentifierTitle) ?? url.deletingPathExtension().lastPathComponent,
                    artist: await text(.commonIdentifierArtist) ?? "Unknown Artist",
                    album: await text(.commonIdentifierAlbumName) ?? url.deletingLastPathComponent().lastPathComponent,
                    duration: dur.isFinite ? dur : 0)
    }
}
