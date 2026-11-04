# Rediscover Shuffle

Rediscover Shuffle is a native SwiftUI iPhone app that gives overlooked music a better chance of appearing early in a playlist. It works entirely on the device, uses Apple's public `MediaPlayer` framework for the library and playback and MusicKit for the playlist covers Music shows, and needs no App Store Connect record, backend, or third-party dependencies. Installing it requires a paid Apple Developer Program membership with the MusicKit App Service enabled for the app's identifier.

## What the app does

1. Requests access to the Music library with `MPMediaLibrary.requestAuthorization`.
2. Reads playlists already visible in the library using `MPMediaQuery.playlists()`.
3. Reads each entry's `MPMediaItem.playCount` and keeps duplicate playlist entries distinct without exposing internal positions in the interface.
4. Generates a complete weighted-random permutation without replacement.
5. Sends that exact order to `MPMusicPlayerController.systemMusicPlayer` with Music's normal shuffle turned off.
6. Shows the cover Music uses for each playlist, read with MusicKit's `MusicLibraryRequest`, under the same Media & Apple Music permission.

For a song with play count `p` and selected bias `b`, its weight is:

```swift
pow(Double(p) + 1.0, -b)
```

Each entry receives an exponential random key, `-log(U) / weight`, and the entries are ordered by ascending key. A lower play count raises the chance that an entry appears earlier, but it never turns the shuffle into a play-count sort. At strength 0 all entries have equal weight, which is an ordinary random shuffle.

The generated queue belongs to the system Music player. Playback therefore continues through the Music app, Lock Screen, and Control Center after Rediscover Shuffle leaves the foreground. The app deliberately does not request background-audio capability. Rediscover Shuffle saves only the queue's opaque library identifiers, entry positions, and last validated playback position so the most recent queue can be reconstructed after relaunch; it never serializes `MPMediaItem` objects or song metadata.

All music metadata and calculations remain on the phone. There is no analytics, database, or server, and the app makes no network requests of its own; MusicKit may download the cover of an Apple Music playlist that isn't stored on the phone.

## Requirements

- iPhone running iOS 17 or later
- Current stable Xcode
- An Apple Account added to Xcode that belongs to a paid Apple Developer Program team
- An active Apple Music subscription for subscription tracks
- The playlist already added to the iPhone's Music library

## Technical limitation

The public `MediaPlayer` library APIs expose only playlists and songs visible in the user's Music library. An Apple Music playlist that is visible only in the catalog must first be added to the library in the Music app. Rediscover Shuffle cannot search the full Apple Music catalog.

Cloud and DRM-protected songs can have a `nil` `assetURL`; the app intentionally does not exclude them because the system Music player may still play them. Availability is ultimately decided by the Music app at playback time. `MPMusicPlayerController` does not provide a reliable per-item playback-error callback, so the app shows preparation failures and provides **Skip Item and Continue** while preserving the remaining queue. The system player may also skip an unavailable item itself.

Play counts are the values Apple exposes through `MPMediaItem.playCount`. These can differ from listening history shown by other Apple Music features, and Apple does not provide this app a supported way to force their synchronization.

## Installation instructions

1. Install the current stable Xcode from the Mac App Store.
2. Open `RediscoverShuffle.xcodeproj`.
3. In Xcode, choose **Xcode > Settings > Accounts** and add your Apple Account.
4. Select the **RediscoverShuffle** app target in the project editor.
5. Open **Signing & Capabilities**.
6. Make sure **Automatically manage signing** is enabled.
7. Select your paid developer team from the Team menu.
8. If Xcode reports that the identifier is unavailable, change `com.example.RediscoverShuffle` to a unique value such as `com.yourname.RediscoverShuffle`.
9. Connect the iPhone to the Mac, unlock it, tap **Trust** if asked, and complete the trust prompt on the Mac.
10. Enable **Developer Mode** on the iPhone if iOS requests it: **Settings > Privacy & Security > Developer Mode**, then restart and confirm.
11. Select the connected iPhone as the run destination in Xcode's toolbar.
12. Press **Run** (the triangular play button).
13. On the phone, open Rediscover Shuffle and grant Music-library permission when prompted.

### Turn on MusicKit for playlist covers

Music's own playlist covers come from MusicKit, which works only when the app's identifier has the MusicKit App Service. Do this once, after Xcode has registered the identifier in step 12:

