import AVFoundation
import SwiftUI

// MARK: - Regions
enum Regions {
    static var defaultCode: String { Locale.current.region?.identifier ?? "IN" }
    static var current: String { UserDefaults.standard.string(forKey: "region") ?? defaultCode }
    static let all: [(code: String, name: String)] = Locale.Region.isoRegions.compactMap { r in
        let id = r.identifier
        guard id.count == 2, let n = Locale.current.localizedString(forRegionCode: id) else { return nil }
        return (id, n)
    }.sorted { $0.name < $1.name }
    static func name(_ c: String) -> String { Locale.current.localizedString(forRegionCode: c) ?? c }
    static func flag(_ c: String) -> String {
        c.uppercased().unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }.map { String($0) }.joined()
    }
    static func trendingQuery(_ c: String) -> String { c == "IN" ? "top hindi punjabi songs this week" : "top songs in \(name(c)) this week" }
    static func albumQuery(_ c: String) -> String { "popular albums \(name(c))" }
}

@MainActor final class UIState: ObservableObject {
    @Published var showPlayer = false
}

// MARK: - Saved tracks (favourites / recents)
struct SavedTrack: Codable {
    let id: UInt64, title: String, artist: String, duration: Double
    let url: String?, art: String?, yt: String?
    init(_ t: Track) {
        id = t.id; title = t.title; artist = t.artist; duration = t.duration; yt = t.ytID
        if t.ytID != nil { url = nil; art = nil } else { url = t.url?.absoluteString; art = t.artworkURL?.absoluteString }  // yt tracks are re-resolved, never store stale URLs
    }
    var track: Track {
        Track(id: id, title: title, artist: artist, album: "Auralis", duration: duration, url: url.flatMap(URL.init(string:)), item: nil,
              artworkURL: yt.map(Track.ytThumb) ?? art.flatMap(URL.init(string:)), ytID: yt)
    }
}

@MainActor final class FavoritesStore: ObservableObject {
    @Published private(set) var items: [Track] = []
    private let key = "auralis.favs"
    init() { if let d = UserDefaults.standard.data(forKey: key), let s = try? JSONDecoder().decode([SavedTrack].self, from: d) { items = s.map(\.track) } }
    func contains(_ t: Track) -> Bool { items.contains { $0.id == t.id } }
    func toggle(_ t: Track) {
        if contains(t) { items.removeAll { $0.id == t.id } } else { items.insert(t, at: 0) }
        if let d = try? JSONEncoder().encode(items.map(SavedTrack.init)) { UserDefaults.standard.set(d, forKey: key) }
    }
}

@MainActor final class RecentStore: ObservableObject {
    @Published private(set) var items: [Track] = []
    private let key = "auralis.recents"
    init() { if let d = UserDefaults.standard.data(forKey: key), let s = try? JSONDecoder().decode([SavedTrack].self, from: d) { items = s.map(\.track) } }
    func add(_ t: Track) {
        guard t.ytID != nil || t.artworkURL != nil else { return }
        items.removeAll { $0.id == t.id }; items.insert(t, at: 0); items = Array(items.prefix(20))
        if let d = try? JSONEncoder().encode(items.map(SavedTrack.init)) { UserDefaults.standard.set(d, forKey: key) }
    }
}

// MARK: - Downloads (highest-bitrate AAC available, saved in Documents/Auralis Downloads)
struct DownloadedItem: Codable, Identifiable {
    let yt: String, title: String, artist: String, duration: Double, file: String, art: String?
    var id: String { yt }
}

final class Downloader: NSObject, URLSessionDownloadDelegate {
    private var cont: CheckedContinuation<URL, Error>?
    private var onProgress: ((Double) -> Void)?
    private var session: URLSession!
    func run(_ req: URLRequest, progress: @escaping (Double) -> Void) async throws -> URL {
        onProgress = progress
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { c in cont = c; session.downloadTask(with: req).resume() }
    }
    func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten w: Int64, totalBytesExpectedToWrite e: Int64) {
        if e > 0 { onProgress?(Double(w) / Double(e)) }
    }
    func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didFinishDownloadingTo loc: URL) {
        let code = (t.response as? HTTPURLResponse)?.statusCode ?? 0
        let size = (try? FileManager.default.attributesOfItem(atPath: loc.path)[.size] as? Int) ?? 0
        guard (200..<300).contains(code), size > 20_000 else { cont?.resume(throwing: URLError(.badServerResponse)); cont = nil; return }
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do { try FileManager.default.moveItem(at: loc, to: dest); cont?.resume(returning: dest) } catch { cont?.resume(throwing: error) }
        cont = nil
    }
    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError e: Error?) {
        if let e { cont?.resume(throwing: e); cont = nil }
    }
}

