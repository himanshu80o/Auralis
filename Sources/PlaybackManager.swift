import AVFoundation
import MediaPlayer
import UIKit
import Combine

enum RepeatMode: CaseIterable { case off, all, one }

/// Position/duration live in their own object so the 2x/second ticks only redraw the progress bars, not the whole app.
@MainActor final class PlayClock: ObservableObject {
    @Published var position = 0.0
    @Published var duration = 0.0
}

@MainActor final class PlaybackManager: ObservableObject {
    static let shared = PlaybackManager()
    let clock = PlayClock()
    @Published var queue: [Track] = []
    @Published var index = 0
    @Published var isPlaying = false
    @Published var isResolving = false
    @Published var streamError: String?
    @Published var repeatMode = RepeatMode.off
    @Published var shuffle = false { didSet { applyShuffle() } }
    @Published var sleepEnd: Date?

    private var sleepTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var statusObs: AnyCancellable?
    private var original: [Track] = []
    private var onlineID: String?
    private var source = ""
    private var retries = 0
    private var seeking = false
    private let player = AVPlayer()
    var current: Track? { queue.indices.contains(index) ? queue[index] : nil }

    private init() {
        configureSession(); setupRemote()
        player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] t in
            Task { @MainActor in
                guard let s = self, !s.seeking else { return }
                let p = t.seconds.isFinite ? t.seconds : 0
                if abs(p - s.clock.position) > 0.2 { s.clock.position = p }
                if let d = s.player.currentItem?.duration.seconds, d.isFinite, d > 0, abs(d - s.clock.duration) > 0.5 { s.clock.duration = d }
            }
        }
        let nc = NotificationCenter.default
        nc.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] n in
            let item = n.object as? AVPlayerItem
            Task { @MainActor in if let s = self, item === s.player.currentItem { s.trackEnded() } }   // ignore the video player's items
        }
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let opt = n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            Task { @MainActor in self?.interruption(raw, opt) }
        }
        nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] n in
            let r = n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor in if r == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { self?.pause() } }
        }
    }

    private func configureSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
    }
    private func interruption(_ type: UInt?, _ opt: UInt?) {
        if type == AVAudioSession.InterruptionType.began.rawValue { isPlaying = false }
        else if type == AVAudioSession.InterruptionType.ended.rawValue,
                AVAudioSession.InterruptionOptions(rawValue: opt ?? 0).contains(.shouldResume) { play() }
    }

    // MARK: queue
    func start(_ tracks: [Track], at i: Int) {
        guard tracks.indices.contains(i) else { return }
        original = tracks; queue = tracks; index = i
        if shuffle { applyShuffle() } else { load() }
    }
    private func applyShuffle() {
        guard let cur = current else { return }
        if shuffle { queue = [cur] + original.filter { $0 != cur }.shuffled(); index = 0 }
        else { queue = original; index = original.firstIndex(of: cur) ?? 0 }
    }
    func stop() {
        loadTask?.cancel(); watchdog?.cancel(); statusObs = nil
        player.pause(); player.replaceCurrentItem(with: nil)
        queue = []; index = 0; isPlaying = false; isResolving = false; streamError = nil
        clock.position = 0; clock.duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: loading
    private func load() {
        loadTask?.cancel(); watchdog?.cancel(); statusObs = nil
        guard let t = current else { return }
        streamError = nil; retries = 0; seeking = false
        clock.duration = t.duration; clock.position = 0
        if let yt = t.ytID, let local = DownloadManager.shared.localURL(yt) { isResolving = false; startItem(local); return }   // downloaded = instant + offline
        if let url = t.url { isResolving = false; startItem(url); return }
        guard let id = t.ytID else { return }
        loadOnline(t, id, fresh: false)
    }
    private func loadOnline(_ t: Track, _ id: String, fresh: Bool) {
        isResolving = true; isPlaying = false
        player.pause(); player.replaceCurrentItem(with: nil)
        updateNowPlaying()
        // keeps the app running in background / screen-off while the next stream is being resolved
        let bg = UIApplication.shared.beginBackgroundTask(withName: "auralis.resolve", expirationHandler: nil)
        loadTask = Task { [weak self] in
            defer { UIApplication.shared.endBackgroundTask(bg) }
            do {
                let s = try await Resolver.shared.stream(id, fresh: fresh)
                guard let self, !Task.isCancelled, self.current?.id == t.id else { return }
                self.isResolving = false
                self.startItem(s.url, headers: s.headers, onlineID: id, source: s.source)
            } catch {
                guard let self, !Task.isCancelled, self.current?.id == t.id else { return }
                self.isResolving = false
                self.streamError = "Couldn't load this track. Check your internet and try again."
            }
        }
    }
    private func startItem(_ url: URL, headers: [String: String] = [:], onlineID: String? = nil, source: String = "") {
        self.onlineID = onlineID; self.source = source
        try? AVAudioSession.sharedInstance().setActive(true)
        let asset = AVURLAsset(url: url, options: headers.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        statusObs = item.publisher(for: \.status).receive(on: DispatchQueue.main).sink { [weak self] st in
            Task { @MainActor in
                guard let self else { return }
                if st == .readyToPlay { self.retries = 0; self.watchdog?.cancel() }
                else if st == .failed { self.itemFailed() }
            }
        }
        player.replaceCurrentItem(with: item)
        play()
        watchdog?.cancel()
        if onlineID != nil {   // if a stream never becomes ready, switch to another source automatically
            watchdog = Task { [weak self] in
                try? await Task.sleep(for: .seconds(12))
                guard !Task.isCancelled, let self, self.player.currentItem === item, item.status != .readyToPlay else { return }
                self.itemFailed()
            }
        }
        prefetchNext()
    }
    private func itemFailed() {
        guard let t = current else { return }
        guard let id = onlineID, retries < 3 else {
            isResolving = false; isPlaying = false; streamError = "Couldn't play this track. Try another one."; return
        }
        retries += 1; let src = source
        player.pause(); isResolving = true
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await Resolver.shared.markBad(id, source: src)
            guard let self, !Task.isCancelled, self.current?.id == t.id else { return }
            self.loadOnline(t, id, fresh: true)
        }
    }
    private func prefetchNext() {   // next track starts instantly
        let n = index + 1
        guard queue.indices.contains(n), let id = queue[n].ytID, DownloadManager.shared.localURL(id) == nil else { return }
        Task { await Resolver.shared.prefetch(id) }
    }

    // MARK: transport
    func play() { player.play(); isPlaying = true; updateNowPlaying() }
    func pause() { player.pause(); isPlaying = false; updateNowPlaying() }
    func toggle() { isPlaying ? pause() : play() }
    func seek(_ s: Double) {
        let target = max(0, min(s, clock.duration > 0 ? clock.duration : s))
        seeking = true; clock.position = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600)) { [weak self] _ in
            Task { @MainActor in self?.seeking = false; self?.updateNowPlaying() }
        }
    }
    func next() {
        guard !queue.isEmpty else { return }
        if index + 1 < queue.count { index += 1 } else if repeatMode == .all { index = 0 } else { pause(); return }
        load()
    }
    func previous() {
        if clock.position > 3 { seek(0); return }
        index = max(0, index - 1); load()
    }
    func cycleRepeat() { let all = RepeatMode.allCases; repeatMode = all[(all.firstIndex(of: repeatMode)! + 1) % all.count] }
    private func trackEnded() { if repeatMode == .one { seek(0); play() } else { next() } }

    func startSleep(minutes: Int) {
        sleepTask?.cancel(); sleepEnd = Date().addingTimeInterval(Double(minutes) * 60)
        sleepTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(minutes * 60))
            if !Task.isCancelled { self?.pause(); self?.sleepEnd = nil }
        }
    }
    func cancelSleep() { sleepTask?.cancel(); sleepEnd = nil }

    // MARK: lock screen / control centre
    private func setupRemote() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.play() }; return .success }
        c.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] e in
            if let e = e as? MPChangePlaybackPositionCommandEvent { Task { @MainActor in self?.seek(e.positionTime) } }
            return .success
        }
    }
    private func updateNowPlaying() {
        guard let t = current else { return }
        var info: [String: Any] = [MPMediaItemPropertyTitle: t.title, MPMediaItemPropertyArtist: t.artist, MPMediaItemPropertyAlbumTitle: t.album,
            MPMediaItemPropertyPlaybackDuration: clock.duration > 0 ? clock.duration : t.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: clock.position, MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0]
        if let img = ArtLoader.cached(t) { info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: img.size) { _ in img } }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        if ArtLoader.cached(t) == nil {
            Task { [weak self] in if await ArtLoader.image(for: t) != nil { self?.updateNowPlaying() } }
        }
    }
}
