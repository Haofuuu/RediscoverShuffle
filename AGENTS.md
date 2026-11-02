# Rediscover Shuffle

## Project

- This is a native iPhone app built with Swift, SwiftUI, Apple's public `MediaPlayer` framework, and Swift MusicKit for playlist covers.
- Open `RediscoverShuffle.xcodeproj` for normal development.
- The minimum deployment target is iOS 17.
- The app is signed with a paid Apple Developer Program team, and the App ID has the MusicKit App Service enabled. No backend, private APIs, or third-party dependencies.
- Keep `MediaPlayer` and MusicKit objects and calls that require the main thread isolated behind `@MainActor` services or view models.
- Preserve duplicate playlist entries. Never discard a song solely because its `assetURL` is `nil`.
- Keep weighted-shuffle math independent of Apple frameworks and deterministically testable.

## Build and test

- Build the app without signing:
  `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project RediscoverShuffle.xcodeproj -scheme RediscoverShuffle -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
- Run the pure shuffle tests:
  `/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift test`
- Before finishing Swift changes, run both checks and fix any failures.
- Music-library authorization and system Music-player behavior require verification on a physical iPhone.

## Working agreements

- Use public `MediaPlayer` for library loading and playback. Swift MusicKit may read library data `MediaPlayer` doesn't expose, such as playlist artwork; moving loading or playback to MusicKit needs explicit approval.
- Do not add external dependencies, analytics, or a database. Apart from MusicKit loading its own artwork, the app makes no network requests.
- Keep MusicKit and other Apple frameworks out of `RediscoverShuffle/Shuffle`, which the SwiftPM tests build on macOS.
- Keep the interface native, accessible, Dynamic Type-safe, and compatible with light and dark mode.
- Preserve the user's automatic-signing team and bundle-identifier changes.
- Never modify the user's original playlists.
- Keep installation and device-verification guidance current in `README.md`.
