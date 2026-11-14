import Foundation

// MARK: - Shared models
struct Hit: Sendable { let id, title, artist: String; let duration: Double }
struct Album: Identifiable, Hashable, Sendable { let id: String; let name, artist: String; let art: URL? }
struct StreamInfo: Sendable { let url: URL; let headers: [String: String]; let bitrate: Int; let source: String }
struct Boxed<T: Sendable>: Sendable { let value: T; let base: String }

func fnv(_ s: String) -> UInt64 {
    var h: UInt64 = 14695981039346656037
    for b in s.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
    return h
}

/// Runs all jobs in parallel and returns the first one that succeeds (others are cancelled).
func race<T: Sendable>(_ jobs: [@Sendable () async throws -> T]) async throws -> T {
    try await withThrowingTaskGroup(of: T?.self) { g in
        for j in jobs { g.addTask { try? await j() } }
        while let r = try await g.next() { if let r { g.cancelAll(); return r } }
        throw URLError(.cannotConnectToHost)
    }
}

func dig(_ o: Any?, _ path: [Any]) -> Any? {
    var c = o
    for k in path {
        if let s = k as? String { c = (c as? [String: Any])?[s] }
        else if let i = k as? Int { c = (c as? [Any]).flatMap { $0.indices.contains(i) ? $0[i] : nil } }
        else { return nil }
    }
    return c
}
func parseDuration(_ s: String) -> Double {
    s.split(separator: ":").compactMap { Double($0) }.reduce(0) { $0 * 60 + $1 }
}

// MARK: - YouTube InnerTube (direct data API: JSON only, no web page, no ads)
enum IT {
    struct Client { let name, version, ua, source: String; let id: Int; let extra: [String: Any] }
    static let androidVR = Client(name: "ANDROID_VR", version: "1.60.19",
        ua: "com.google.android.apps.youtube.vr.oculus/1.60.19 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip",
        source: "android_vr", id: 28,
        extra: ["deviceMake": "Oculus", "deviceModel": "Quest 3", "osName": "Android", "osVersion": "12L", "androidSdkVersion": 32])
    static let ios = Client(name: "IOS", version: "20.10.4",
        ua: "com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)",
        source: "ios", id: 5,
        extra: ["deviceMake": "Apple", "deviceModel": "iPhone16,2", "osName": "iPhone", "osVersion": "18.3.2.22D82"])

