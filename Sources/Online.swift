import SwiftUI

// MARK: - Theme palette (0 System, 1 Light, 2 Dark, 3 Neon Purple, 4 Neon Blue)
struct Palette {
    let bgTop, bgBottom, accent, accent2, text, sub, surface, tile: Color
    let filledPlay: Bool, showMore: Bool, glow: Bool

    var gradient: LinearGradient { LinearGradient(colors: [accent, accent2], startPoint: .leading, endPoint: .trailing) }
    var background: LinearGradient { LinearGradient(colors: [bgTop, bgBottom], startPoint: .top, endPoint: .bottom) }

    static let purple = Palette(bgTop: Color(red: 0.16, green: 0.03, blue: 0.30), bgBottom: Color(red: 0.02, green: 0.0, blue: 0.06),
        accent: Color(red: 0.66, green: 0.30, blue: 1.0), accent2: Color(red: 0.42, green: 0.36, blue: 1.0),
        text: .white, sub: Color.white.opacity(0.55), surface: Color(red: 0.55, green: 0.25, blue: 1.0).opacity(0.14),
        tile: Color(red: 0.10, green: 0.10, blue: 0.25), filledPlay: true, showMore: true, glow: true)
    static let blue = Palette(bgTop: Color(red: 0.0, green: 0.10, blue: 0.20), bgBottom: Color(red: 0.0, green: 0.02, blue: 0.06),
        accent: Color(red: 0.10, green: 0.82, blue: 0.95), accent2: Color(red: 0.32, green: 0.40, blue: 1.0),
        text: .white, sub: Color.white.opacity(0.55), surface: Color.white.opacity(0.07),
        tile: Color(red: 0.05, green: 0.22, blue: 0.28), filledPlay: false, showMore: false, glow: true)
    static let dark = Palette(bgTop: Color(red: 0.08, green: 0.08, blue: 0.10), bgBottom: Color(red: 0.0, green: 0.0, blue: 0.0),
        accent: Color(red: 0.25, green: 0.85, blue: 0.90), accent2: Color(red: 0.38, green: 0.55, blue: 1.0),
        text: .white, sub: Color.white.opacity(0.55), surface: Color.white.opacity(0.07),
        tile: Color(red: 0.09, green: 0.19, blue: 0.24), filledPlay: false, showMore: false, glow: false)
    static let light = Palette(bgTop: Color(red: 0.97, green: 0.98, blue: 1.0), bgBottom: Color(red: 0.90, green: 0.93, blue: 0.97),
        accent: Color(red: 0.0, green: 0.58, blue: 0.70), accent2: Color(red: 0.25, green: 0.40, blue: 0.95),
        text: Color(red: 0.05, green: 0.08, blue: 0.14), sub: Color.black.opacity(0.5), surface: Color.black.opacity(0.06),
        tile: Color(red: 0.09, green: 0.19, blue: 0.24), filledPlay: false, showMore: false, glow: false)

    static func make(_ theme: Int, _ scheme: ColorScheme) -> Palette {
        switch theme {
        case 3: return .purple
        case 4: return .blue
        default: return (theme == 1 || (theme == 0 && scheme == .light)) ? .light : .dark
        }
    }
}

// MARK: - Logo
struct WaveShape: Shape {
    func path(in r: CGRect) -> Path {
        func g(_ x: Double, _ c: Double, _ w: Double) -> Double { exp(-pow((x - c) / w, 2)) }
        var p = Path()
        for i in 0...80 {
            let x = Double(i) / 80
            let y = 0.62 - 0.14 * g(x, 0.28, 0.08) + 0.10 * g(x, 0.42, 0.06) - 0.40 * g(x, 0.64, 0.10)
            let pt = CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        return p
    }
}

struct AuralisMark: View {
    let pal: Palette
    var size: CGFloat = 52
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26).fill(pal.tile)
            RoundedRectangle(cornerRadius: size * 0.26).stroke(.white.opacity(0.1))
            WaveShape().stroke(pal.gradient, style: StrokeStyle(lineWidth: size * 0.07, lineCap: .round, lineJoin: .round))
                .padding(size * 0.2).padding(.bottom, size * 0.06)
            Capsule().fill(pal.accent.opacity(0.6)).frame(width: size * 0.5, height: size * 0.025).offset(y: size * 0.24)
        }.frame(width: size, height: size).shadow(color: pal.glow ? pal.accent.opacity(0.35) : .clear, radius: 10)
    }
}

