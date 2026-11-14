import SwiftUI

@main struct AuralisApp: App {
    @StateObject private var player = PlaybackManager.shared
    @StateObject private var library = MusicLibrary()
    @StateObject private var videos = VideoLibrary()
    @StateObject private var folders = FolderLibrary()
    @StateObject private var downloads = DownloadManager.shared
    @StateObject private var favs = FavoritesStore()
    @StateObject private var ui = UIState()
    @AppStorage("onboarded") private var onboarded = false
    @AppStorage("setupDone") private var setupDone = false
    @AppStorage("theme") private var theme = 0
    var body: some Scene {
        WindowGroup {
            Group {
                if !onboarded { WelcomeView(onboarded: $onboarded) }
                else if !setupDone { SetupView() }     // asks username + region the first time
                else { RootView() }
            }
            .environmentObject(player).environmentObject(library).environmentObject(videos).environmentObject(folders)
            .environmentObject(downloads).environmentObject(favs).environmentObject(ui)
            .tint(theme == 3 ? Palette.purple.accent : theme == 4 ? Palette.blue.accent : Color(red: 0.1, green: 0.8, blue: 0.85))
            .preferredColorScheme(theme == 1 ? .light : theme == 0 ? nil : .dark)
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
            AuralisMark(pal: .dark, size: 120)
            Text("AURALIS").font(.largeTitle.bold()).tracking(3)
            Text("EVERY SOUND. EVERY MOMENT.").font(.footnote.weight(.semibold)).tracking(1.6).foregroundStyle(Palette.dark.accent)
            Text("Auralis needs access to your Music library and Photos videos. iOS does not allow scanning other storage; you can add Files folders later.")
                .font(.footnote).multilineTextAlignment(.center).padding(.horizontal, 32).foregroundStyle(.white.opacity(0.7))
            Spacer()
            Button("SCAN MY DEVICE") {
                Task { await lib.requestAndLoad(); await vids.requestAndLoad(); onboarded = true }
            }.buttonStyle(.borderedProminent).controlSize(.large)
        }.padding().foregroundStyle(.white).background(Palette.dark.background.ignoresSafeArea()).preferredColorScheme(.dark)
    }
}

struct RootView: View {
    @EnvironmentObject var ui: UIState
    var body: some View {
        // Each tab hosts its own mini player *above* the tab bar, so the tab bar is never covered.
        TabView {
            SongsView().tabItem { Label("Music", systemImage: "music.note") }
            VideosView().tabItem { Label("Videos", systemImage: "play.rectangle") }
            OnlineView().tabItem { Label("Online", systemImage: "icloud") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .sheet(isPresented: $ui.showPlayer) { FullPlayer() }
    }
}
