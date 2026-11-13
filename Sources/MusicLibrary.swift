import MediaPlayer
import UIKit

struct Track: Identifiable, Hashable {
    let id: UInt64
    let title, artist, album: String
    let duration: Double
    let url: URL?          // nil = DRM / cloud-only; not playable via AVPlayer
    let item: MPMediaItem?
    var artworkData: Data? = nil
    var artworkURL: URL? = nil
    var ytID: String? = nil   // YouTube video id; stream URL is resolved lazily at play time
    var artwork: UIImage? { item?.artwork?.image(at: CGSize(width: 600, height: 600)) ?? artworkData.flatMap(UIImage.init(data:)) }
    static func == (a: Track, b: Track) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

@MainActor final class MusicLibrary: ObservableObject {
    @Published var status = MPMediaLibrary.authorizationStatus()
    @Published var songs: [Track] = []
    @Published var skipped = 0
    init() {
        NotificationCenter.default.addObserver(forName: .MPMediaLibraryDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.load() }
        }
        MPMediaLibrary.default().beginGeneratingLibraryChangeNotifications()
        if status == .authorized { load() }
    }
    func requestAndLoad() async {
        status = await withCheckedContinuation { c in MPMediaLibrary.requestAuthorization { c.resume(returning: $0) } }
        if status == .authorized { load() }
    }
    func load() {
        let q = MPMediaQuery.songs()
        q.addFilterPredicate(MPMediaPropertyPredicate(value: false, forProperty: MPMediaItemPropertyIsCloudItem))
        let items = q.items ?? []
        let all = items.map { Track(id: $0.persistentID, title: $0.title ?? "Unknown", artist: $0.artist ?? "Unknown Artist",
                                    album: $0.albumTitle ?? "Unknown Album", duration: $0.playbackDuration, url: $0.assetURL, item: $0) }
        songs = all.filter { $0.url != nil }
        skipped = all.count - songs.count
    }
}