// MARK: - Models
struct Album: Identifiable, Hashable { let id: String; let name, artist: String; let art: URL? }

struct SavedTrack: Codable {
    let id: UInt64, title: String, artist: String, duration: Double
    let url: String?, art: String?, yt: String?
    init(_ t: Track) { id = t.id; title = t.title; artist = t.artist; duration = t.duration
        url = t.url?.absoluteString; art = t.artworkURL?.absoluteString; yt = t.ytID }
    var track: Track { Track(id: id, title: title, artist: artist, album: "Auralis", duration: duration,
                             url: url.flatMap(URL.init(string:)), item: nil, artworkURL: art.flatMap(URL.init(string:)), ytID: yt) }
}

@MainActor final class RecentStore: ObservableObject {
    @Published private(set) var items: [Track] = []
    private let key = "auralis.recents"
    init() {
        if let d = UserDefaults.standard.data(forKey: key), let s = try? JSONDecoder().decode([SavedTrack].self, from: d) { items = s.map(\.track) }
    }
    func add(_ t: Track) {
        guard t.ytID != nil || t.artworkURL != nil else { return }   // online tracks only
        items.removeAll { $0.id == t.id }; items.insert(t, at: 0); items = Array(items.prefix(20))
        if let d = try? JSONEncoder().encode(items.map(SavedTrack.init)) { UserDefaults.standard.set(d, forKey: key) }
    }
}

func fnv(_ s: String) -> UInt64 {
    var h: UInt64 = 14695981039346656037
    for b in s.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
    return h
}

// MARK: - Audius (fallback only)
enum Audius {
    struct R: Decodable {
        struct T: Decodable {
            struct U: Decodable { let name: String }
            struct A: Decodable { let big: String?; enum CodingKeys: String, CodingKey { case big = "480x480" } }
            let id: String, title: String, duration: Double?, user: U, artwork: A?
        }
        let data: [T]
    }
    static func tracks(_ query: String) async throws -> [Track] {
        var c = URLComponents(string: "https://api.audius.co/v1/tracks/search")!
        c.queryItems = [URLQueryItem(name: "app_name", value: "Auralis"), URLQueryItem(name: "query", value: query)]
        let (data, _) = try await URLSession.shared.data(from: c.url!)
        return try JSONDecoder().decode(R.self, from: data).data.map { t in
            Track(id: fnv(t.id), title: t.title, artist: t.user.name, album: "Auralis", duration: t.duration ?? 0,
                  url: URL(string: "https://api.audius.co/v1/tracks/\(t.id)/stream?app_name=Auralis"), item: nil,
                  artworkURL: t.artwork?.big.flatMap(URL.init(string:)))
        }
    }
}

