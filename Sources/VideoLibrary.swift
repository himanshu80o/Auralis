import Photos
import AVKit
import SwiftUI

struct VideoItem: Identifiable { let id: String; let asset: PHAsset; var duration: Double { asset.duration } }

@MainActor final class VideoLibrary: ObservableObject {
    @Published var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published var videos: [VideoItem] = []
    init() { if status == .authorized || status == .limited { load() } }
    func requestAndLoad() async {
        status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        if status == .authorized || status == .limited { load() }
    }
    func load() {
        let o = PHFetchOptions(); o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let r = PHAsset.fetchAssets(with: .video, options: o)
        var out: [VideoItem] = []; r.enumerateObjects { a, _, _ in out.append(VideoItem(id: a.localIdentifier, asset: a)) }
        videos = out
    }
}

struct Thumb: View {
    let asset: PHAsset; @State private var img: UIImage?
    var body: some View {
        Group { if let img { Image(uiImage: img).resizable().scaledToFill() } else { Color.gray.opacity(0.3) } }
            .task {
                let o = PHImageRequestOptions(); o.isNetworkAccessAllowed = true
                PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 400, height: 400), contentMode: .aspectFill, options: o) { i, _ in img = i }
            }
    }
}

struct VideoPlayerScreen: View {
    let asset: PHAsset; @State private var player: AVPlayer?
    var body: some View {
        Group { if let player { VideoPlayer(player: player).onAppear { player.play() } } else { ProgressView("Loading (may download from iCloud)…") } }
            .task {
                let o = PHVideoRequestOptions(); o.isNetworkAccessAllowed = true
                PHImageManager.default().requestPlayerItem(forVideo: asset, options: o) { item, _ in
                    if let item { Task { @MainActor in player = AVPlayer(playerItem: item) } }
                }
            }
    }
}
