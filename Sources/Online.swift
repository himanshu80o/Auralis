import SwiftUI

enum OnlineDest: Hashable { case recents, trending, albums }

// MARK: - Reusable pieces
struct SectionHeader: View {
    let title: String; let pal: Palette; let dest: OnlineDest?
    var body: some View {
        HStack(spacing: 10) {
            Capsule().fill(pal.gradient).frame(width: 4, height: 22)
            Text(title).font(.system(size: 22, weight: .bold)).foregroundStyle(pal.text)
            Spacer()
            if let dest {
                NavigationLink(value: dest) {
                    HStack(spacing: 4) { Text("See All"); Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)) }
                        .font(.system(size: 15, weight: .medium)).foregroundStyle(pal.accent)
                }
            }
        }.padding(.horizontal, 20)
    }
}

struct DownloadButton: View {
    @EnvironmentObject var dl: DownloadManager
    let t: Track; let yt: String; let pal: Palette
    var body: some View {
        if dl.isDownloaded(yt) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(pal.accent).frame(width: 34, height: 44)
        } else if let p = dl.progress[yt] {
            ZStack {
                Circle().stroke(pal.sub.opacity(0.3), lineWidth: 2.5)
                Circle().trim(from: 0, to: max(p, 0.05)).stroke(pal.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).rotationEffect(.degrees(-90))
            }.frame(width: 22, height: 22).frame(width: 34, height: 44)
        } else {
            Button { dl.download(t) } label: {
                Image(systemName: "arrow.down.circle").font(.system(size: 22)).foregroundStyle(pal.sub).frame(width: 34, height: 44)
            }.buttonStyle(.plain)
        }
    }
}

struct TrackRow: View {
    @EnvironmentObject var player: PlaybackManager
    @EnvironmentObject var favs: FavoritesStore
    @EnvironmentObject var dl: DownloadManager
    let t: Track; let pal: Palette; let action: () -> Void
    var body: some View {
        let now = player.current?.id == t.id
        HStack(spacing: 12) {
            ArtView(track: t).frame(width: 62, height: 62).clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(t.title).font(.system(size: 17, weight: .medium)).lineLimit(1).foregroundStyle(now ? pal.accent : pal.text)
                Text(t.artist).font(.system(size: 14)).lineLimit(1).foregroundStyle(pal.sub)
            }
            Spacer(minLength: 4)
            if let yt = t.ytID { DownloadButton(t: t, yt: yt, pal: pal) }
            Button(action: action) {
                Image(systemName: now && player.isPlaying ? "waveform" : "play.fill").font(.system(size: 15))
                    .foregroundStyle(pal.filledPlay ? Color.white : pal.text)
                    .frame(width: 44, height: 44)
                    .background(pal.filledPlay ? AnyShapeStyle(pal.gradient) : AnyShapeStyle(pal.surface), in: Circle())
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 20).padding(.vertical, 8).contentShape(Rectangle()).onTapGesture(perform: action)
        .contextMenu {
            Button("Play", systemImage: "play.fill", action: action)
            if t.ytID != nil {
                Button(favs.contains(t) ? "Remove from Favourites" : "Add to Favourites", systemImage: favs.contains(t) ? "heart.slash" : "heart") { favs.toggle(t) }
                if !dl.isDownloaded(t.ytID!) { Button("Download", systemImage: "arrow.down.circle") { dl.download(t) } }
            }
        }
    }
}

struct AlbumTile: View {
    let a: Album; let pal: Palette; var size: CGFloat = 132
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtView(track: Track(id: fnv(a.id), title: a.name, artist: a.artist, album: "", duration: 0, url: nil, item: nil, artworkURL: a.art))
                .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: 16))
            Text(a.name).font(.system(size: 14, weight: .medium)).lineLimit(1).foregroundStyle(pal.text)
            Text(a.artist).font(.system(size: 12)).lineLimit(1).foregroundStyle(pal.sub)
        }.frame(width: size, alignment: .leading)
    }
}

@MainActor func playAlbum(_ a: Album, player: PlaybackManager) async {
    let t = await Catalog.albumTracks(a.id)
    if t.isEmpty { player.streamError = "Couldn't open this album. Try another one." } else { player.start(t, at: 0) }
}