// MARK: - Online data source (Piped API: JSON only, no web page, no ads)
actor YouTubeSource {
    static let shared = YouTubeSource()
    private var instances = ["https://pipedapi.kavin.rocks", "https://pipedapi.adminforge.de",
                             "https://api.piped.private.coffee", "https://pipedapi.leptons.xyz"]
    private var discovered = false

    struct Item: Decodable {
        let url: String?, title: String?, name: String?, thumbnail: String?, uploaderName: String?
        let duration: Double?, type: String?
    }
    struct Search: Decodable { let items: [Item] }
    struct Playlist: Decodable { let relatedStreams: [Item] }
    struct Streams: Decodable {
        struct A: Decodable { let url: String; let mimeType: String?; let bitrate: Int? }
        let audioStreams: [A]
    }
    struct Inst: Decodable { let api_url: String; let uptime_24h: Double? }

    private func discover() async {
        discovered = true
        guard let u = URL(string: "https://piped-instances.kavin.rocks/"),
              let (d, _) = try? await URLSession.shared.data(from: u),
              let list = try? JSONDecoder().decode([Inst].self, from: d) else { return }
        let top = list.sorted { ($0.uptime_24h ?? 0) > ($1.uptime_24h ?? 0) }.prefix(6).map { $0.api_url }
        instances = Array(NSOrderedSet(array: top + instances)) as? [String] ?? instances
    }

    private func get<T: Decodable>(_ path: String, _ q: [URLQueryItem] = []) async throws -> T {
        if !discovered { await discover() }
        var last: Error = URLError(.cannotConnectToHost)
        for (i, base) in instances.enumerated() {
            guard var c = URLComponents(string: base + path) else { continue }
            if !q.isEmpty { c.queryItems = q }
            guard let url = c.url else { continue }
            do {
                let (d, r) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 8))
                guard (r as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                let v = try JSONDecoder().decode(T.self, from: d)
                if i > 0 { let b = instances.remove(at: i); instances.insert(b, at: 0) }
                return v
            } catch { last = error }
        }
        throw last
    }

    private func queryValue(_ url: String?, _ name: String) -> String? {
        url.flatMap { URLComponents(string: $0)?.queryItems?.first(where: { $0.name == name })?.value }
    }
    private func track(_ i: Item) -> Track? {
        guard let id = queryValue(i.url, "v"), let dur = i.duration, dur > 0 else { return nil }
        let artist = (i.uploaderName ?? "Unknown").replacingOccurrences(of: " - Topic", with: "")
        return Track(id: fnv(id), title: i.title ?? "Unknown", artist: artist, album: "Auralis", duration: dur,
                     url: nil, item: nil, artworkURL: i.thumbnail.flatMap(URL.init(string:)), ytID: id)
    }

    func search(_ query: String) async throws -> [Track] {
        let r: Search = try await get("/search", [URLQueryItem(name: "q", value: query), URLQueryItem(name: "filter", value: "music_songs")])
        let t = r.items.filter { $0.type == "stream" }.compactMap(track)
        if t.isEmpty { throw URLError(.cannotParseResponse) }
        return t
    }

    func albums(_ query: String) async throws -> [Album] {
        let r: Search = try await get("/search", [URLQueryItem(name: "q", value: query), URLQueryItem(name: "filter", value: "music_albums")])
        return r.items.compactMap { i in
            guard let id = queryValue(i.url, "list") else { return nil }
            return Album(id: id, name: i.name ?? i.title ?? "Album",
                         artist: (i.uploaderName ?? "").replacingOccurrences(of: " - Topic", with: ""),
                         art: i.thumbnail.flatMap(URL.init(string:)))
        }
    }

    func albumTracks(_ id: String) async throws -> [Track] {
        let p: Playlist = try await get("/playlists/\(id)")
        return p.relatedStreams.compactMap(track)
    }

    /// AVPlayer can't play WebM/Opus, so pick the best AAC (audio/mp4) stream.
    func streamURL(_ id: String) async throws -> URL {
        let s: Streams = try await get("/streams/\(id)")
        let best = s.audioStreams.filter { ($0.mimeType ?? "").hasPrefix("audio/mp4") }.max { ($0.bitrate ?? 0) < ($1.bitrate ?? 0) }
        guard let u = best.flatMap({ URL(string: $0.url) }) else { throw URLError(.resourceUnavailable) }
        return u
    }
}

@MainActor func playAlbum(_ a: Album, player: PlaybackManager) async {
    if let t = try? await YouTubeSource.shared.albumTracks(a.id), !t.isEmpty { player.start(t, at: 0) }
    else { player.streamError = "Couldn't open this album. Try another one." }
}

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

