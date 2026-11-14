import SwiftUI
import Photos

func fmt(_ s: Double) -> String { let t = Int(max(0, s)); return String(format: "%d:%02d", t / 60, t % 60) }

// MARK: - Music tab
struct SongsView: View {
    @EnvironmentObject var lib: MusicLibrary
    @EnvironmentObject var folders: FolderLibrary
    @EnvironmentObject var player: PlaybackManager
    @AppStorage("theme") private var theme = 0
    @Environment(\.colorScheme) private var scheme
    @State private var query = ""
    @State private var toDelete: Track?
    var all: [Track] { lib.songs + folders.tracks }
    var shown: [Track] { query.isEmpty ? all : all.filter { ($0.title + $0.artist + $0.album).localizedCaseInsensitiveContains(query) } }
    func canDelete(_ t: Track) -> Bool { t.item == nil && t.url?.isFileURL == true }

    var body: some View {
        let pal = Palette.make(theme, scheme)
        NavigationStack {
            Screen(pal: pal) {
                VStack(spacing: 10) {
                    TopBar(pal: pal) { EmptyView() }
                    SearchField(pal: pal, prompt: "Search your music…", text: $query)
                    if lib.status != .authorized && folders.tracks.isEmpty {
                        Spacer()
                        ContentUnavailableView { Label("Music access needed", systemImage: "lock") } actions: {
                            Button("Open Settings") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                        }
                        Spacer()
                    } else {
                        List(Array(shown.enumerated()), id: \.element.id) { i, t in
                            Button { player.start(shown, at: i) } label: {
                                HStack(spacing: 14) {
                                    ArtView(track: t).frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 10))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(t.title).font(.system(size: 16, weight: .medium)).lineLimit(1).foregroundStyle(player.current?.id == t.id ? pal.accent : pal.text)
                                        Text(t.artist).font(.system(size: 13)).lineLimit(1).foregroundStyle(pal.sub)
                                    }
                                }
                            }
                            .listRowBackground(Color.clear).listRowSeparatorTint(pal.sub.opacity(0.2))
                            .swipeActions { if canDelete(t) { Button("Delete", role: .destructive) { toDelete = t } } }
                            .contextMenu { if canDelete(t) { Button("Delete file", role: .destructive) { toDelete = t } } }
                        }.listStyle(.plain).scrollContentBackground(.hidden)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .confirmationDialog("Delete this file from your device?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible) {
                Button("Delete", role: .destructive) { if let t = toDelete { folders.delete(t) }; toDelete = nil }
            }
        }
        .miniPlayerInset()
    }
}

// MARK: - Videos tab
struct VideosView: View {
    @EnvironmentObject var vids: VideoLibrary
    @EnvironmentObject var player: PlaybackManager
    @AppStorage("theme") private var theme = 0
    @Environment(\.colorScheme) private var scheme
    @State private var playing: VideoItem?
    var body: some View {
        let pal = Palette.make(theme, scheme)
        NavigationStack {
            Screen(pal: pal) {
                VStack(spacing: 10) {
                    TopBar(pal: pal) { EmptyView() }
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                            ForEach(vids.videos) { v in
                                Button { playing = v } label: {
                                    Thumb(asset: v.asset).frame(height: 100).clipShape(RoundedRectangle(cornerRadius: 14))
                                        .overlay(alignment: .bottomTrailing) { Text(fmt(v.duration)).font(.caption2).foregroundStyle(.white).padding(4).background(.black.opacity(0.6), in: Capsule()).padding(6) }
                                }
                                .contextMenu {
                                    Button("Delete video", role: .destructive) {
                                        Task { try? await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.deleteAssets([v.asset] as NSArray) }; vids.load() }
                                    }
                                }
                            }
                        }.padding(.horizontal, 20).padding(.top, 6)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(item: $playing) { v in
                ZStack(alignment: .topLeading) {
                    Color.black.ignoresSafeArea()
                    VideoPlayerScreen(asset: v.asset)
                    Button { playing = nil } label: { Image(systemName: "xmark.circle.fill").font(.largeTitle).padding() }.tint(.white)
                }.onAppear { player.pause() }
            }
        }
        .miniPlayerInset()
    }
}