1. Sign in at [developer.apple.com/account](https://developer.apple.com/account) and open **Certificates, Identifiers & Profiles > Identifiers**.
2. Select the app's identifier (for example `com.michael.RediscoverShuffle.a6a8c814`).
3. Open the **App Services** tab, check **MusicKit**, and click **Save**.
4. Back in Xcode, press **Run** again. Changes can take a few minutes to reach the provisioning profile.

No entitlement, developer token, private key, App Store Connect record, or TestFlight setup is needed; Xcode's automatic signing and MusicKit handle the token. Without the App Service the app still works, and every playlist shows the mosaic built from its songs.

## Using the app

1. Grant Music access after reading the onboarding explanation.
2. Search or browse the alphabetically sorted playlist list. Swipe right or touch and hold a playlist to pin it above the other playlists. When two or more playlists are pinned, tap **Edit** and drag them into your preferred order, or use **Move Up** / **Move Down** in the touch-and-hold menu. Pull down to refresh after changing the library; the list also refreshes on its own when the Music library changes.
3. Open a playlist. A weighted order is ready immediately under **Up Next**, and the header summarizes how many songs are **unplayed** or **overlooked** (played no more than a quarter as often as the playlist's median song). Matching badges mark those songs in the list.
4. Tap **Play** to send exactly that order to Music, or **Reshuffle** to roll a new order. The **Rediscovery** menu chooses one of six levels from Off (0) to Maximum (5); changing it previews a new order right away unless that playlist's queue is already playing.
5. Switch to **All Songs** to browse the playlist in a remembered sort order—Default, play count low-to-high, play count high-to-low, or singer. Sorting never changes the shuffle.
6. While the queue plays, the current song is highlighted and earlier songs move out of **Up Next**; going back in Music restores them. The main button becomes **Pause** / **Resume**. Tapping **Play** on a partly played saved queue submits only the songs still shown, so it never restarts songs that already moved out of the list.
7. A mini player stays at the bottom of every screen whenever Music has a current song; its glass picks up a tint from the song's artwork. Tap it for the full player, which zooms out of the mini player and shows previous, play/pause, and next controls, a progress bar you can drag (or adjust with VoiceOver) to seek, and the rest of the Rediscover queue when it is the one playing. **Open Music** jumps to the Music app.
8. After navigating away or relaunching, the **Continue** card at the top of the Playlists screen reopens the most recently played order with its progress. Reshuffling that queue updates the card; previewing other playlists never replaces it. To remove the card, touch and hold it and choose **Remove**; Music keeps playing, the playlist isn't changed, and the next **Play** saves a new order.

Every playlist screen takes its colours from its own artwork. The app reads a few colours from the playlist's cover in Music, or else from up to four album covers or a generated cover, and lays them out as a soft colour field behind the header that fades into a tinted page; Play, Reshuffle, badges, and secondary text use matching colours chosen to keep WCAG AA contrast in light and dark mode. While a playlist's queue is playing, its field drifts slowly; each Reshuffle deals the colours into a new arrangement. The full player is always dark and fills the screen with the current song's colours, which blend into the next song's when the track changes. The Continue card wears its playlist's colours, and the welcome screen uses the app's ember and wine.

Opening a playlist zooms out of its cover on iOS 18 and later; iOS 17 uses the standard push and a simpler static gradient instead of the animated field. The interface keeps system typography, with an expanded display face for playlist titles, 2×2 album mosaics, and generated covers for playlists without artwork. A mosaic appears only when four different albums have artwork that can be drawn; songs whose artwork hasn't downloaded from iCloud are skipped, so a cover falls back to a single album or a generated cover instead of showing blank tiles. When MusicKit provides the cover Music shows for a playlist, whether a custom image or Music's own collage, it replaces the mosaic and the colour field takes its colours from that cover. MusicKit and `MediaPlayer` share no documented playlist ID, so the app matches them by ID first and then by name when the name is unique; a playlist it can't match keeps the mosaic. Buttons give press feedback and haptics on Play and Reshuffle; reshuffled rows glide into place. With Reduce Motion enabled, rows swap without movement, colour fields hold still, and track changes crossfade. Colour fields also stop moving when they are off screen. Playback actions show a preparation indicator and disable repeat submissions while Music prepares the queue.

On relaunch, the saved order is rebuilt from the current authorized Music library. Entries removed from the source playlist cannot be reconstructed and are omitted. Because public `MediaPlayer` APIs do not expose a system-queue identifier, live progress is reattached only when Music's current queue index and item identifier match the saved order. Replacing or editing the queue in Music stops Rediscover Shuffle from advancing the saved display; it does not erase that display.

The source playlist is never edited or replaced.

## Settings

Tap the gear on the Playlists screen to open the native Settings form. Appearance can follow the system or stay in light or dark mode; changing it crossfades the whole app, including the open Settings sheet. The same persisted Rediscovery and song-sort preferences used by playlist screens are available under **Shuffle**, along with a remembered Show Play Counts toggle. **Language** opens the app's page in iOS Settings, where Apple's per-app controls live; only translations included with the app can appear as choices.

The interface is available in English and Simplified Chinese, including VoiceOver descriptions, playback errors, the app name, and the Music-library permission explanation. To switch languages, open the app's page in iOS Settings, choose **Language**, and select **简体中文** or English. Restart the app if iOS does not refresh an already open screen immediately.

Settings shows Music-library authorization only when access is missing, shows the installed version and build, and links to the public source repository.

## Troubleshooting

### Verify the redesigned interface on an iPhone

- Check permission onboarding, playlist search, pinning/reordering, the Rediscovery menu, the Continue card, and the mini player in both light and dark mode.
- On iOS 26 and later, confirm the search field stays under the Playlists title, including after returning from a playlist, and that the mini player floats just above the home indicator with rows fading beneath it and tucks behind the keyboard while you search.
- Check playlists with songs from iCloud Music Library that aren't downloaded; their covers should never show blank tiles.
- Compare covers with the Music app: a playlist with a custom image, one with Music's collage, an Apple Music playlist added to the library, and two playlists with the same name. Each cover should match Music, or fall back to the mosaic when Music has none or the playlist can't be matched, and its colour field should match the cover shown.
- Open playlists with colourful, black-and-white, and missing artwork. Each should get its own colour field with readable text and buttons; grey covers should keep a neutral page with the app's ember accent.
- On a fresh install, the system Music permission prompt should appear only after **Get Started**. If permission is denied, the app should offer **Open Settings**.
- Try a small screen, landscape, and the largest Accessibility Text Size. Titles and song details should wrap, Play and Reshuffle should stack vertically, and controls should remain reachable by scrolling.
- With VoiceOver, check playlist and song labels (including Unplayed/Overlooked), the Rediscovery menu value, pin menus, mini-player controls, and current-song announcements. Enable Reduce Motion and confirm reshuffles swap without sliding, the playing waveform and colour fields hold still, track changes crossfade, and onboarding fades without movement.
- Play a real playlist, leave and reopen the app, and confirm current-song highlighting, the Continue card's progress, **Pause** / **Resume**, **Reshuffle**, the mini player, and the full player match the Music app. Simulator fixtures cannot verify authorization or system Music playback.
- Confirm the app icon appears in the Music permission prompt on a device. The iOS 27 Simulator shows a placeholder there for this app's icon.
- Check the home-screen icon in the Default, Dark, and Tinted icon styles (touch and hold the home screen, then Edit > Customize).

### Signing errors

Confirm that an Apple Account is present under **Xcode > Settings > Accounts**, automatic signing is enabled on the app target, and your paid developer team is selected. If covers still show only mosaics, check that the MusicKit App Service is enabled for the app's identifier and run the app again. Signing errors for the test bundle do not prevent installing the app; when running tests on a device, ensure the test target uses the same team.

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

### The provisioning profile expired

Development profiles for a paid team last about a year. Connect the iPhone to the Mac, open the project in Xcode, select the phone, and press Run again. If needed, remove the expired app from the phone first; reinstalling loses only the app's local strength/onboarding settings, not the Music library or playlists.

## Project structure

- `MusicLibraryService`: permission, playlist queries, stable identifiers, and library-change refreshes
- `PlaylistCoverStore`: reads Music's playlist covers with MusicKit and their colours for the colour fields
- `PlaylistCoverMatcher`: Apple-independent pairing of `MediaPlayer` playlists with MusicKit playlists by ID or unique name
- `MusicPlaybackService`: system player queue, playback notifications, current track, and duplicate-safe queue position
- `PinnedPlaylistStore`: persistent pinned-playlist state and user-defined pinned order
- `GeneratedQueueSession`: persists lightweight queue identifiers and reconstructs the most recent queue after relaunch
- `GeneratedQueueStore`: file-scoped queue persistence and clearing, independent from user preferences
- `QueueProgress`: Apple-independent matching and remaining-order projection
- `AppSettings`: centralized preference keys, defaults, appearance options, and strength labels
- `PlaylistSongSort`: deterministic playlist display sorting by source order, play count, or singer
- `WeightedShuffleEngine`: pure weighted-permutation math with injectable randomness
- `PlaylistViewModel`: maps distinct playlist entries into and out of the pure shuffle engine
- `ArtworkColorPalette`: Apple-independent colour extraction and contrast-checked colour roles for artwork-themed screens
- SwiftUI views: permission, playlist browser, playlist detail, mini player and full player, and the shared colour field
- `RediscoverShuffleTests`: deterministic unit tests for the shuffle math and invariants

## Testing

In Xcode, select an iOS Simulator and run **Product > Test**. The shuffle engine, the artwork colour rules, and playlist cover matching also have a companion Swift Package manifest so their platform-independent tests can run from a terminal with:

```sh
swift test
```

The simulator cannot supply a real on-device Music library or fully validate `systemMusicPlayer`; complete the real-device checklist below after installing.

## Real-device verification checklist

- Accept and deny the Music permission once each; verify the app never shows a blank screen and that Open Settings works.
- Confirm playlists added to the library appear, including an empty, one-song, cloud-only, and duplicate-entry playlist when available.
- Confirm titles, artists, artwork, and play counts match Music.
- With the MusicKit App Service enabled, confirm playlist covers match Music, including custom images and Music's collages, and that each playlist's colour field follows its cover. Rename a playlist in Music and confirm its cover still matches after returning to the app.
- Open Settings from the gear button; verify System, Light, and Dark appearance switch the Settings sheet and the screen behind it together and remain selected after relaunch.
- Change Rediscovery, song sort, and Show Play Counts in Settings; open a playlist to confirm the changes are immediately reflected and hidden counts are not read by VoiceOver.
- Verify Language opens the app's iOS Settings page and does not show nonfunctional in-app language choices.
- Switch App Language to Simplified Chinese and verify onboarding, playlists, queue controls, Settings, alerts, VoiceOver descriptions, the Home Screen app name, and the Music-permission prompt appear in Chinese.
- Confirm the Music permission status is current and denied/restricted states offer Open iOS Settings without displaying another authorization prompt.
- Touch and hold the Continue card and choose **Remove** (with VoiceOver, use the Remove action); verify the card disappears while Apple Music keeps playing, other preferences stay unchanged, and the next **Play** brings the card back.
- Change the song-list sorting between Default, both play-count directions, and singer; leave and reopen a playlist and confirm the choice is remembered.
- Generate several queues and confirm all playlist entries appear once and duplicates remain separate.
- Start playback, leave the app, and use Music, Lock Screen, and Control Center; then return and confirm the now-playing state updated.
- Let several songs advance and confirm earlier rows leave the visible queue, the current row moves to the top, and Back restores earlier rows.
- After several songs advance, confirm the current row is at the top of **Up Next**, and that after replacing Music's queue elsewhere, **Play** starts from that remaining row without restoring earlier songs.
- Quit and reopen Rediscover Shuffle while its Music queue is still active; confirm the **Continue** card restores the order at the current duplicate-safe position.
- Use the mini player's play/pause and next buttons and the full player's previous button (which restarts the song after a few seconds of playback); confirm Music responds and the highlighted row follows.
- Drag the full player's progress bar and confirm Music seeks to the same point; with VoiceOver, swipe up or down on it to skip 15 seconds.
- Leave the full player and a playing playlist open for a few minutes and confirm scrolling stays smooth and the phone does not run warm.
- Replace the queue in Music and confirm Rediscover Shuffle freezes the saved order instead of advancing it against unrelated playback.
- Confirm the Music queue follows the preview order and ordinary Music shuffle remains off.
- Try an unavailable song if one is present and confirm the rest of the queue can continue.