struct TrackRow: View {
    @EnvironmentObject var player: PlaybackManager
    let t: Track; let pal: Palette; let action: () -> Void
    var body: some View {
        let now = player.current?.id == t.id
        HStack(spacing: 14) {
            ArtView(track: t).frame(width: 62, height: 62).clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(t.title).font(.system(size: 17, weight: .medium)).lineLimit(1).foregroundStyle(now ? pal.accent : pal.text)
                Text(t.artist).font(.system(size: 14)).lineLimit(1).foregroundStyle(pal.sub)
            }
            Spacer(minLength: 4)
            if pal.showMore {
                Menu { Button("Play now", action: action) } label: {
                    Image(systemName: "ellipsis").rotationEffect(.degrees(90)).foregroundStyle(pal.sub).frame(width: 28, height: 40)
                }
            }
            Button(action: action) {
                Image(systemName: now && player.isPlaying ? "waveform" : "play.fill").font(.system(size: 15))
                    .foregroundStyle(pal.filledPlay ? Color.white : pal.text)
                    .frame(width: 44, height: 44)
                    .background(pal.filledPlay ? AnyShapeStyle(pal.gradient) : AnyShapeStyle(pal.surface), in: Circle())
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 20).padding(.vertical, 8).contentShape(Rectangle()).onTapGesture(perform: action)
    }
}

struct AlbumTile: View {
    let a: Album; let pal: Palette; var size: CGFloat = 132
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                pal.surface
                if let u = a.art { AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Color.clear } }
            }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: 16))
            Text(a.name).font(.system(size: 14, weight: .medium)).lineLimit(1).foregroundStyle(pal.text)
            Text(a.artist).font(.system(size: 12)).lineLimit(1).foregroundStyle(pal.sub)
        }.frame(width: size, alignment: .leading)
    }
}

enum OnlineDest: Hashable { case recents, trending, albums }

struct TrackListScreen: View {
    @EnvironmentObject var player: PlaybackManager
    @AppStorage("theme") private var theme = 0
    @Environment(\.colorScheme) private var scheme
    let title: String; let tracks: [Track]
    var body: some View {
        let pal = Palette.make(theme, scheme)
        ZStack {
            pal.background.ignoresSafeArea()
            ScrollView { LazyVStack(spacing: 0) {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { i, t in TrackRow(t: t, pal: pal) { player.start(tracks, at: i) } }
                Color.clear.frame(height: 90)
            } }
        }.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}

struct AlbumGridScreen: View {
    @EnvironmentObject var player: PlaybackManager
    @AppStorage("theme") private var theme = 0
    @Environment(\.colorScheme) private var scheme
    let albums: [Album]
    var body: some View {
        let pal = Palette.make(theme, scheme)
        ZStack {
            pal.background.ignoresSafeArea()
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16)], spacing: 18) {
                    ForEach(albums) { a in
                        Button { Task { await playAlbum(a, player: player) } } label: { AlbumTile(a: a, pal: pal) }.buttonStyle(.plain)
                    }
                }.padding(20)
                Color.clear.frame(height: 90)
            }
        }.navigationTitle("Popular Albums").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Online tab (Home-style layout)
struct OnlineView: View {
    @EnvironmentObject var player: PlaybackManager
    @AppStorage("theme") private var theme = 0
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
    @FocusState private var focused: Bool

    static let playlists: [(String, String, String)] = [
        ("Chill Vibes", "lofi chill songs", "moon.stars.fill"), ("Future Hits", "new hit songs 2026", "sparkles"),
        ("Workout", "workout gym songs", "figure.run"), ("Bollywood", "latest bollywood songs", "music.mic")]

    var pal: Palette { Palette.make(theme, scheme) }

