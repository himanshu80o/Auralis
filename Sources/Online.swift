import SwiftUI

/// Free, ad-free online catalog via the public Audius API (independent artists). Not tested offline.
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
        var c = URLComponents(string: query.isEmpty ? "https://api.audius.co/v1/tracks/trending" : "https://api.audius.co/v1/tracks/search")!
        c.queryItems = [URLQueryItem(name: "app_name", value: "Auralis")] + (query.isEmpty ? [] : [URLQueryItem(name: "query", value: query)])
        let (data, _) = try await URLSession.shared.data(from: c.url!)
        return try JSONDecoder().decode(R.self, from: data).data.map { t in
            var h: UInt64 = 14695981039346656037
            for b in t.id.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
            return Track(id: h, title: t.title, artist: t.user.name, album: "Audius", duration: t.duration ?? 0,
                         url: URL(string: "https://api.audius.co/v1/tracks/\(t.id)/stream?app_name=Auralis"), item: nil,
                         artworkURL: t.artwork?.big.flatMap(URL.init(string:)))
        }
    }
}

struct OnlineView: View {
    @EnvironmentObject var player: PlaybackManager
    @State private var query = ""
    @State private var results: [Track] = []
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List(Array(results.enumerated()), id: \.element.id) { i, t in
                Button { player.start(results, at: i) } label: {
                    HStack {
                        ArtView(track: t).frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading) { Text(t.title).lineLimit(1); Text(t.artist).font(.caption).foregroundStyle(.secondary) }
                    }
                }.foregroundStyle(.primary)
            }
            .listStyle(.plain)
            .overlay { if loading { ProgressView() } else if let error { Text(error).foregroundStyle(.secondary).padding() } }
            .navigationTitle("Online").searchable(text: $query)
            .onSubmit(of: .search) { Task { await load() } }
            .task { await load() }
        }
    }
    func load() async {
        loading = true; error = nil; defer { loading = false }
        do { results = try await Audius.tracks(query) } catch { self.error = "Could not load. Check internet." }
    }
}
