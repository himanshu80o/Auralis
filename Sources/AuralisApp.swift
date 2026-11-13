import SwiftUI

@main struct AuralisApp: App {
    @StateObject private var player = PlaybackManager.shared
    @StateObject private var library = MusicLibrary()
    @StateObject private var videos = VideoLibrary()
    @StateObject private var folders = FolderLibrary()
    @AppStorage("onboarded") private var onboarded = false
    @AppStorage("theme") private var theme = 0
    var body: some Scene {
        WindowGroup {
            Group {
                if onboarded { RootView() } else { WelcomeView(onboarded: $onboarded) }
            }
            .environmentObject(player).environmentObject(library).environmentObject(videos).environmentObject(folders)
            .tint(Color(red: 0.1, green: 0.8, blue: 0.85))
            .preferredColorScheme(theme == 1 ? .light : theme == 2 ? .dark : nil)
        }
    }
}

struct WelcomeView: View {
    @Binding var onboarded: Bool
    @EnvironmentObject var lib: MusicLibrary
    @EnvironmentObject var vids: VideoLibrary
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image("Logo").resizable().frame(width: 120, height: 120).clipShape(RoundedRectangle(cornerRadius: 28))
            Text("AURALIS").font(.largeTitle.bold())
            Text("Every Sound. Every Moment.").foregroundStyle(.secondary)
            Text("Auralis needs access to your Music library and Photos videos. iOS does not allow scanning other storage; you can add Files folders later.")
                .font(.footnote).multilineTextAlignment(.center).padding(.horizontal, 32)
            Spacer()
            Button("SCAN MY DEVICE") {
                Task { await lib.requestAndLoad(); await vids.requestAndLoad(); onboarded = true }
            }.buttonStyle(.borderedProminent).controlSize(.large)
        }.padding().background(Color(red: 0.04, green: 0.08, blue: 0.16).ignoresSafeArea()).preferredColorScheme(.dark)
    }
}

struct RootView: View {
    @EnvironmentObject var player: PlaybackManager
    @State private var showPlayer = false
    var body: some View {
        TabView {
            SongsView().tabItem { Label("Music", systemImage: "music.note") }
            VideosView().tabItem { Label("Videos", systemImage: "play.rectangle") }
            OnlineView().tabItem { Label("Online", systemImage: "globe") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .safeAreaInset(edge: .bottom, spacing: 49) {
            if player.current != nil { MiniPlayer().onTapGesture { showPlayer = true } }
        }
        .sheet(isPresented: $showPlayer) { FullPlayer() }
    }
}
