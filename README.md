# AURALIS – Every Sound. Every Moment.
Build: `brew install xcodegen && xcodegen generate && open Auralis.xcodeproj`, set your Team, run on a real device (iOS 17+).
Online tab: Home-style layout (hero, recents, trending, albums), ad-free streaming via Piped API (JSON only, no web page), Audius fallback. Themes: Dark, Light, System, Neon Purple, Neon Blue (Settings). Background + screen-off playback via audio background mode. Optional: add an image set named "Avatar" for the profile photo.
Implemented: onboarding + permissions, MPMediaQuery song discovery (auto-refresh), PhotoKit video discovery (iCloud-aware), AVPlayer background playback, interruption/route handling, lock-screen/Control Center/Bluetooth controls, queue, shuffle/repeat, mini + full player, search, settings.
Files folders: Settings > Add folder (saved bookmarks, recursive audio scan, ID3/metadata + artwork).
NOT yet built: SwiftData persistence, playlists, favorites, equalizer (AVAudioEngine), lyrics, visualizer, sleep timer, PiP/subtitles, CarPlay, Face ID lock.
Limits: DRM/Apple Music/cloud-only items have no assetURL and can't be played by AVPlayer. iOS has no full-storage scan.