// MARK: - Mini player
struct ProgressLine: View {
    @ObservedObject var clock: PlayClock; let pal: Palette
    var body: some View {
        GeometryReader { g in
            let f = clock.duration > 0 ? min(max(clock.position / clock.duration, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(pal.sub.opacity(0.25))
                Capsule().fill(pal.gradient).frame(width: g.size.width * CGFloat(f))
            }
        }.frame(height: 3).padding(.horizontal, 14).padding(.bottom, 8)
    }
}

struct MiniPlayer: View {
    @EnvironmentObject var p: PlaybackManager
    @EnvironmentObject var ui: UIState
    @EnvironmentObject var favs: FavoritesStore
    @AppStorage("theme") private var theme = 0
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let pal = Palette.make(theme, scheme)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 12) {
                    ArtView(track: p.current).frame(width: 46, height: 46).clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.current?.title ?? "").font(.system(size: 16, weight: .semibold)).lineLimit(1)
                        Text(p.streamError ?? p.current?.artist ?? "").font(.system(size: 12)).foregroundStyle(pal.sub).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle()).onTapGesture { ui.showPlayer = true }
                if let t = p.current, t.ytID != nil {
                    let liked = favs.contains(t)
                    Button { favs.toggle(t) } label: {
                        Image(systemName: liked ? "heart.fill" : "heart").foregroundStyle(liked ? pal.accent : pal.text).frame(width: 30, height: 40)
                    }.sensoryFeedback(.selection, trigger: liked)
                }
                Button { p.previous() } label: { Image(systemName: "backward.fill").frame(width: 28, height: 40) }
                Button { p.toggle() } label: {
                    Group { if p.isResolving { ProgressView().tint(pal.accent) } else { Image(systemName: p.isPlaying ? "pause.fill" : "play.fill") } }
                        .frame(width: 40, height: 40).overlay(Circle().stroke(pal.accent, lineWidth: 2))
                }
                Button { p.next() } label: { Image(systemName: "forward.fill").frame(width: 28, height: 40) }
            }.padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 8)
            ProgressLine(clock: p.clock, pal: pal)
        }
        .foregroundStyle(pal.text)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(pal.accent.opacity(0.6), lineWidth: 1))
        .padding(.horizontal, 8)
        .contextMenu { Button("Close player", systemImage: "xmark", role: .destructive) { p.stop() } }
    }
}

// MARK: - Full player
struct VinylView: View {
    let track: Track?; let spinning: Bool
    @State private var angle = 0.0
    private let timer = Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect()
    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            ZStack {
                Circle().fill(.black)
                ForEach(1..<8) { i in Circle().stroke(.white.opacity(0.07), lineWidth: 1).frame(width: s * (1 - CGFloat(i) * 0.07)) }
                ArtView(track: track).frame(width: s * 0.4, height: s * 0.4).clipShape(Circle())
                Circle().fill(.black).frame(width: s * 0.04)
            }.frame(width: s, height: s).rotationEffect(.degrees(angle)).shadow(radius: 14, y: 8)
        }.aspectRatio(1, contentMode: .fit)
        .onReceive(timer) { _ in if spinning { angle = (angle + 1.2).truncatingRemainder(dividingBy: 360) } }
    }
}

