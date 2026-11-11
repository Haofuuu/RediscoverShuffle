# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

`AGENTS.md` holds the project's binding rules (frameworks, privacy, signing, never modifying the user's playlists); follow it alongside this file. `README.md` is the user-facing manual and holds the real-device verification checklist, so keep it current when behavior changes.

## Commands

All commands need macOS with Xcode; there is no Swift toolchain on Linux cloud containers.

- Build the app (no signing):
  `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project RediscoverShuffle.xcodeproj -scheme RediscoverShuffle -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
- Run the platform-independent tests (SwiftPM, macOS):
  `/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift test`
- Run one suite or test: `swift test --filter QueueProgressTests` or `swift test --filter "QueueProgressTests/duplicateOccurrencesUsePlayerIndex"`
- Run both the build and `swift test` before finishing any Swift change.

There is no linter or formatter configured.

### Two test targets

- `RediscoverShuffleCoreTests/` (Swift Testing, `@Suite`/`@Test`) belongs only to `Package.swift`, whose `RediscoverShuffleCore` target compiles just `RediscoverShuffle/Shuffle/`. This is where nearly all tests live.
- `RediscoverShuffleTests/WeightedShuffleEngineTests.swift` (XCTest) belongs only to the Xcode project's test target and runs on a simulator via Product > Test. It uses `#if SWIFT_PACKAGE` to pick the module it imports.

`Package.swift` uses swift-tools 6.0, so `Shuffle/` compiles in the Swift 6 language mode (strict concurrency) under `swift test`, while the Xcode app target uses `SWIFT_VERSION = 5.0`. Code in `Shuffle/` must compile cleanly under both.

The Xcode project lists files explicitly (no synchronized folders): a new source file must be added to `project.pbxproj` (file reference, group, and the target's Sources phase) or the app build won't see it. A new file in `Shuffle/` is picked up by SwiftPM automatically, but still needs adding to the Xcode project.

## Architecture

### Layers

- `RediscoverShuffle/Shuffle/` — pure Swift, Foundation only, no MediaPlayer/MusicKit/UIKit/SwiftUI. Holds the weighted-shuffle math (`WeightedShuffleEngine`, injectable `RandomNumberGenerator`), queue position logic (`QueueProgress`), persistence of the last queue (`GeneratedQueueStore`), settings keys and defaults (`AppSettings`), sorting, rediscovery stats, the swipe-back rules (`PageSwipe`), cover matching by ID or unique name, and artwork colour extraction. Anything that needs deterministic tests goes here.
- `RediscoverShuffle/Services/` — `@MainActor` `ObservableObject`s that wrap Apple frameworks. They are created once in `RediscoverShuffleApp` and injected as `environmentObject`s:
  - `MusicLibraryService`: authorization, `MPMediaQuery.playlists()` loading into `LibraryPlaylist`/`PlaylistEntry`, and debounced refresh on library-change notifications.
  - `MusicPlaybackService`: drives `MPMusicPlayerController.systemMusicPlayer`, now-playing state, and maps Music's queue index to positions in the generated order.
  - `GeneratedQueueSession`: remembers the latest `PlaylistViewModel` (the Continue card) separately from `playingQueue` (what Music was actually handed, which the full player's Up Next follows), persists it through `GeneratedQueueStore`, and rebuilds it after relaunch.
  - `PlaylistCoverStore`: the only place that queries MusicKit; matches library playlists to MusicKit playlists via `MusicLibraryRequest` and keeps their `Artwork`. Views (`Components.swift`, `ColorField.swift`) only render that `Artwork` and read its colours.
  - `PinnedPlaylistStore`: pinned IDs and their order.
- `RediscoverShuffle/ViewModels/PlaylistViewModel.swift` — bridges `PlaylistEntry` into `ShuffleCandidate`s for the engine and back. Each reshuffle or Play gets a new `queueID`; services use it to tell a preview-only reshuffle apart from the order Music is actually playing.
- `RediscoverShuffle/Views/` — SwiftUI. `RootView` switches between permission onboarding and the playlist browser and hosts the floating mini player. `ColorField.swift` and `ArtworkColorPalette` produce per-playlist artwork-themed backgrounds; accents always use the app's `ember` colour, never artwork colours. `PlaylistPageStage.swift` is UIKit: it shows the playlist page and owns its whole transition (see the invariants below).

### Invariants spanning several files

- Duplicate playlist entries are distinct: `PlaylistEntryIdentifier` is (playlist persistent ID, original index), not the song ID. Shuffling, persistence, and queue-position matching (`QueueProgress.matchingPosition`, which prefers Music's player index and otherwise the nearest occurrence) all depend on this.
- Never drop an entry just because `assetURL` is `nil`. Music decides playability at play time.
- `playCount` is read once at library load (`PlaylistEntry.init`); views, sorting, and shuffling never go back to `MPMediaItem` for it.
- Persistence holds only opaque persistent IDs, entry positions, and playback progress, never `MPMediaItem`s or song metadata. Restoring after relaunch re-resolves those IDs against the freshly loaded playlists.
- The playlist page is not in the `NavigationStack`. `PlaylistPageStage` (created in `RootView`, reached through the `pageStage` environment value) hosts each `PlaylistDetailView` in a card over the Playlists screen and is the only thing that moves it: opening out of a cover marked with `.pageSource(_:cornerRadius:)`, following a swipe back, springing back, and closing. Every motion starts from the card's presentation layer, so any of them can be interrupted; don't add `navigationDestination`, `navigationTransition`, or SwiftUI animations of the page's position alongside it. The page draws its own top bar and gets its insets from the stage's `PageLayout`, not from UIKit's safe area. Views inside the page reach it through the `playlistPage` environment value (`goBack()`, the `.playlistPage` coordinate space, and `sidewaysDragFrame` for controls that keep sideways drags). The Playlists screen is never moved, scaled or redrawn for a page: it only dims, in the stage's own UIKit layer. Any transform above its hosting view makes the list lay itself out against the scaled position (a 0.913 set-back moved the whole list 42 pt on the phone), and any SwiftUI state that changes as a page comes or goes costs frames mid-motion, so the stage publishes nothing; the one signal is `PageCover.hidesPlaylists`, read only by the browser's backdrop and flipped only while nothing moves. One `PageSwipeGestureRecognizer` sits on the stage view rather than on each card, and `PageStageView.hitTest` sorts every touch: page content, the stage itself (a page not showing yet, or one caught on its way back, which turns round at touch-down without its content seeing the touch), or through to Playlists. Thresholds and the card's geometry under the finger live in `Shuffle/PageSwipe.swift` with tests.
- Play submits only the remaining visible suffix (`prepareVisibleOrderForPlayback`), so songs that already played aren't replayed.

### Localization

UI strings live in `Resources/Localizable.xcstrings` and permission/app-name strings in `Resources/InfoPlist.xcstrings`, in English and Simplified Chinese (`zh-Hans`). New user-facing text, including VoiceOver labels and error messages, needs both.

## Verification limits

The simulator has no real Music library and can't fully exercise `systemMusicPlayer` or MusicKit covers. Changes to authorization, library loading, playback, or covers need checking on a physical iPhone against the README's checklists. Say so when you can't do that.
