import SwiftUI

func fmt(_ s: Double) -> String { let t = Int(max(0, s)); return String(format: "%d:%02d", t / 60, t % 60) }

struct SongsView: View {
    @EnvironmentObject var lib: MusicLibrary
    @EnvironmentObject var folders: FolderLibrary
    @EnvironmentObject var player: PlaybackManager
    @State private var query = ""
    var all: [Track] { lib.songs + folders.tracks }
    var shown: [Track] { query.isEmpty ? all : all.filter { ($0.title + $0.artist + $0.album).localizedCaseInsensitiveContains(query) } }
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
                                Group { if let a = t.artwork { Image(uiImage: a).resizable() } else { Color.gray.opacity(0.3) } }
                                    .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading) { Text(t.title).lineLimit(1); Text(t.artist).font(.caption).foregroundStyle(.secondary) }
                            }
                        }.foregroundStyle(.primary)
                    }.listStyle(.plain)
                }
            }.navigationTitle("Music").searchable(text: $query)
        }
    }
}

struct VideosView: View {
    @EnvironmentObject var vids: VideoLibrary
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(vids.videos) { v in
                        NavigationLink { VideoPlayerScreen(asset: v.asset).ignoresSafeArea() } label: {
                            Thumb(asset: v.asset).frame(height: 100).clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(alignment: .bottomTrailing) { Text(fmt(v.duration)).font(.caption2).padding(4).background(.black.opacity(0.6), in: Capsule()).padding(6) }
                        }
                    }
                }.padding()
            }.navigationTitle("Videos")
        }
    }
}

struct MiniPlayer: View {
    @EnvironmentObject var p: PlaybackManager
    var body: some View {
        HStack {
            if let a = p.current?.artwork { Image(uiImage: a).resizable().frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 6)) }
            VStack(alignment: .leading) { Text(p.current?.title ?? "").lineLimit(1); Text(p.current?.artist ?? "").font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Button { p.toggle() } label: { Image(systemName: p.isPlaying ? "pause.fill" : "play.fill") }
            Button { p.next() } label: { Image(systemName: "forward.fill") }.padding(.leading, 8)
        }.padding(10).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 8)
    }
}

struct FullPlayer: View {
    @EnvironmentObject var p: PlaybackManager
    @State private var scrub: Double?
    var body: some View {
        VStack(spacing: 20) {
            if let a = p.current?.artwork { Image(uiImage: a).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 24)).shadow(radius: 20).scaleEffect(p.isPlaying ? 1 : 0.88).animation(.spring, value: p.isPlaying) }
            else { RoundedRectangle(cornerRadius: 24).fill(.gray.opacity(0.3)).aspectRatio(1, contentMode: .fit) }
            VStack { Text(p.current?.title ?? "").font(.title2.bold()); Text(p.current?.artist ?? "").foregroundStyle(.secondary) }
            Slider(value: Binding(get: { scrub ?? p.position }, set: { scrub = $0 }), in: 0...max(p.duration, 1)) { editing in
                if !editing, let s = scrub { p.seek(s); scrub = nil }
            }
            HStack { Text(fmt(scrub ?? p.position)); Spacer(); Text("-" + fmt(p.duration - p.position)) }.font(.caption).monospacedDigit()
            HStack(spacing: 32) {
                Button { p.shuffle.toggle() } label: { Image(systemName: "shuffle").foregroundStyle(p.shuffle ? Color.accentColor : .secondary) }
                Button { p.previous() } label: { Image(systemName: "backward.fill").font(.title) }
                Button { p.toggle() } label: { Image(systemName: p.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 64)) }
                Button { p.next() } label: { Image(systemName: "forward.fill").font(.title) }
                Button { p.cycleRepeat() } label: { Image(systemName: p.repeatMode == .one ? "repeat.1" : "repeat").foregroundStyle(p.repeatMode == .off ? .secondary : Color.accentColor) }
            }.sensoryFeedback(.impact, trigger: p.isPlaying)
        }.padding(28).presentationDragIndicator(.visible)
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
                Picker("Theme", selection: $theme) { Text("System").tag(0); Text("Light").tag(1); Text("Dark").tag(2) }
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
                    if lib.skipped > 0 { Text("\(lib.skipped) DRM/cloud-only songs can't be played by third-party apps.").font(.footnote) }
                    Button("Open iOS Settings") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                }
            }.navigationTitle("Settings")
            .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { r in
                if case .success(let u) = r { Task { await folders.add(u) } }
            }
        }
    }
}