struct FullPlayer: View {
    @EnvironmentObject var p: PlaybackManager
    @EnvironmentObject var favs: FavoritesStore
    @EnvironmentObject var dl: DownloadManager
    var body: some View {
        ZStack {
            Color(red: 0.88, green: 0.87, blue: 0.85).ignoresSafeArea()
            VStack(spacing: 14) {
                HStack {
                    Spacer()
                    Menu {
                        ForEach([5, 10, 15, 30, 45, 60], id: \.self) { m in Button("Sleep in \(m) min") { p.startSleep(minutes: m) } }
                        Button("Cancel timer", role: .destructive) { p.cancelSleep() }
                    } label: { Image(systemName: p.sleepEnd == nil ? "moon.zzz" : "moon.zzz.fill").font(.title3) }
                }
                VinylView(track: p.current, spinning: p.isPlaying).padding(.horizontal, 8)
                VStack(spacing: 4) {
                    Text(p.current?.title ?? "").font(.system(size: 28, weight: .bold, design: .serif)).multilineTextAlignment(.center).lineLimit(2)
                    Text(p.streamError ?? p.current?.artist ?? "").font(.subheadline)
                }
                if let t = p.current, let yt = t.ytID {
                    HStack(spacing: 34) {
                        Button { favs.toggle(t) } label: { Image(systemName: favs.contains(t) ? "heart.fill" : "heart").font(.title3) }
                        if dl.isDownloaded(yt) { Image(systemName: "checkmark.circle.fill").font(.title3) }
                        else if let pr = dl.progress[yt] { ProgressView(value: pr).frame(width: 60).tint(.black) }
                        else { Button { dl.download(t) } label: { Image(systemName: "arrow.down.circle").font(.title3) } }
                    }
                }
                ScrubBar(clock: p.clock, tint: .black, rail: .black.opacity(0.15), label: .black.opacity(0.7))
                HStack(spacing: 20) {
                    Button { p.previous() } label: { Image(systemName: "backward.fill").frame(width: 90, height: 60).background(.black.opacity(0.1), in: Capsule()) }
                    Button { p.toggle() } label: {
                        Group { if p.isResolving { ProgressView().tint(.white) } else { Image(systemName: p.isPlaying ? "pause.fill" : "play.fill").font(.title) } }
                            .foregroundStyle(.white).frame(width: 84, height: 84).background(.black, in: Circle())
                    }
                    Button { p.next() } label: { Image(systemName: "forward.fill").frame(width: 90, height: 60).background(.black.opacity(0.1), in: Capsule()) }
                }
                HStack(spacing: 40) {
                    Button { p.shuffle.toggle() } label: { Image(systemName: "shuffle").opacity(p.shuffle ? 1 : 0.35) }
                    Button { p.cycleRepeat() } label: { Image(systemName: p.repeatMode == .one ? "repeat.1" : "repeat").opacity(p.repeatMode == .off ? 0.35 : 1) }
                }
            }.padding(24).foregroundStyle(.black).sensoryFeedback(.impact, trigger: p.isPlaying)
        }.environment(\.colorScheme, .light).presentationDragIndicator(.visible)
    }
}

// MARK: - Settings (always white text, on a dark background in every theme)
struct SettingsView: View {
    @EnvironmentObject var lib: MusicLibrary
    @EnvironmentObject var vids: VideoLibrary
    @EnvironmentObject var folders: FolderLibrary
    @State private var picking = false
    @AppStorage("theme") private var theme = 0
    var body: some View {
        let pal = Palette.forSettings(theme)
        let row = Color.white.opacity(0.09)
        NavigationStack {
            Screen(pal: pal) {
                VStack(spacing: 0) {
                    TopBar(pal: pal) { EmptyView() }
                    Form {
                        Section { Picker("Theme", selection: $theme) {
                            Text("Dark").tag(2); Text("Light").tag(1); Text("System").tag(0); Text("Neon Purple").tag(3); Text("Neon Blue").tag(4)
                        } }.listRowBackground(row)
                        Section {
                            Button("Add folder…") { picking = true }
                            ForEach(folders.folderNames, id: \.self) { Label($0, systemImage: "folder") }
                            if !folders.folderNames.isEmpty {
                                Button("Rescan folders (\(folders.tracks.count) songs)") { Task { await folders.rescan() } }
                                Button("Remove all folders", role: .destructive) { folders.removeAll() }.foregroundStyle(.white)
                            }
                            if folders.scanning { ProgressView("Scanning…").tint(.white) }
                        } header: { Text("Folders (Files app)").foregroundStyle(.white) }.listRowBackground(row)
                        Section {
                            Button("Rescan music (\(lib.songs.count) songs)") { lib.load() }
                            Button("Rescan videos (\(vids.videos.count))") { vids.load() }
                            Button("Open iOS Settings") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                        } header: { Text("Library").foregroundStyle(.white) }.listRowBackground(row)
                    }.scrollContentBackground(.hidden)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { r in
                if case .success(let u) = r { Task { await folders.add(u) } }
            }
        }
        .foregroundStyle(.white).tint(.white)
        .environment(\.colorScheme, .dark)
        .miniPlayerInset()
    }
}
