# AURALIS – Every Sound. Every Moment.
Build: `brew install xcodegen && xcodegen generate && open Auralis.xcodeproj`, set your Team, run on a real device (iOS 17+).
Implemented: onboarding + permissions, MPMediaQuery song discovery (auto-refresh), PhotoKit video discovery (iCloud-aware), AVPlayer background playback, interruption/route handling, lock-screen/Control Center/Bluetooth controls, queue, shuffle/repeat, mini + full player, search, settings.
Files folders: Settings > Add folder (saved bookmarks, recursive audio scan, ID3/metadata + artwork).
NOT yet built: SwiftData persistence, playlists, favorites, equalizer (AVAudioEngine), lyrics, visualizer, sleep timer, PiP/subtitles, CarPlay, Face ID lock.
Limits: DRM/Apple Music/cloud-only items have no assetURL and can't be played by AVPlayer. iOS has no full-storage scan.
