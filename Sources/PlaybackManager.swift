import AVFoundation
import MediaPlayer
import UIKit

enum RepeatMode: CaseIterable { case off, all, one }

@MainActor final class PlaybackManager: ObservableObject {
    static let shared = PlaybackManager()
    @Published var queue: [Track] = []
    @Published var index = 0
    @Published var isPlaying = false
    @Published var position = 0.0
    @Published var duration = 0.0
    @Published var repeatMode = RepeatMode.off
    @Published var shuffle = false { didSet { applyShuffle() } }
    private var original: [Track] = []
    private let player = AVPlayer()
    var current: Track? { queue.indices.contains(index) ? queue[index] : nil }

    private init() {
        configureSession(); setupRemote()
        player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] t in
            Task { @MainActor in
                guard let s = self else { return }
                s.position = t.seconds.isFinite ? t.seconds : 0
                s.updateNowPlaying()
            }
        }
        let nc = NotificationCenter.default
        nc.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.trackEnded() } }
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
    }
    private func interruption(_ type: UInt?, _ opt: UInt?) {
        if type == AVAudioSession.InterruptionType.began.rawValue { isPlaying = false }
        else if type == AVAudioSession.InterruptionType.ended.rawValue,
                AVAudioSession.InterruptionOptions(rawValue: opt ?? 0).contains(.shouldResume) { play() }
    }

    func start(_ tracks: [Track], at i: Int) {
        original = tracks; queue = tracks; index = i
        if shuffle { applyShuffle() } else { load() }
    }
    private func applyShuffle() {
        guard let cur = current else { return }
        if shuffle { queue = [cur] + original.filter { $0 != cur }.shuffled(); index = 0 }
        else { queue = original; index = original.firstIndex(of: cur) ?? 0 }
    }
    private func load() {
        guard let t = current, let url = t.url else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        duration = t.duration; position = 0
        play()
    }
    func play() { player.play(); isPlaying = true; updateNowPlaying() }
    func pause() { player.pause(); isPlaying = false; updateNowPlaying() }
    func toggle() { isPlaying ? pause() : play() }
    func seek(_ s: Double) { player.seek(to: CMTime(seconds: s, preferredTimescale: 600)); position = s }
    func next() {
        guard !queue.isEmpty else { return }
        if index + 1 < queue.count { index += 1 } else if repeatMode == .all { index = 0 } else { pause(); return }
        load()
    }
    func previous() {
        if position > 3 { seek(0); return }
        index = max(0, index - 1); load()
    }
    func cycleRepeat() {
        let all = RepeatMode.allCases; repeatMode = all[(all.firstIndex(of: repeatMode)! + 1) % all.count]
    }
    private func trackEnded() { if repeatMode == .one { seek(0); play() } else { next() } }

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
        var info: [String: Any] = [MPMediaItemPropertyTitle: t.title, MPMediaItemPropertyArtist: t.artist,
            MPMediaItemPropertyAlbumTitle: t.album, MPMediaItemPropertyPlaybackDuration: t.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position, MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0]
        if let img = t.artwork { info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: img.size) { _ in img } }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
