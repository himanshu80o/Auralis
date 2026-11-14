import SwiftUI
import WebKit
import CryptoKit

/// "Continue with Google": signs in on Google's own page (inside a web view). Auralis never sees the password;
/// it only keeps the session cookies that the web view stores on this phone and sends them to YouTube like a browser would.
@MainActor final class YTAuth: ObservableObject {
    static let shared = YTAuth()
    @Published private(set) var signedIn = false
    private var cookieHeader = ""
    private var sapisid = ""

    init() { Task { await refresh() } }

    func refresh() async {
        let all = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        let mine = all.filter { $0.domain.hasSuffix("youtube.com") || $0.domain.hasSuffix("google.com") }
        let sp = mine.first { $0.name == "SAPISID" }?.value ?? mine.first { $0.name == "__Secure-3PAPISID" }?.value ?? ""
        cookieHeader = mine.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        sapisid = sp
        let now = !sp.isEmpty
        let changed = now != signedIn
        signedIn = now
        if changed { await Resolver.shared.reset() }   // old (bot-blocked) answers must not be reused
    }

    func signOut() async {
        let store = WKWebsiteDataStore.default()
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        await refresh()
    }

    /// Cookie + SAPISIDHASH headers, exactly what a logged-in browser sends.
    func requestHeaders() -> [String: String] {
        guard signedIn else { return [:] }
        let ts = Int(Date().timeIntervalSince1970), origin = "https://www.youtube.com"
        let hash = Insecure.SHA1.hash(data: Data("\(ts) \(sapisid) \(origin)".utf8)).map { String(format: "%02x", $0) }.joined()
        return ["Cookie": cookieHeader, "Authorization": "SAPISIDHASH \(ts)_\(hash)", "X-Origin": origin, "Origin": origin, "X-Goog-AuthUser": "0"]
    }
}

struct GoogleLoginWebView: UIViewRepresentable {
    let onSignedIn: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onSignedIn) }
    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration(); cfg.websiteDataStore = .default()
        let w = WKWebView(frame: .zero, configuration: cfg)
        // Google refuses sign-in inside "embedded" browsers, so present as mobile Safari.
        w.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Mobile/15E148 Safari/604.1"
        w.navigationDelegate = context.coordinator
        w.load(URLRequest(url: URL(string: "https://accounts.google.com/ServiceLogin?service=youtube&hl=en&continue=https%3A%2F%2Fwww.youtube.com%2F")!))
        return w
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    final class Coordinator: NSObject, WKNavigationDelegate {
        let done: () -> Void
        init(_ d: @escaping () -> Void) { done = d }
        func webView(_ w: WKWebView, didFinish navigation: WKNavigation!) {
            guard let host = w.url?.host, host.hasSuffix("youtube.com") else { return }
            Task { @MainActor in
                await YTAuth.shared.refresh()
                if YTAuth.shared.signedIn { self.done() }
            }
        }
    }
}

struct GoogleLoginSheet: View {
    let onSignedIn: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            GoogleLoginWebView { onSignedIn(); dismiss() }
                .navigationTitle("Sign in with Google").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
        }
    }
}

/// Shown once, right after the profile setup.
struct SignInView: View {
    @Binding var asked: Bool
    @State private var showLogin = false
    var body: some View {
        let pal = Palette.dark
        Screen(pal: pal) {
            VStack(spacing: 18) {
                Spacer()
                AuralisMark(pal: pal, size: 84)
                Text("Sign in to play online music").font(.title2.bold()).multilineTextAlignment(.center)
                Text("YouTube often asks for a Google account before it hands out songs. Sign in once and online playback and downloads work reliably. You type your password only on Google's own page; Auralis keeps nothing except the session on this phone.")
                    .font(.footnote).foregroundStyle(pal.sub).multilineTextAlignment(.center).padding(.horizontal, 28)
                Button { showLogin = true } label: {
                    Label("Continue with Google", systemImage: "g.circle.fill").font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(pal.gradient, in: Capsule()).foregroundStyle(.black).padding(.horizontal, 24)
                }
                Button("Skip for now") { asked = true }.font(.subheadline).foregroundStyle(pal.sub)
                Text("Tip: use a spare Google account, not your main one.").font(.caption2).foregroundStyle(pal.sub)
                Spacer()
            }
        }
        .foregroundStyle(.white).environment(\.colorScheme, .dark).preferredColorScheme(.dark)
        .sheet(isPresented: $showLogin) { GoogleLoginSheet { asked = true } }
    }
}
