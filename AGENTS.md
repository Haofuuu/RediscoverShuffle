# Rediscover Shuffle

## Project

- This is a native iPhone app built with Swift, SwiftUI, and Apple's public `MediaPlayer` framework.
- Open `RediscoverShuffle.xcodeproj` for normal development.
- The minimum deployment target is iOS 17.
- Keep the app compatible with free Personal Team signing: no paid Apple capabilities, MusicKit developer tokens, backend, private APIs, or third-party dependencies.
- Keep `MediaPlayer` objects and calls that require the main thread isolated behind `@MainActor` services or view models.
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

- Use public `MediaPlayer`; do not migrate to Swift MusicKit without explicit approval.
- Do not add external dependencies, networking, analytics, a database, or paid Apple services.
- Keep the interface native, accessible, Dynamic Type-safe, and compatible with light and dark mode.
- Preserve the user's automatic-signing team and bundle-identifier changes.
- Never modify the user's original playlists.
- Keep installation and device-verification guidance current in `README.md`.