// MARK: - Secondary screens
struct TrackListScreen: View {
    @EnvironmentObject var player: PlaybackManager
    @EnvironmentObject var dl: DownloadManager
    @AppStorage("theme") private var theme = 0
    @Environment(\.colorScheme) private var scheme
    let title: String; let tracks: [Track]
    var body: some View {
        let pal = Palette.make(theme, scheme)
        Screen(pal: pal) {
            if tracks.isEmpty {
                Text("Nothing here yet").foregroundStyle(pal.sub)
            } else {
                ScrollView { LazyVStack(spacing: 0) {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { i, t in TrackRow(t: t, pal: pal) { player.start(tracks, at: i) } }
                } }
            }
        }
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .toolbar { if tracks.contains(where: { $0.ytID != nil }) { ToolbarItem(placement: .topBarTrailing) {
            Button { dl.downloadAll(tracks) } label: { Image(systemName: "arrow.down.circle") } } } }
        .miniPlayerInset()
    }
}

struct AlbumGridScreen: View {
    @EnvironmentObject var player: PlaybackManager
    @AppStorage("theme") private var theme = 0
    @Environment(\.colorScheme) private var scheme
    let albums: [Album]
    var body: some View {
        let pal = Palette.make(theme, scheme)
        Screen(pal: pal) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16)], spacing: 18) {
                    ForEach(albums) { a in
                        Button { Task { await playAlbum(a, player: player) } } label: { AlbumTile(a: a, pal: pal) }.buttonStyle(.plain)
                    }
                }.padding(20)
            }
        }.navigationTitle("Popular Albums").navigationBarTitleDisplayMode(.inline).miniPlayerInset()
    }
}

struct DownloadsScreen: View {
    @EnvironmentObject var player: PlaybackManager
    @EnvironmentObject var dl: DownloadManager
    @AppStorage("theme") private var theme = 0
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let pal = Palette.make(theme, scheme)
        let tracks = dl.tracks
        Screen(pal: pal) {
            if tracks.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle").font(.system(size: 44)).foregroundStyle(pal.accent)
                    Text("No downloads yet").font(.headline).foregroundStyle(pal.text)
                    Text("Tap the download icon next to any song.").font(.footnote).foregroundStyle(pal.sub)
                }
            } else {
                List {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { i, t in
                        Button { player.start(tracks, at: i) } label: {
                            HStack(spacing: 14) {
                                ArtView(track: t).frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(t.title).font(.system(size: 16, weight: .medium)).lineLimit(1).foregroundStyle(player.current?.id == t.id ? pal.accent : pal.text)
                                    Text(t.artist).font(.system(size: 13)).lineLimit(1).foregroundStyle(pal.sub)
                                }
                            }
                        }.listRowBackground(Color.clear)
                        .swipeActions { Button("Delete", role: .destructive) { if let it = dl.items.first(where: { $0.yt == t.ytID }) { dl.delete(it) } } }
                    }
                }.listStyle(.plain).scrollContentBackground(.hidden)
            }
        }.navigationTitle("My Downloads").navigationBarTitleDisplayMode(.inline).miniPlayerInset()
    }
}

// MARK: - Region picker / setup / profile
struct RegionList: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var q = ""
    var body: some View {
        List(Regions.all.filter { q.isEmpty || $0.name.localizedCaseInsensitiveContains(q) }, id: \.code) { r in
            Button { selection = r.code; dismiss() } label: {
                HStack { Text(Regions.flag(r.code)); Text(r.name); Spacer(); if r.code == selection { Image(systemName: "checkmark") } }
            }
        }.searchable(text: $q).navigationTitle("Region").navigationBarTitleDisplayMode(.inline)
    }
}

