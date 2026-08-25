# Rediscover Shuffle

Rediscover Shuffle is a native SwiftUI iPhone app that gives overlooked music a better chance of appearing early in a playlist. It works entirely on the device, uses Apple's public `MediaPlayer` framework, and does not require a paid Apple Developer membership, developer tokens, App Store Connect, a backend, or third-party dependencies.

## What the app does

1. Requests access to the Music library with `MPMediaLibrary.requestAuthorization`.
2. Reads playlists already visible in the library using `MPMediaQuery.playlists()`.
3. Reads each entry's `MPMediaItem.playCount` and keeps duplicate playlist entries distinct without exposing internal positions in the interface.
4. Generates a complete weighted-random permutation without replacement.
5. Sends that exact order to `MPMusicPlayerController.systemMusicPlayer` with Music's normal shuffle turned off.

For a song with play count `p` and selected bias `b`, its weight is:

```swift
pow(Double(p) + 1.0, -b)
```

Each entry receives an exponential random key, `-log(U) / weight`, and the entries are ordered by ascending key. A lower play count raises the chance that an entry appears earlier, but it never turns the shuffle into a play-count sort. At strength 0 all entries have equal weight, which is an ordinary random shuffle.

The generated queue belongs to the system Music player. Playback therefore continues through the Music app, Lock Screen, and Control Center after Rediscover Shuffle leaves the foreground. The app deliberately does not request background-audio capability.

All music metadata and calculations remain on the phone. There is no networking, analytics, database, or server.

## Requirements

- iPhone running iOS 17 or later
- Current stable Xcode
- An Apple Account added to Xcode (a free Personal Team is sufficient)
- An active Apple Music subscription for subscription tracks
- The playlist already added to the iPhone's Music library

## Technical limitation

The public `MediaPlayer` library APIs expose only playlists and songs visible in the user's Music library. An Apple Music playlist that is visible only in the catalog must first be added to the library in the Music app. Rediscover Shuffle cannot search the full Apple Music catalog.

Cloud and DRM-protected songs can have a `nil` `assetURL`; the app intentionally does not exclude them because the system Music player may still play them. Availability is ultimately decided by the Music app at playback time. `MPMusicPlayerController` does not provide a reliable per-item playback-error callback, so the app shows preparation failures and provides **Skip Item and Continue** while preserving the remaining queue. The system player may also skip an unavailable item itself.

Play counts are the values Apple exposes through `MPMediaItem.playCount`. These can differ from listening history shown by other Apple Music features, and Apple does not provide this app a supported way to force their synchronization.

## Free installation instructions

1. Install the current stable Xcode from the Mac App Store.
2. Open `RediscoverShuffle.xcodeproj`.
3. In Xcode, choose **Xcode > Settings > Accounts** and add your Apple Account.
4. Select the **RediscoverShuffle** app target in the project editor.
5. Open **Signing & Capabilities**.
6. Make sure **Automatically manage signing** is enabled.
7. Select your free **Personal Team** from the Team menu.
8. If Xcode reports that the identifier is unavailable, change `com.example.RediscoverShuffle` to a unique value such as `com.yourname.RediscoverShuffle`.
9. Connect the iPhone to the Mac, unlock it, tap **Trust** if asked, and complete the trust prompt on the Mac.
10. Enable **Developer Mode** on the iPhone if iOS requests it: **Settings > Privacy & Security > Developer Mode**, then restart and confirm.
11. Select the connected iPhone as the run destination in Xcode's toolbar.
12. Press **Run** (the triangular play button).
13. On the phone, open Rediscover Shuffle and grant Music-library permission when prompted.

Free Personal Team provisioning normally expires after approximately seven days. Reconnect the iPhone and press Run in Xcode again to reinstall or renew the app. This is an Apple provisioning limitation, not an application bug.

No MusicKit capability, App Service-enabled identifier, MusicKit developer token, media identifier, private key, App Store Connect record, or TestFlight setup is needed.

## Using the app

