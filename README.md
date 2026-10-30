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

The generated queue belongs to the system Music player. Playback therefore continues through the Music app, Lock Screen, and Control Center after Rediscover Shuffle leaves the foreground. The app deliberately does not request background-audio capability. Rediscover Shuffle saves only the queue's opaque library identifiers, entry positions, and last validated playback position so the most recent queue can be reconstructed after relaunch; it never serializes `MPMediaItem` objects or song metadata.

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
2. Search or browse the alphabetically sorted playlist list. Swipe right or touch and hold a playlist to pin it above the other playlists. When two or more playlists are pinned, tap **Edit** and drag them into your preferred order, or use **Move Up** / **Move Down** in the touch-and-hold menu. Pull down to refresh after changing the library; the list also refreshes on its own when the Music library changes.
3. Open a playlist. A weighted order is ready immediately under **Up Next**, and the header summarizes how many songs are **unplayed** or **overlooked** (played no more than a quarter as often as the playlist's median song). Matching badges mark those songs in the list.
4. Tap **Play** to send exactly that order to Music, or **Reshuffle** to roll a new order. The **Rediscovery** menu chooses one of six levels from Off (0) to Maximum (5); changing it previews a new order right away unless that playlist's queue is already playing.
5. Switch to **All Songs** to browse the playlist in a remembered sort order—Default, play count low-to-high, play count high-to-low, or singer. Sorting never changes the shuffle.
6. While the queue plays, the current song is highlighted and earlier songs move out of **Up Next**; going back in Music restores them. The main button becomes **Pause** / **Resume**. Tapping **Play** on a partly played saved queue submits only the songs still shown, so it never restarts songs that already moved out of the list.
7. A mini player stays at the bottom of every screen whenever Music has a current song. Tap it for the full player with previous, play/pause, and next controls, plus the rest of the Rediscover queue when it is the one playing. **Open Music** jumps to the Music app.
8. After navigating away or relaunching, the **Continue** card at the top of the Playlists screen reopens the most recently played order with its progress. Reshuffling that queue updates the card; previewing other playlists never replaces it.

The interface uses system typography, artwork-first layouts with 2×2 album mosaics, generated covers for playlists without artwork, artwork-tinted headers, and an ember-red accent taken from the app icon. Buttons give press feedback and haptics on Play and Reshuffle; reshuffled rows glide into place, and with Reduce Motion enabled they swap without movement. Playback actions show a preparation indicator and disable repeat submissions while Music prepares the queue.

On relaunch, the saved order is rebuilt from the current authorized Music library. Entries removed from the source playlist cannot be reconstructed and are omitted. Because public `MediaPlayer` APIs do not expose a system-queue identifier, live progress is reattached only when Music's current queue index and item identifier match the saved order. Replacing or editing the queue in Music stops Rediscover Shuffle from advancing the saved display; it does not erase that display.

The source playlist is never edited or replaced.

## Settings

Tap the gear on the Playlists screen to open the native Settings form. Appearance can follow the system or stay in light or dark mode. The same persisted Rediscovery and song-sort preferences used by playlist screens are available under **Shuffle**, along with a remembered Show Play Counts toggle. **Language** opens the app's page in iOS Settings, where Apple's per-app controls live; only translations included with the app can appear as choices.

The interface is available in English and Simplified Chinese, including VoiceOver descriptions, playback errors, the app name, and the Music-library permission explanation. To switch languages, open the app's page in iOS Settings, choose **Language**, and select **简体中文** or English. Restart the app if iOS does not refresh an already open screen immediately.

Settings shows Music-library authorization only when access is missing, shows the installed version and build, links to the public source repository, and can clear Rediscover Shuffle's locally saved queue after confirmation. Clearing the saved queue does not stop Apple Music, change playlists, or erase unrelated preferences.

## Troubleshooting

### Verify the redesigned interface on an iPhone

- Check permission onboarding, playlist search, pinning/reordering, the Rediscovery menu, the Continue card, and the mini player in both light and dark mode.
- On a fresh install, the system Music permission prompt should appear only after **Get Started**. If permission is denied, the app should offer **Open Settings**.
- Try a small screen, landscape, and the largest Accessibility Text Size. Titles and song details should wrap, Play and Reshuffle should stack vertically, and controls should remain reachable by scrolling.
- With VoiceOver, check playlist and song labels (including Unplayed/Overlooked), the Rediscovery menu value, pin menus, mini-player controls, and current-song announcements. Enable Reduce Motion and confirm reshuffles swap without sliding, the playing waveform holds still, and onboarding fades without movement.
- Play a real playlist, leave and reopen the app, and confirm current-song highlighting, the Continue card's progress, **Pause** / **Resume**, **Reshuffle**, the mini player, and the full player match the Music app. Simulator fixtures cannot verify authorization or system Music playback.
- Confirm the app icon appears in the Music permission prompt on a device. The iOS 27 Simulator shows a placeholder there for this app's single-PNG icon.

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
- `MusicPlaybackService`: system player queue, playback notifications, current track, and duplicate-safe queue position
- `PinnedPlaylistStore`: persistent pinned-playlist state and user-defined pinned order
- `GeneratedQueueSession`: persists lightweight queue identifiers and reconstructs the most recent queue after relaunch
- `GeneratedQueueStore`: file-scoped queue persistence and clearing, independent from user preferences
- `QueueProgress`: Apple-independent matching and remaining-order projection
- `AppSettings`: centralized preference keys, defaults, appearance options, and strength labels
- `PlaylistSongSort`: deterministic playlist display sorting by source order, play count, or singer
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
- Open Settings from the gear button; verify System, Light, and Dark appearance update the whole app and remain selected after relaunch.
- Change Rediscovery, song sort, and Show Play Counts in Settings; open a playlist to confirm the changes are immediately reflected and hidden counts are not read by VoiceOver.
- Verify Language opens the app's iOS Settings page and does not show nonfunctional in-app language choices.
- Switch App Language to Simplified Chinese and verify onboarding, playlists, queue controls, Settings, alerts, VoiceOver descriptions, the Home Screen app name, and the Music-permission prompt appear in Chinese.
- Confirm the Music permission status is current and denied/restricted states offer Open iOS Settings without displaying another authorization prompt.
- Clear a saved queue after confirming; verify the Continue card disappears while Apple Music continues playing and other preferences remain unchanged.
- Change the song-list sorting between Default, both play-count directions, and singer; leave and reopen a playlist and confirm the choice is remembered.
- Generate several queues and confirm all playlist entries appear once and duplicates remain separate.
- Start playback, leave the app, and use Music, Lock Screen, and Control Center; then return and confirm the now-playing state updated.
- Let several songs advance and confirm earlier rows leave the visible queue, the current row moves to the top, and Back restores earlier rows.
- After several songs advance, confirm the current row is at the top of **Up Next**, and that after replacing Music's queue elsewhere, **Play** starts from that remaining row without restoring earlier songs.
- Quit and reopen Rediscover Shuffle while its Music queue is still active; confirm the **Continue** card restores the order at the current duplicate-safe position.
- Use the mini player's play/pause and next buttons and the full player's previous button (which restarts the song after a few seconds of playback); confirm Music responds and the highlighted row follows.
- Replace the queue in Music and confirm Rediscover Shuffle freezes the saved order instead of advancing it against unrelated playback.
- Confirm the Music queue follows the preview order and ordinary Music shuffle remains off.
- Try an unavailable song if one is present and confirm the rest of the queue can continue.