@MainActor final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()
    @Published private(set) var items: [DownloadedItem] = []
    @Published private(set) var progress: [String: Double] = [:]
    @Published var lastError: String?
    private let dir: URL
    private var index: URL { dir.appendingPathComponent("index.json") }

    init() {
        dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Auralis Downloads")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let d = try? Data(contentsOf: index), let i = try? JSONDecoder().decode([DownloadedItem].self, from: d) {
            items = i.filter { FileManager.default.fileExists(atPath: dir.appendingPathComponent($0.file).path) }
        }
    }
    private func save() { if let d = try? JSONEncoder().encode(items) { try? d.write(to: index) } }
    func fileURL(_ f: String) -> URL { dir.appendingPathComponent(f) }
    func isDownloaded(_ yt: String) -> Bool { items.contains { $0.yt == yt } }
    func localURL(_ yt: String) -> URL? {
        guard let i = items.first(where: { $0.yt == yt }) else { return nil }
        let u = fileURL(i.file); return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }
    func track(_ i: DownloadedItem) -> Track {
        Track(id: fnv(i.yt), title: i.title, artist: i.artist, album: "Downloads", duration: i.duration, url: fileURL(i.file), item: nil,
              artworkURL: i.art.map(fileURL) ?? Track.ytThumb(i.yt), ytID: i.yt)
    }
    var tracks: [Track] { items.map(track) }

    func download(_ t: Track) {
        guard let yt = t.ytID, progress[yt] == nil, !isDownloaded(yt) else { return }
        progress[yt] = 0
        Task { await run(t, yt) }
    }
    func downloadAll(_ list: [Track]) {
        Task { for t in list where t.ytID != nil && !isDownloaded(t.ytID!) { download(t); try? await Task.sleep(for: .milliseconds(400)) } }
    }
    /// muxed (video+audio) mp4 -> audio-only m4a
    nonisolated static func extractAudio(_ src: URL, to dest: URL) async throws {
        let asset = AVURLAsset(url: src)
        guard let ex = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { throw URLError(.cannotCreateFile) }
        ex.outputURL = dest; ex.outputFileType = .m4a
        await ex.export()
        guard ex.status == .completed else { throw ex.error ?? URLError(.cannotCreateFile) }
    }
    nonisolated static func isPlayable(_ u: URL) async -> Bool {
        (try? await AVURLAsset(url: u).load(.isPlayable)) ?? false
    }
    private func run(_ t: Track, _ yt: String) async {
        defer { progress[yt] = nil }
        var reason = ""
        for attempt in 0..<3 {
            do {
                let s = try await Resolver.shared.stream(yt, fresh: attempt > 0)   // links are probed before use, so a dead link never gets here
                var req = URLRequest(url: s.url, timeoutInterval: 60)
                s.headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
                req.setValue("bytes=0-", forHTTPHeaderField: "Range")
                let tmp = try await Downloader().run(req) { p in
                    Task { @MainActor in if p - (self.progress[yt] ?? 0) >= 0.03 { self.progress[yt] = p } }
                }
                let name = "\(yt).m4a", dest = fileURL(name)
                try? FileManager.default.removeItem(at: dest)
                if s.muxed {
                    let mp4 = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
                    try FileManager.default.moveItem(at: tmp, to: mp4)
                    defer { try? FileManager.default.removeItem(at: mp4) }
                    try await Self.extractAudio(mp4, to: dest)
                } else {
                    try FileManager.default.moveItem(at: tmp, to: dest)
                }
                guard await Self.isPlayable(dest) else {
                    try? FileManager.default.removeItem(at: dest)
                    throw ResolveError(message: "file not playable")
                }
                var art: String?
                if let (d, _) = try? await URLSession.shared.data(from: Track.ytThumb(yt)) { try? d.write(to: fileURL("\(yt).jpg")); art = "\(yt).jpg" }
                items.removeAll { $0.yt == yt }
                items.insert(DownloadedItem(yt: yt, title: t.title, artist: t.artist, duration: t.duration, file: name, art: art), at: 0)
                save(); return
            } catch {
                reason = (error as? ResolveError)?.message ?? (error as? URLError).map { "network \($0.code.rawValue)" } ?? error.localizedDescription
                try? await Task.sleep(for: .milliseconds(600))
            }
        }
        lastError = "Download failed for “\(t.title)” (\(reason.prefix(100)))"
    }
    func delete(_ i: DownloadedItem) {
        try? FileManager.default.removeItem(at: fileURL(i.file))
        if let a = i.art { try? FileManager.default.removeItem(at: fileURL(a)) }
        items.removeAll { $0.yt == i.yt }; save()
    }
}