1. Grant Music access after reading the onboarding explanation.
2. Search or browse the alphabetically sorted playlist list. Swipe right to pin a playlist above unpinned playlists. When two or more playlists are pinned, tap **Edit** and drag them into your preferred order. Pull to refresh or use the refresh button after changing the library.
3. Select a playlist and adjust **Rediscovery Strength** through the six discrete levels from Normal (0) to Maximum (5).
4. Tap **Shuffle and Play** to generate the full queue and begin playback.
5. Inspect the queue, reshuffle without changing the source playlist, or replay the displayed order. After navigating away, use **View Last Queue** on a playlist detail page to reopen the most recently generated order during the current app session. The now-playing card reflects the Music app without replacing its playback controls.

The source playlist is never edited or replaced.

## Troubleshooting

### Signing errors

Confirm that an Apple Account is present under **Xcode > Settings > Accounts**, automatic signing is enabled on the app target, and a Personal Team is selected. Signing errors for the test bundle do not prevent installing the app; when running tests on a device, ensure the test target uses the same team.

### Bundle identifier is not unique

The placeholder `com.example.RediscoverShuffle` may already be registered. In the app target's **Signing & Capabilities** pane, replace it with a reverse-domain identifier unique to you. Xcode gives the test bundle its own `.Tests` suffix.

### Developer Mode is required

On iOS, open **Settings > Privacy & Security > Developer Mode**, enable it, restart the iPhone, and confirm after restart. The option commonly appears only after first connecting the phone to Xcode.

### Music permission was denied

Use the app's **Open Settings** button, or open **Settings > Privacy & Security > Media & Apple Music**, and allow access for Rediscover Shuffle. Return to the app; it rechecks permission when it becomes active.

### No playlists appear

Open Music and verify that the playlist is under **Library > Playlists**, not merely open as an Apple Music catalog page. Allow the Music app time to synchronize, reopen Rediscover Shuffle, and tap Refresh. Device restrictions can also prevent library access.

### A song appears in Apple Music but not here

Add the song or its playlist to the Music library first. The public `MediaPlayer` query cannot browse the full subscription catalog.

### A song is unavailable or playback fails

Confirm the Apple Music subscription is active, the device is online for non-downloaded music, and the song still plays directly in Music. If a queue preparation error appears, choose **Skip Item and Continue**. Regional removal, expired catalog rights, or an unmatched library item can make one song unavailable even when the rest of the queue works.

### The free provisioning profile expired

Connect the iPhone to the Mac, open the project in Xcode, select the phone, and press Run again. If needed, remove the expired app from the phone first; reinstalling loses only the app's local strength/onboarding settings, not the Music library or playlists.

## Project structure

- `MusicLibraryService`: permission, playlist queries, stable identifiers, and library-change refreshes
- `MusicPlaybackService`: system player queue, playback notifications, and current track
- `PinnedPlaylistStore`: persistent pinned-playlist state and user-defined pinned order
- `GeneratedQueueSession`: retains the most recently generated queue while the app is running
- `WeightedShuffleEngine`: pure weighted-permutation math with injectable randomness
- `PlaylistViewModel`: maps distinct playlist entries into and out of the pure shuffle engine
- SwiftUI views: permission, playlist browser, playlist detail, complete queue preview, and now-playing card
- `RediscoverShuffleTests`: deterministic unit tests for the shuffle math and invariants

## Testing

In Xcode, select an iOS Simulator and run **Product > Test**. The shuffle engine also has a companion Swift Package manifest so its platform-independent tests can run from a terminal with:

```sh
swift test
```

The simulator cannot supply a real on-device Music library or fully validate `systemMusicPlayer`; complete the real-device checklist below after installing.

## Real-device verification checklist

- Accept and deny the Music permission once each; verify the app never shows a blank screen and that Open Settings works.
- Confirm playlists added to the library appear, including an empty, one-song, cloud-only, and duplicate-entry playlist when available.
- Confirm titles, artists, artwork, and play counts match Music.
- Generate several queues and confirm all playlist entries appear once and duplicates remain separate.
- Start playback, leave the app, and use Music, Lock Screen, and Control Center; then return and confirm the now-playing state updated.
- Confirm the Music queue follows the preview order and ordinary Music shuffle remains off.
- Try an unavailable song if one is present and confirm the rest of the queue can continue.