struct SetupView: View {
    @AppStorage("username") private var username = ""
    @AppStorage("region") private var region = Regions.defaultCode
    @AppStorage("setupDone") private var done = false
    var body: some View {
        let pal = Palette.dark
        NavigationStack {
            Screen(pal: pal) {
                VStack(spacing: 18) {
                    Spacer()
                    AuralisMark(pal: pal, size: 84)
                    Text("Set up your profile").font(.title2.bold())
                    Text("Your region is used to recommend trending music.").font(.footnote).foregroundStyle(pal.sub)
                    TextField("", text: $username, prompt: Text("Username").foregroundColor(pal.sub))
                        .padding(14).background(pal.surface, in: RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 24)
                    NavigationLink { RegionList(selection: $region) } label: {
                        HStack { Text("Region"); Spacer(); Text("\(Regions.flag(region)) \(Regions.name(region))"); Image(systemName: "chevron.right").font(.caption) }
                            .padding(14).background(pal.surface, in: RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 24)
                    }
                    Button { done = true } label: {
                        Text("Continue").font(.system(size: 17, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(pal.gradient, in: Capsule()).foregroundStyle(.black).padding(.horizontal, 24)
                    }.disabled(username.trimmingCharacters(in: .whitespaces).isEmpty).opacity(username.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                    Spacer()
                }
            }.toolbar(.hidden, for: .navigationBar)
        }.foregroundStyle(.white).environment(\.colorScheme, .dark).preferredColorScheme(.dark)
    }
}

struct ProfileSheet: View {
    @EnvironmentObject var dl: DownloadManager
    @EnvironmentObject var favs: FavoritesStore
    @AppStorage("username") private var username = ""
    @AppStorage("region") private var region = Regions.defaultCode
    @AppStorage("theme") private var theme = 0
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        let pal = Palette.make(theme, scheme)
        NavigationStack {
            Screen(pal: pal) {
                Form {
                    Section {
                        HStack(spacing: 14) {
                            ZStack { pal.gradient; Text(String(username.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()).font(.title2.bold()).foregroundStyle(.white) }
                                .frame(width: 56, height: 56).clipShape(Circle())
                            TextField("", text: $username, prompt: Text("Username").foregroundColor(pal.sub)).font(.title3)
                        }
                        NavigationLink { RegionList(selection: $region) } label: {
                            HStack { Text("Region"); Spacer(); Text("\(Regions.flag(region)) \(Regions.name(region))").foregroundStyle(pal.sub) }
                        }
                    }.listRowBackground(pal.surface)
                    Section {
                        NavigationLink { DownloadsScreen() } label: { Label("My Downloads (\(dl.items.count))", systemImage: "arrow.down.circle.fill") }
                        NavigationLink { TrackListScreen(title: "Favourites", tracks: favs.items) } label: { Label("Favourites (\(favs.items.count))", systemImage: "heart.fill") }
                    }.listRowBackground(pal.surface)
                }.scrollContentBackground(.hidden).foregroundStyle(pal.text)
            }
            .navigationTitle("Profile").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }.tint(pal.accent)
    }
}

// MARK: - Online tab
struct OnlineView: View {
    @EnvironmentObject var player: PlaybackManager
    @EnvironmentObject var dl: DownloadManager
    @AppStorage("theme") private var theme = 0
    @AppStorage("region") private var region = Regions.defaultCode
    @AppStorage("username") private var username = ""
    @Environment(\.colorScheme) private var scheme
    @StateObject private var recents = RecentStore()
    @State private var query = ""
    @State private var searchQ: String?
    @State private var results: [Track] = []
    @State private var trending: [Track] = []
    @State private var albums: [Album] = []
    @State private var loading = false
    @State private var notice: String?
    @State private var page = 0
    @State private var showProfile = false

    static let playlists: [(String, String, String)] = [
        ("Chill Vibes", "lofi chill songs", "moon.stars.fill"), ("Future Hits", "new hit songs 2026", "sparkles"),
        ("Workout", "workout gym songs", "figure.run"), ("Party", "party dance songs", "music.mic")]

    var pal: Palette { Palette.make(theme, scheme) }

    var body: some View {
        NavigationStack {
            Screen(pal: pal) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        TopBar(pal: pal) { trailingButtons }
                        SearchField(pal: pal, prompt: "Search songs, artists, albums…", text: $query) { submitSearch() }
                            .onChange(of: query) { _, v in if v.isEmpty { searchQ = nil } }
                        if let msg = player.streamError ?? dl.lastError ?? notice {
                            Text(msg).font(.footnote).foregroundStyle(pal.sub).padding(.horizontal, 20)
                        }
                        if let q = searchQ { searchResults(q) } else { home }
                    }.padding(.bottom, 12)
                }.scrollDismissesKeyboard(.interactively).refreshable { await loadHome(force: true) }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: OnlineDest.self) { d in
                switch d {
                case .recents: TrackListScreen(title: "Recently Played", tracks: recents.items)
                case .trending: TrackListScreen(title: "Trending Now", tracks: trending)
                case .albums: AlbumGridScreen(albums: albums)
                }
            }
        }
        .miniPlayerInset()
        .sheet(isPresented: $showProfile) { ProfileSheet() }
        .task(id: region) { await loadHome(force: false) }
        .onChange(of: player.current?.id) { _, _ in if let t = player.current { recents.add(t) } }
    }