    static func player(_ id: String, _ c: Client) async throws -> StreamInfo {
        var req = URLRequest(url: URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false")!, timeoutInterval: 6)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(c.ua, forHTTPHeaderField: "User-Agent")
        req.setValue("\(c.id)", forHTTPHeaderField: "X-YouTube-Client-Name")
        req.setValue(c.version, forHTTPHeaderField: "X-YouTube-Client-Version")
        var client: [String: Any] = ["clientName": c.name, "clientVersion": c.version, "hl": "en", "gl": Regions.current]
        c.extra.forEach { client[$0.key] = $0.value }
        let body: [String: Any] = ["context": ["client": client], "videoId": id, "contentCheckOk": true, "racyCheckOk": true]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (d, _) = try await URLSession.shared.data(for: req)
        let j = try JSONSerialization.jsonObject(with: d)
        guard let fm = dig(j, ["streamingData", "adaptiveFormats"]) as? [[String: Any]] else { throw URLError(.resourceUnavailable) }
        // AVPlayer only plays AAC (audio/mp4). Always take the HIGHEST bitrate available.
        let audio = fm.filter { (($0["mimeType"] as? String) ?? "").hasPrefix("audio/mp4") && ($0["url"] as? String) != nil }
        guard let best = audio.max(by: { ($0["bitrate"] as? Int ?? 0) < ($1["bitrate"] as? Int ?? 0) }),
              let u = (best["url"] as? String).flatMap(URL.init(string:)) else { throw URLError(.resourceUnavailable) }
        return StreamInfo(url: u, headers: ["User-Agent": c.ua], bitrate: best["bitrate"] as? Int ?? 0, source: c.source)
    }

    static func search(_ q: String) async throws -> [Hit] {
        var req = URLRequest(url: URL(string: "https://www.youtube.com/youtubei/v1/search?prettyPrint=false")!, timeoutInterval: 6)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["context": ["client": ["clientName": "WEB", "clientVersion": "2.20250310.01.00", "hl": "en", "gl": Regions.current]],
                                   "query": q, "params": "EgIQAQ=="]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (d, _) = try await URLSession.shared.data(for: req)
        let j = try JSONSerialization.jsonObject(with: d)
        let sections = dig(j, ["contents", "twoColumnSearchResultsRenderer", "primaryContents", "sectionListRenderer", "contents"]) as? [Any] ?? []
        var out: [Hit] = []
        for s in sections {
            for it in dig(s, ["itemSectionRenderer", "contents"]) as? [Any] ?? [] {
                guard let id = dig(it, ["videoRenderer", "videoId"]) as? String,
                      let title = dig(it, ["videoRenderer", "title", "runs", 0, "text"]) as? String,
                      let len = dig(it, ["videoRenderer", "lengthText", "simpleText"]) as? String else { continue }
                let artist = (dig(it, ["videoRenderer", "ownerText", "runs", 0, "text"]) as? String ?? "Unknown").replacingOccurrences(of: " - Topic", with: "")
                out.append(Hit(id: id, title: title, artist: artist, duration: parseDuration(len)))
            }
        }
        if out.isEmpty { throw URLError(.cannotParseResponse) }
        return out
    }
}

// MARK: - Piped (public API instances, raced in parallel)
actor Piped {
    static let shared = Piped()
    private var instances = ["https://pipedapi.kavin.rocks", "https://pipedapi.adminforge.de",
                             "https://api.piped.private.coffee", "https://pipedapi.leptons.xyz",
                             "https://pipedapi.nosebs.ru", "https://pipedapi.reallyaweso.me"]
    private var discovered = false

    struct Item: Decodable, Sendable { let url: String?, title: String?, name: String?, thumbnail: String?, uploaderName: String?; let duration: Double?, type: String? }
    struct Search: Decodable, Sendable { let items: [Item] }
    struct Playlist: Decodable, Sendable { let relatedStreams: [Item] }
    struct Streams: Decodable, Sendable { struct A: Decodable, Sendable { let url: String; let mimeType: String?; let bitrate: Int? }; let audioStreams: [A] }
    struct Inst: Decodable, Sendable { let api_url: String; let uptime_24h: Double? }

    private func list() -> [String] {
        if !discovered { discovered = true; Task { await self.discover() } }   // never blocks the first request
        return instances
    }
    private func discover() async {
        guard let u = URL(string: "https://piped-instances.kavin.rocks/"),
              let (d, _) = try? await URLSession.shared.data(from: u),
              let l = try? JSONDecoder().decode([Inst].self, from: d) else { return }
        let top = l.sorted { ($0.uptime_24h ?? 0) > ($1.uptime_24h ?? 0) }.prefix(6).map { $0.api_url }
        instances = Array(NSOrderedSet(array: top + instances)) as? [String] ?? instances
    }
    private func promote(_ base: String) {
        if let i = instances.firstIndex(of: base), i > 0 { instances.remove(at: i); instances.insert(base, at: 0) }
    }
    nonisolated static func fetch<T: Decodable>(_ base: String, _ path: String, _ q: [URLQueryItem]) async throws -> T {
        guard var c = URLComponents(string: base + path) else { throw URLError(.badURL) }
        if !q.isEmpty { c.queryItems = q }
        let (d, r) = try await URLSession.shared.data(for: URLRequest(url: c.url!, timeoutInterval: 6))
        guard (r as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: d)
    }
    private func get<T: Decodable & Sendable>(_ path: String, _ q: [URLQueryItem] = []) async throws -> T {
        let all = list(); var i = 0; var last: Error = URLError(.cannotConnectToHost)
        while i < all.count {   // 3 instances at a time, first answer wins
            let chunk = Array(all[i..<min(i + 3, all.count)])
            let jobs: [@Sendable () async throws -> Boxed<T>] = chunk.map { base in
                { @Sendable in Boxed(value: try await Piped.fetch(base, path, q) as T, base: base) }
            }
            do { let r = try await race(jobs); promote(r.base); return r.value } catch { last = error }
            i += 3
        }
        throw last
    }
    private func vid(_ s: String?) -> String? { s.flatMap { URLComponents(string: $0)?.queryItems?.first { $0.name == "v" }?.value } }

    func search(_ q: String) async throws -> [Hit] {
        let r: Search = try await get("/search", [URLQueryItem(name: "q", value: q), URLQueryItem(name: "filter", value: "music_songs")])
        return r.items.filter { $0.type == "stream" }.compactMap { i in
            guard let id = vid(i.url), let d = i.duration, d > 0 else { return nil }
            return Hit(id: id, title: i.title ?? "Unknown", artist: (i.uploaderName ?? "Unknown").replacingOccurrences(of: " - Topic", with: ""), duration: d)
        }
    }
    func albums(_ q: String) async throws -> [Album] {
        let r: Search = try await get("/search", [URLQueryItem(name: "q", value: q), URLQueryItem(name: "filter", value: "music_albums")])
        return r.items.compactMap { i in
            guard let id = i.url.flatMap({ URLComponents(string: $0)?.queryItems?.first { $0.name == "list" }?.value }) else { return nil }
            return Album(id: id, name: i.name ?? i.title ?? "Album", artist: (i.uploaderName ?? "").replacingOccurrences(of: " - Topic", with: ""), art: i.thumbnail.flatMap(URL.init(string:)))
        }
    }
    func albumTracks(_ id: String) async throws -> [Hit] {
        let p: Playlist = try await get("/playlists/\(id)")
        return p.relatedStreams.compactMap { i in
            guard let v = vid(i.url), let d = i.duration, d > 0 else { return nil }
            return Hit(id: v, title: i.title ?? "Unknown", artist: (i.uploaderName ?? "").replacingOccurrences(of: " - Topic", with: ""), duration: d)
        }
    }
    func stream(_ id: String) async throws -> StreamInfo {
        let s: Streams = try await get("/streams/\(id)")
        let a = s.audioStreams.filter { ($0.mimeType ?? "").hasPrefix("audio/mp4") }.max { ($0.bitrate ?? 0) < ($1.bitrate ?? 0) }
        guard let a, let u = URL(string: a.url) else { throw URLError(.resourceUnavailable) }
        return StreamInfo(url: u, headers: [:], bitrate: a.bitrate ?? 0, source: "piped")
    }
}

// MARK: - Stream resolver: fastest source wins, results cached, bad sources skipped on retry
actor Resolver {
    static let shared = Resolver()
    private var cache: [String: (StreamInfo, Date)] = [:]
    private var bad: [String: Set<String>] = [:]

    func stream(_ id: String, fresh: Bool = false) async throws -> StreamInfo {
        if !fresh, let c = cache[id], Date().timeIntervalSince(c.1) < 4 * 3600 { return c.0 }
        let skip = bad[id] ?? []
        var jobs: [@Sendable () async throws -> StreamInfo] = []
        if !skip.contains("android_vr") { jobs.append { try await IT.player(id, IT.androidVR) } }
        if !skip.contains("ios") { jobs.append { try await IT.player(id, IT.ios) } }
        if !skip.contains("piped") { jobs.append { try await Piped.shared.stream(id) } }
        if jobs.isEmpty { bad[id] = nil; return try await stream(id, fresh: true) }
        let s = try await race(jobs)
        cache[id] = (s, Date()); return s
    }
    func markBad(_ id: String, source: String) { bad[id, default: []].insert(source); cache[id] = nil }
    func prefetch(_ id: String) async { _ = try? await stream(id) }
}

// MARK: - Catalog: search / albums with cache + fallback
@MainActor enum Catalog {
    private static var cache: [String: (Date, [Track])] = [:]

