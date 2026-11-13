import SwiftUI
import Photos

func fmt(_ s: Double) -> String { let t = Int(max(0, s)); return String(format: "%d:%02d", t / 60, t % 60) }

struct ArtView: View {
    let track: Track?
    var body: some View {
        if let a = track?.artwork { Image(uiImage: a).resizable().scaledToFill() }
        else if let u = track?.artworkURL { AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Color.gray.opacity(0.3) } }
        else { Color.gray.opacity(0.3) }
    }
}

struct SongsView: View {
    @EnvironmentObject var lib: MusicLibrary
    @EnvironmentObject var folders: FolderLibrary
    @EnvironmentObject var player: PlaybackManager
    @State private var query = ""
    @State private var toDelete: Track?
    var all: [Track] { lib.songs + folders.tracks }
    var shown: [Track] { query.isEmpty ? all : all.filter { ($0.title + $0.artist + $0.album).localizedCaseInsensitiveContains(query) } }
    func canDelete(_ t: Track) -> Bool { t.item == nil && t.url?.isFileURL == true }
    var body: some View {
        NavigationStack {
            Group {
                if lib.status != .authorized && folders.tracks.isEmpty {
                    ContentUnavailableView { Label("Music access needed", systemImage: "lock") } actions: {
                        Button("Open Settings") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                    }
                } else {
                    List(Array(shown.enumerated()), id: \.element.id) { i, t in
                        Button { player.start(shown, at: i) } label: {
                            HStack {
                                ArtView(track: t).frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading) { Text(t.title).lineLimit(1); Text(t.artist).font(.caption).foregroundStyle(.secondary) }
                            }
                        }.foregroundStyle(.primary)
                        .swipeActions { if canDelete(t) { Button("Delete", role: .destructive) { toDelete = t } } }
                        .contextMenu { if canDelete(t) { Button("Delete file", role: .destructive) { toDelete = t } } }
                    }.listStyle(.plain)
                }
            }.navigationTitle("Music").searchable(text: $query)
            .confirmationDialog("Delete this file from your device?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible) {
                Button("Delete", role: .destructive) { if let t = toDelete { folders.delete(t) }; toDelete = nil }
            }
        }
    }
}

struct VideosView: View {
    @EnvironmentObject var vids: VideoLibrary
    @EnvironmentObject var player: PlaybackManager
    @State private var playing: VideoItem?
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(vids.videos) { v in
                        Button { playing = v } label: {
                            Thumb(asset: v.asset).frame(height: 100).clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(alignment: .bottomTrailing) { Text(fmt(v.duration)).font(.caption2).padding(4).background(.black.opacity(0.6), in: Capsule()).padding(6) }
                        }
                        .contextMenu {
                            Button("Delete video", role: .destructive) {
                                Task { try? await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.deleteAssets([v.asset] as NSArray) }; vids.load() }
                            }
                        }
                    }
                }.padding()
            }.navigationTitle("Videos")
            .fullScreenCover(item: $playing) { v in
                ZStack(alignment: .topLeading) {
                    Color.black.ignoresSafeArea()
                    VideoPlayerScreen(asset: v.asset)
                    Button { playing = nil } label: { Image(systemName: "xmark.circle.fill").font(.largeTitle).padding() }.tint(.white)
                }.onAppear { player.pause() }
            }
        }
    }
}

struct MiniPlayer: View {
    @EnvironmentObject var p: PlaybackManager
    @AppStorage("theme") private var theme = 0
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let pal = Palette.make(theme, scheme)
        let frac = p.duration > 0 ? min(max(p.position / p.duration, 0), 1) : 0
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ArtView(track: p.current).frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.current?.title ?? "").font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    Text(p.current?.artist ?? "").font(.system(size: 13)).foregroundStyle(pal.sub).lineLimit(1)
                }
                Spacer()
                Button { p.previous() } label: { Image(systemName: "backward.fill") }
                Button { p.toggle() } label: {
                    Group { if p.isResolving { ProgressView().tint(pal.accent) } else { Image(systemName: p.isPlaying ? "pause.fill" : "play.fill") } }
                        .frame(width: 40, height: 40).overlay(Circle().stroke(pal.accent, lineWidth: 2))
                }
                Button { p.next() } label: { Image(systemName: "forward.fill") }
            }.padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 8)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(pal.sub.opacity(0.25))
                    Capsule().fill(pal.gradient).frame(width: g.size.width * CGFloat(frac))
                }
            }.frame(height: 3).padding(.horizontal, 14).padding(.bottom, 8)
        }
        .foregroundStyle(pal.text)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(pal.accent.opacity(0.6), lineWidth: 1))
        .padding(.horizontal, 8)
    }
}

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
        .onReceive(timer) { _ in if spinning { angle += 1.2 } }
    }
}