    var trailingButtons: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell").font(.system(size: 22)).foregroundStyle(pal.text)
                Circle().fill(.red).frame(width: 9, height: 9).offset(x: 3, y: -2)
            }
            Button { showProfile = true } label: {
                ZStack {
                    pal.gradient
                    let ch = String(username.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
                    if ch.isEmpty { Image(systemName: "person.fill").foregroundStyle(.white) } else { Text(ch).font(.headline).foregroundStyle(.white) }
                }.frame(width: 44, height: 44).clipShape(Circle()).overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
            }
        }
    }

    // MARK: home sections
    @ViewBuilder var home: some View {
        hero
        recentSection
        if loading && trending.isEmpty { ProgressView().tint(pal.accent).frame(maxWidth: .infinity).padding(.top, 20) }
        if !trending.isEmpty {
            SectionHeader(title: "Trending Now", pal: pal, dest: .trending)
            VStack(spacing: 0) {
                ForEach(Array(trending.prefix(5).enumerated()), id: \.element.id) { i, t in
                    TrackRow(t: t, pal: pal) { player.start(trending, at: i) }
                    if i < min(trending.count, 5) - 1 { Rectangle().fill(pal.sub.opacity(0.18)).frame(height: 0.5).padding(.leading, 94).padding(.trailing, 20) }
                }
            }
        }
        if !albums.isEmpty {
            SectionHeader(title: "Popular Albums", pal: pal, dest: .albums)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(albums.prefix(10)) { a in
                        Button { Task { await playAlbum(a, player: player) } } label: { AlbumTile(a: a, pal: pal) }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 20)
            }
        }
    }

    var hero: some View {
        let slides = Array(trending.prefix(4))
        let n = max(slides.count, 1)
        return ZStack(alignment: .bottom) {
            TabView(selection: $page) {
                ForEach(0..<n, id: \.self) { i in heroSlide(i < slides.count ? slides[i] : nil, i).tag(i) }
            }.tabViewStyle(.page(indexDisplayMode: .never))
            HStack(spacing: 8) {
                ForEach(0..<n, id: \.self) { i in
                    Capsule().fill(i == page ? AnyShapeStyle(pal.gradient) : AnyShapeStyle(Color.white.opacity(0.35)))
                        .frame(width: i == page ? 24 : 8, height: 8)
                }
            }.padding(.bottom, 12)
        }
        .frame(height: 210).clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(pal.accent.opacity(pal.glow ? 0.7 : 0.3), lineWidth: 1.2))
        .shadow(color: pal.glow ? pal.accent.opacity(0.35) : .clear, radius: 14)
        .padding(.horizontal, 20)
    }

    func heroSlide(_ t: Track?, _ i: Int) -> some View {
        ZStack(alignment: .leading) {
            LinearGradient(colors: [Color.black.opacity(0.85), pal.accent2.opacity(0.55), pal.accent.opacity(0.35)], startPoint: .leading, endPoint: .trailing)
            HStack { Spacer(); ArtView(track: t).frame(width: 220, height: 210)
                .mask(LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: UnitPoint(x: 0.6, y: 0.5))) }
            LinearGradient(colors: [Color.black.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text("Feel the").font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
                Text("Music").font(.system(size: 54, weight: .heavy).italic())
                    .foregroundStyle(LinearGradient(colors: [.white, pal.accent], startPoint: .leading, endPoint: .trailing))
                Text("Stream. Enjoy. Repeat.").font(.system(size: 15)).foregroundStyle(.white.opacity(0.75))
                Button { if !trending.isEmpty { player.start(trending, at: i) } } label: {
                    Label("Play Now", systemImage: "play.fill").font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 20).padding(.vertical, 10).foregroundStyle(.white).background(pal.gradient, in: Capsule())
                }.padding(.top, 8)
            }.padding(.leading, 22).padding(.bottom, 14)
        }
    }

    @ViewBuilder var recentSection: some View {
        SectionHeader(title: "Recently Played", pal: pal, dest: recents.items.isEmpty ? nil : .recents)
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 14) {
                if recents.items.isEmpty {
                    ForEach(Self.playlists, id: \.0) { p in
                        Button { query = p.0; searchQ = p.0; Task { await runSearch(p.1) } } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                ZStack {
                                    LinearGradient(colors: [pal.accent2.opacity(0.9), pal.accent.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    Image(systemName: p.2).font(.system(size: 34)).foregroundStyle(.white.opacity(0.9))
                                }.frame(width: 118, height: 118).clipShape(RoundedRectangle(cornerRadius: 18))
                                Text(p.0).font(.system(size: 15, weight: .medium)).foregroundStyle(pal.text)
                                Text("Playlist").font(.system(size: 13)).foregroundStyle(pal.sub)
                            }
                        }.buttonStyle(.plain)
                    }
                } else {
                    ForEach(Array(recents.items.enumerated()), id: \.element.id) { i, t in
                        Button { player.start(recents.items, at: i) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                ArtView(track: t).frame(width: 118, height: 118).clipShape(RoundedRectangle(cornerRadius: 18))
                                Text(t.title).font(.system(size: 15, weight: .medium)).lineLimit(1).foregroundStyle(pal.text)
                                Text(t.artist).font(.system(size: 13)).lineLimit(1).foregroundStyle(pal.sub)
                            }.frame(width: 118, alignment: .leading)
                        }.buttonStyle(.plain)
                    }
                }
            }.padding(.horizontal, 20)
        }
    }

    @ViewBuilder func searchResults(_ q: String) -> some View {
        SectionHeader(title: "Results", pal: pal, dest: nil)
        if loading && results.isEmpty { ProgressView().tint(pal.accent).frame(maxWidth: .infinity).padding(.top, 40) }
        VStack(spacing: 0) {
            ForEach(Array(results.enumerated()), id: \.element.id) { i, t in TrackRow(t: t, pal: pal) { player.start(results, at: i) } }
        }
    }

    // MARK: loading
    func submitSearch() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searchQ = q
        Task { await runSearch(q) }
    }

    func runSearch(_ q: String) async {
        loading = true; notice = nil; results = []; defer { loading = false }
        if let r = try? await Catalog.search(q) { results = r; return }
        let a = await Catalog.audius(q)
        if a.isEmpty { notice = "Could not load. Check your internet." } else { results = a; notice = "Main source is unreachable right now — showing alternate results." }
    }

    func loadHome(force: Bool) async {
        let key = "auralis.trending." + region
        if trending.isEmpty, let d = UserDefaults.standard.data(forKey: key), let s = try? JSONDecoder().decode([SavedTrack].self, from: d) {
            trending = s.map(\.track)   // show last results instantly, refresh below
        }
        loading = trending.isEmpty; notice = nil; defer { loading = false }
        async let al = Catalog.albums(Regions.albumQuery(region))
        if let t = try? await Catalog.search(Regions.trendingQuery(region)) {
            trending = t
            if let d = try? JSONEncoder().encode(t.map(SavedTrack.init)) { UserDefaults.standard.set(d, forKey: key) }
        } else if trending.isEmpty {
            let a = await Catalog.audius("trending")
            if a.isEmpty { notice = "Could not load. Pull down to retry." } else { trending = a; notice = "Main source is unreachable right now — showing alternate results." }
        }
        let a = await al
        if !a.isEmpty { albums = a }
    }
}