    static func track(_ h: Hit) -> Track {
        Track(id: fnv(h.id), title: h.title, artist: h.artist, album: "Auralis", duration: h.duration,
              url: nil, item: nil, artworkURL: Track.ytThumb(h.id), ytID: h.id)
    }

    static func search(_ q: String) async throws -> [Track] {
        let key = q + "|" + Regions.current
        if let c = cache[key], Date().timeIntervalSince(c.0) < 600 { return c.1 }
        let jobs: [@Sendable () async throws -> [Hit]] = [{ try await IT.search(q) }, { try await Piped.shared.search(q) }]
        var hits = (try? await race(jobs)) ?? []
        hits = hits.filter { $0.duration >= 30 && $0.duration <= 900 }   // skip mixes / podcasts
        var seen = Set<String>(); hits = hits.filter { seen.insert($0.id).inserted }
        if hits.isEmpty { throw URLError(.cannotParseResponse) }
        let t = hits.map(track); cache[key] = (Date(), t); return t
    }
    static func albums(_ q: String) async -> [Album] { (try? await Piped.shared.albums(q)) ?? [] }
    static func albumTracks(_ id: String) async -> [Track] { ((try? await Piped.shared.albumTracks(id)) ?? []).map(track) }

    // Fallback when YouTube sources are unreachable
    struct AR: Decodable {
        struct T: Decodable {
            struct U: Decodable { let name: String }
            struct A: Decodable { let big: String?; enum CodingKeys: String, CodingKey { case big = "480x480" } }
            let id: String, title: String, duration: Double?, user: U, artwork: A?
        }
        let data: [T]
    }
    static func audius(_ q: String) async -> [Track] {
        var c = URLComponents(string: "https://api.audius.co/v1/tracks/search")!
        c.queryItems = [URLQueryItem(name: "app_name", value: "Auralis"), URLQueryItem(name: "query", value: q)]
        guard let (d, _) = try? await URLSession.shared.data(from: c.url!), let r = try? JSONDecoder().decode(AR.self, from: d) else { return [] }
        return r.data.map { t in Track(id: fnv(t.id), title: t.title, artist: t.user.name, album: "Auralis", duration: t.duration ?? 0,
            url: URL(string: "https://api.audius.co/v1/tracks/\(t.id)/stream?app_name=Auralis"), item: nil, artworkURL: t.artwork?.big.flatMap(URL.init(string:))) }
    }
}