struct FullPlayer: View {
    @EnvironmentObject var p: PlaybackManager
    @State private var scrub: Double?
    var body: some View {
        ZStack {
            Color(red: 0.88, green: 0.87, blue: 0.85).ignoresSafeArea()
            VStack(spacing: 16) {
                HStack {
                    Spacer()
                    Menu {
                        ForEach([5, 10, 15, 30, 45, 60], id: \.self) { m in Button("Sleep in \(m) min") { p.startSleep(minutes: m) } }
                        Button("Cancel timer", role: .destructive) { p.cancelSleep() }
                    } label: { Image(systemName: p.sleepEnd == nil ? "moon.zzz" : "moon.zzz.fill").font(.title3) }
                }
                VinylView(track: p.current, spinning: p.isPlaying).padding(.horizontal, 8)
                VStack(spacing: 4) {
                    Text(p.current?.title ?? "").font(.system(size: 30, weight: .bold, design: .serif)).multilineTextAlignment(.center).lineLimit(2)
                    Text(p.current?.artist ?? "").font(.subheadline)
                }
                Slider(value: Binding(get: { scrub ?? p.position }, set: { scrub = $0; p.scrubbing = true }), in: 0...max(p.duration, 1)) { editing in
                    if !editing, let s = scrub { p.seek(s); scrub = nil; p.scrubbing = false }
                }.tint(.black)
                HStack {
                    Text(fmt(scrub ?? p.position)); Spacer(); Text("-" + fmt(p.duration - (scrub ?? p.position)))
                }.font(.caption.monospacedDigit())
                HStack(spacing: 20) {
                    Button { p.previous() } label: { Image(systemName: "backward.fill").frame(width: 90, height: 60).background(.black.opacity(0.1), in: Capsule()) }
                    Button { p.toggle() } label: { Image(systemName: p.isPlaying ? "pause.fill" : "play.fill").font(.title).foregroundStyle(.white).frame(width: 84, height: 84).background(.black, in: Circle()) }
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

struct SettingsView: View {
    @EnvironmentObject var lib: MusicLibrary
    @EnvironmentObject var vids: VideoLibrary
    @EnvironmentObject var folders: FolderLibrary
    @State private var picking = false
    @AppStorage("theme") private var theme = 0
    var body: some View {
        NavigationStack {
            Form {
                Picker("Theme", selection: $theme) { Text("Dark").tag(2); Text("Light").tag(1); Text("System").tag(0); Text("Neon Purple").tag(3); Text("Neon Blue").tag(4) }
                Section("Folders (Files app)") {
                    Button("Add folder…") { picking = true }
                    ForEach(folders.folderNames, id: \.self) { Label($0, systemImage: "folder") }
                    if !folders.folderNames.isEmpty {
                        Button("Rescan folders (\(folders.tracks.count) songs)") { Task { await folders.rescan() } }
                        Button("Remove all folders", role: .destructive) { folders.removeAll() }
                    }
                    if folders.scanning { ProgressView("Scanning…") }
                }
                Section("Library") {
                    Button("Rescan music (\(lib.songs.count) songs)") { lib.load() }
                    Button("Rescan videos (\(vids.videos.count))") { vids.load() }
                    Button("Open iOS Settings") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                }
            }.navigationTitle("Settings")
            .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { r in
                if case .success(let u) = r { Task { await folders.add(u) } }
            }
        }
    }
}
