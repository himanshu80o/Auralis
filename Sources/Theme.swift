import SwiftUI
import AVFoundation

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
    /// Settings is always dark so its text can always be white.
    static func forSettings(_ theme: Int) -> Palette { theme == 3 ? .purple : theme == 4 ? .blue : .dark }
}

// MARK: - Logo + header shared by every tab
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

/// Logo + AURALIS + tagline (+ optional trailing buttons). Same on Music, Videos, Online, Settings.
struct TopBar<Trailing: View>: View {
    let pal: Palette
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(spacing: 14) {
            AuralisMark(pal: pal, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("AURALIS").font(.system(size: 26, weight: .bold)).tracking(2).foregroundStyle(pal.text)
                Text("EVERY SOUND. EVERY MOMENT.").font(.system(size: 9.5, weight: .semibold)).tracking(1.6)
                    .foregroundStyle(pal.accent).lineLimit(2)
            }
            Spacer(minLength: 0)
            trailing()
        }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 4)
    }
}

struct Screen<Content: View>: View {
    let pal: Palette
    @ViewBuilder var content: () -> Content
    var body: some View {
        ZStack {
            pal.background.ignoresSafeArea()
            if pal.glow { Circle().fill(pal.accent.opacity(0.22)).frame(width: 420).blur(radius: 90).offset(x: 140, y: -330).allowsHitTesting(false) }
            content()
        }
    }
}

struct SearchField: View {
    let pal: Palette; let prompt: String
    @Binding var text: String
    var onSubmit: () -> Void = {}
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 18)).foregroundStyle(pal.text)
            TextField("", text: $text, prompt: Text(prompt).foregroundColor(pal.sub))
                .submitLabel(.search).foregroundStyle(pal.text).onSubmit(onSubmit)
            if !text.isEmpty { Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(pal.sub) } }
        }
        .padding(.horizontal, 16).frame(height: 50)
        .background(pal.surface, in: Capsule())
        .overlay(Capsule().stroke(pal.glow ? pal.accent.opacity(0.45) : pal.sub.opacity(0.25), lineWidth: 1))
        .padding(.horizontal, 20)
    }
}

// MARK: - Mini player sits ABOVE the tab bar (applied inside every tab, so the tab bar never gets covered)
struct MiniInset: ViewModifier {
    @EnvironmentObject var p: PlaybackManager
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if p.current != nil { MiniPlayer().padding(.bottom, 6).transition(.move(edge: .bottom).combined(with: .opacity)) }
        }.animation(.snappy, value: p.current != nil)
    }
}
extension View { func miniPlayerInset() -> some View { modifier(MiniInset()) } }

// MARK: - Artwork (decoded once, cached, loaded off the render path)
enum ArtLoader {
    static let cache: NSCache<NSString, UIImage> = { let c = NSCache<NSString, UIImage>(); c.countLimit = 400; return c }()
    static func key(_ t: Track) -> NSString { "\(t.id)|\(t.artworkURL?.absoluteString ?? "")" as NSString }
    static func cached(_ t: Track) -> UIImage? { cache.object(forKey: key(t)) }

    @MainActor static func image(for t: Track) async -> UIImage? {
        if let c = cached(t) { return c }
        var img: UIImage?
        if let item = t.item { img = item.artwork?.image(at: CGSize(width: 300, height: 300)) }
        else if let d = t.artworkData { img = UIImage(data: d) }
        else if let u = t.artworkURL {
            if u.isFileURL { img = await Task.detached { (try? Data(contentsOf: u)).flatMap(UIImage.init(data:)) }.value }
            else if let (d, _) = try? await URLSession.shared.data(from: u) { img = UIImage(data: d) }
        } else if let u = t.url, u.isFileURL { img = await embedded(u) }
        if let img { cache.setObject(img, forKey: key(t)) }
        return img
    }
    nonisolated static func embedded(_ url: URL) async -> UIImage? {
        let a = AVURLAsset(url: url)
        guard let meta = try? await a.load(.commonMetadata),
              let m = AVMetadataItem.metadataItems(from: meta, filteredByIdentifier: .commonIdentifierArtwork).first,
              let d = try? await m.load(.dataValue) else { return nil }
        return UIImage(data: d)
    }
}

struct ArtView: View {
    let track: Track?
    @State private var img: UIImage?
    init(track: Track?) { self.track = track; _img = State(initialValue: track.flatMap(ArtLoader.cached)) }
    var body: some View {
        Color.gray.opacity(0.25)
            .overlay { if let img { Image(uiImage: img).resizable().scaledToFill() } }
            .clipped()
            .task(id: track?.id) {
                guard let t = track else { img = nil; return }
                if let c = ArtLoader.cached(t) { img = c; return }
                img = await ArtLoader.image(for: t)
            }
    }
}

// MARK: - Seek bar: tap anywhere to jump, drag to scrub, no jumping back on release
struct ScrubBar: View {
    @EnvironmentObject var p: PlaybackManager
    @ObservedObject var clock: PlayClock
    var tint: Color, rail: Color, label: Color
    @State private var drag: Double?

    var body: some View {
        let dur = max(clock.duration, 1)
        let frac = drag ?? min(max(clock.position / dur, 0), 1)
        VStack(spacing: 4) {
            GeometryReader { g in
                let w = max(g.size.width, 1)
                let r: CGFloat = drag == nil ? 7 : 11
                ZStack(alignment: .leading) {
                    Capsule().fill(rail).frame(height: 5)
                    Capsule().fill(tint).frame(width: w * frac, height: 5)
                    Circle().fill(tint).frame(width: r * 2, height: r * 2).offset(x: w * frac - r)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in drag = min(max(v.location.x / w, 0), 1) }
                    .onEnded { v in
                        let f = min(max(v.location.x / w, 0), 1)
                        if clock.duration > 0 { p.seek(f * clock.duration) }
                        drag = nil
                    })
            }
            .frame(height: 32)
            .animation(drag == nil ? .linear(duration: 0.5) : nil, value: frac)
            HStack {
                Text(fmt(frac * dur)); Spacer(); Text("-" + fmt(dur - frac * dur))
            }.font(.caption.monospacedDigit()).foregroundStyle(label)
        }
    }
}