    var body: some View {
        NavigationStack {
            ZStack {
                pal.background.ignoresSafeArea()
                if pal.glow {
                    Circle().fill(pal.accent.opacity(0.22)).frame(width: 420).blur(radius: 90).offset(x: 140, y: -330).allowsHitTesting(false)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        searchBar
                        if let msg = player.streamError ?? notice {
                            Text(msg).font(.footnote).foregroundStyle(pal.sub).padding(.horizontal, 20)
                        }
                        if let q = searchQ { searchResults(q) } else { home }
                        Color.clear.frame(height: 90)
                    }
                }.scrollDismissesKeyboard(.interactively).refreshable { await loadHome() }
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
        .task { await loadHome() }
        .onChange(of: player.current?.id) { _, _ in if let t = player.current { recents.add(t) } }
    }

    // MARK: header + search
    var header: some View {
        HStack(spacing: 14) {
            AuralisMark(pal: pal, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("AURALIS").font(.system(size: 26, weight: .bold)).tracking(2).foregroundStyle(pal.text)
                Text("EVERY SOUND. EVERY MOMENT.").font(.system(size: 9.5, weight: .semibold)).tracking(1.6).foregroundStyle(pal.accent)
            }
            Spacer()
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell").font(.system(size: 22)).foregroundStyle(pal.text)
                Circle().fill(.red).frame(width: 9, height: 9).offset(x: 3, y: -2)
            }
            avatar
        }.padding(.horizontal, 20).padding(.top, 8)
    }

    var avatar: some View {
        Group {
            if let img = UIImage(named: "Avatar") { Image(uiImage: img).resizable().scaledToFill() }
            else { ZStack { pal.gradient; Image(systemName: "person.fill").foregroundStyle(.white) } }
        }.frame(width: 44, height: 44).clipShape(Circle()).overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
    }

    var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 18)).foregroundStyle(pal.text)
            TextField("", text: $query, prompt: Text("Search songs, artists, albums…").foregroundColor(pal.sub))
                .focused($focused).submitLabel(.search).foregroundStyle(pal.text)
                .onSubmit { submitSearch() }
            if !query.isEmpty || searchQ != nil {
                Button { query = ""; searchQ = nil; notice = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(pal.sub) }
            }
            Rectangle().fill(pal.sub.opacity(0.4)).frame(width: 1, height: 26)
            Button { focused = true } label: { Image(systemName: "waveform").font(.system(size: 18, weight: .semibold)).foregroundStyle(pal.accent) }
        }
        .padding(.horizontal, 16).frame(height: 52)
        .background(pal.surface, in: Capsule())
        .overlay(Capsule().stroke(pal.glow ? pal.accent.opacity(0.45) : pal.sub.opacity(0.25), lineWidth: 1))
        .padding(.horizontal, 20)
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
                    if i < min(trending.count, 5) - 1 { Rectangle().fill(pal.sub.opacity(0.18)).frame(height: 0.5).padding(.leading, 96).padding(.trailing, 20) }
                }
            }
        }
        if !albums.isEmpty {
            SectionHeader(title: "Popular Albums", pal: pal, dest: .albums)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
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
            HStack { Spacer(); ArtView(track: t).frame(width: 210, height: 210).clipped()
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
            HStack(spacing: 14) {
                if recents.items.isEmpty {
                    ForEach(Self.playlists, id: \.0) { p in
                        Button { searchQ = p.0; query = p.0; Task { await runSearch(p.1) } } label: {
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

    // MARK: search results
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
        focused = false; searchQ = q
        Task { await runSearch(q) }
    }

    func runSearch(_ q: String) async {
        loading = true; notice = nil; results = []; defer { loading = false }
        do { results = try await YouTubeSource.shared.search(q) }
        catch {
            if let a = try? await Audius.tracks(q), !a.isEmpty { results = a; notice = "Main source is unreachable right now — showing alternate results." }
            else { notice = "Could not load. Check your internet." }
        }
    }

    func loadHome() async {
        loading = true; notice = nil; defer { loading = false }
        async let al = try? YouTubeSource.shared.albums("popular albums")
        do { trending = try await YouTubeSource.shared.search("top songs this week") }
        catch {
            if let a = try? await Audius.tracks("trending"), !a.isEmpty { trending = a; notice = "Main source is unreachable right now — showing alternate results." }
            else { notice = "Could not load. Pull down to retry." }
        }
        if let a = await al, !a.isEmpty { albums = a }
    }
}
