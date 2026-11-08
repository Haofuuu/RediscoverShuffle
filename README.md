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
2. Search or browse the alphabetically sorted playlist list. Each playlist shows how many of its songs are unplayed, or else overlooked, and empty playlists wait in their own group at the bottom. The search field sits under the large Playlists title when the screen opens and scrolls away with the list, like the Music app's library; scroll back to the top to search again. Search ignores case, accents, and full- or half-width forms. While the field is active, a glass close button beside it cancels the search. Swipe right or touch and hold a playlist to pin it above the other playlists. When two or more playlists are pinned, tap **Edit** and drag them into your preferred order, or use **Move Up** / **Move Down** in the touch-and-hold menu. Pull down to refresh after changing the library; the list also refreshes on its own when the Music library changes, handling a burst of changes in one refresh and leaving the screen untouched when nothing it shows has changed.
3. Open a playlist. A weighted order is ready immediately under **Up Next**, and the header summarizes how many songs are **unplayed** or **overlooked** (played no more than a quarter as often as the playlist's median song). Matching badges mark those songs in the list. Tap the summary to see what unplayed, overlooked, and Rediscovery mean.
4. Tap **Play** to send exactly that order to Music, or **Reshuffle** to roll a new order. The **Rediscovery** menu chooses one of six levels from Off (0) to Maximum (5); changing it previews a new order right away unless that playlist's queue is already playing. While it plays, a caption explains that the change applies on the next **Reshuffle**, and a reshuffled order is labeled as not playing yet until you tap **Play**.
5. Switch to **All Songs** to browse the playlist in a remembered sort order—Default, play count low-to-high, play count high-to-low, or singer. Sorting never changes the shuffle.
6. While the queue plays, the current song is highlighted and earlier songs move out of **Up Next**; going back in Music restores them. The main button becomes **Pause** / **Resume**. Tapping **Play** on a partly played saved queue submits only the songs still shown, so it never restarts songs that already moved out of the list.
7. A mini player stays at the bottom of every screen whenever Music has a current song. It floats on plain glass, as far from the bottom edge as from the sides, like the system's bottom bars, and slides behind the keyboard while you search. Tap it for the full player, which rises as a standard sheet and shows previous, play/pause, and next controls, a progress bar you can drag (or adjust with VoiceOver) to seek, and the rest of the Rediscover queue when it is the one playing. **Open Music** jumps to the Music app.
8. After navigating away or relaunching, the **Continue** card at the top of the Playlists screen reopens the most recently played order with its progress. Reshuffling that queue updates the card; previewing other playlists never replaces it. To remove the card, tap its **⋯** button (or touch and hold it) and choose **Remove**; Music keeps playing, the playlist isn't changed, and the next **Play** saves a new order.

Every playlist screen takes its colours from its own artwork. The app reads a few colours from the playlist's cover in Music, or else from up to four album covers or a generated cover, and lays them out as a soft colour field behind the header that fades into a tinted page, with secondary text that takes only a trace of the artwork's hue and keeps WCAG AA contrast in light and dark mode. Controls never take the artwork's colour: Play, the playing indicator, badge symbols, and other accents all use the app icon's ember, the same in light and dark mode. While a playlist's queue is playing, its field drifts slowly; each Reshuffle deals the colours into a new arrangement. The full player is always dark and fills the screen with the current song's colours, which blend into the next song's when the track changes; each song keeps the same colours every time the player opens. The welcome screen and the Playlists screen share the app's ember-and-wine field, which drifts on the Playlists screen while music plays, and the Continue card is glass over that field. The Playlists title scrolls away with the list under a soft blur, like the Music app's Home. The app runs in portrait only.

On iOS 18 and later, a playlist zooms open out of its cover (or the Continue card's cover) and zooms back into it when you go back; earlier versions use the standard push. The full player rises as the standard sheet. Taps keep working while a playlist zooms back, as on the Home Screen: tap the same playlist to zoom straight back into it, with the same order you just left rather than a fresh shuffle, or tap anything else on the Playlists screen and it responds at once. A swipe from the left edge, or downward, follows your finger, as in Music, even while a playlist is still zooming open; let go and it glides back into its row, and tapping it again right after reopens it. For about a second after the zoom-in lands, iOS is still finishing the opening; a swipe from the edge then goes straight back instead of following the finger, so tapping the playlist as it zooms back always reopens it. A quick swipe toward the right from anywhere else goes back too, and never presses a button it starts on. From the moment you tap Back or start a swipe back, the playlist you're leaving takes no taps, so none of its buttons or popovers can turn up over the Playlists screen. iOS 17 shows a simpler static gradient instead of the animated field. The interface keeps system typography, with an expanded display face for playlist titles, 2×2 album mosaics, and generated covers for playlists without artwork. A mosaic appears only when four different albums have artwork that can be drawn; songs whose artwork hasn't downloaded from iCloud are skipped, so a cover falls back to a single album or a generated cover instead of showing blank tiles. When MusicKit provides the cover Music shows for a playlist, whether a custom image or Music's own collage, it replaces the mosaic and the colour field takes its colours from that cover. MusicKit and `MediaPlayer` share no documented playlist ID, so the app matches them by ID first and then by name when the name is unique; a playlist it can't match keeps the mosaic. Buttons give press feedback and haptics on Play and Reshuffle; reshuffled rows glide into place. With Reduce Motion enabled, rows swap without movement, colour fields hold still, and track changes crossfade. Colour fields also stop moving when they are off screen. Playback actions show a preparation indicator and disable repeat submissions while Music prepares the queue.

On relaunch, the saved order is rebuilt from the current authorized Music library. Entries removed from the source playlist cannot be reconstructed and are omitted. Because public `MediaPlayer` APIs do not expose a system-queue identifier, live progress is reattached only when Music's current queue index and item identifier match the saved order. Replacing or editing the queue in Music stops Rediscover Shuffle from advancing the saved display; it does not erase that display.

The source playlist is never edited or replaced.

## Settings

Tap the gear on the Playlists screen to open the native Settings form. Appearance can follow the system or stay in light or dark mode; changing it crossfades the whole app, including the open Settings sheet. A remembered Show Play Counts toggle controls whether song rows show play counts; Rediscovery strength and song sort are set on each playlist's screen. **Language** opens the app's page in iOS Settings, where Apple's per-app controls live; only translations included with the app can appear as choices.

The interface is available in English and Simplified Chinese, including VoiceOver descriptions, playback errors, the app name, and the Music-library permission explanation. To switch languages, open the app's page in iOS Settings, choose **Language**, and select **简体中文** or English. Restart the app if iOS does not refresh an already open screen immediately.

Settings shows Music-library authorization only when access is missing, shows the installed version and build, and links to the public source repository.

## Troubleshooting

### Verify the redesigned interface on an iPhone

- Check permission onboarding, playlist search, pinning/reordering, the Rediscovery menu, the Continue card, and the mini player in both light and dark mode.
- Confirm the search field shows under the Playlists title on launch, scrolls away as you scroll down, and returns at the top. On iOS 26 and later, check that the mini player keeps the same distance from the sides and bottom edge as the system's bottom bars, with rows fading beneath it, and tucks behind the keyboard while you search.
- Tap the search field and its close button several times in a row, with and without typing first. The field should answer the moment your finger lands, and the close button should fade in beside it as it narrows, then fade out as it widens back. The field should never jump straight to its new width, and no glass should be left beside it afterwards. Do this right after launching the app too: the first tap sets up the keyboard, which takes longest, and it should animate exactly like the later ones.
- Open playlists from their rows and from the Continue card; each should zoom out of its cover and back into it. Tap Back, or let go of a swipe back, and immediately tap another playlist: it should open straight away. Do the same on the playlist you just left: it should zoom back open with the same Up Next order, while opening it again later deals a fresh one. Tap Back, or swipe back and let go, then immediately tap the shrinking playlist's "overlooked ⓘ" line, Play, or pin: only the Playlists screen should respond, and How Rediscovery Works, playback, or a pin change should never come from the playlist you left. Also open a playlist and swipe it away while it is still zooming open, then tap where its ⓘ line was: the same should hold. Try both quickly several times. Start a swipe back and cancel it; the playlist should stay and respond to taps at once. Swipe back repeatedly, reopening the same playlist each time, including swiping from the left edge while it is still zooming open: the playlist should follow your finger and glide back into its row, and tapping it again just after should reopen it, with no long pause before taps respond. Open a playlist, wait about half a second, swipe from the very left edge, and tap the same playlist straight away; repeat several times: it should reopen every time. Start a swipe on the "overlooked ⓘ" line or on Play: the playlist should go back without opening How Rediscovery Works or starting playback. Stay on a playlist for a few seconds, then swipe right from the middle of the screen: it should go back as easily as it does right after opening, while scrolling and the Up Next / All Songs switcher keep working.
- Check that every accent, including Play, the playing waveform, badge symbols, toggles, and the Settings gear, is the same ember as the app icon in both light and dark mode.
- Feel for light haptics on mini-player and full-player controls, a selection tick when pinning or changing appearance, and a firmer tap when removing the Continue card.
- Check playlists with songs from iCloud Music Library that aren't downloaded; their covers should never show blank tiles.
- Compare covers with the Music app: a playlist with a custom image, one with Music's collage, an Apple Music playlist added to the library, and two playlists with the same name. Each cover should match Music, or fall back to the mosaic when Music has none or the playlist can't be matched, and its colour field should match the cover shown.
- Open playlists with colourful, black-and-white, and missing artwork. Each should get its own colour field with readable text and buttons; grey covers should keep a neutral page with the app's ember accent.
- On a fresh install, the system Music permission prompt should appear only after **Get Started**. If permission is denied, the app should offer **Open Settings**.
- Try a small screen and the largest Accessibility Text Size, and confirm the app stays in portrait when the phone turns. Titles and song details should wrap, playlist rows should place the cover above the name, Play and Reshuffle should stack vertically, and controls should remain reachable by scrolling.
- With VoiceOver, check playlist and song labels (including Unplayed/Overlooked), the Rediscovery menu value, pin menus, mini-player controls, and current-song announcements. Enable Reduce Motion and confirm reshuffles swap without sliding, the playing waveform and colour fields hold still, track changes crossfade, and onboarding fades without movement.
- Play a real playlist, leave and reopen the app, and confirm current-song highlighting, the Continue card's progress, **Pause** / **Resume**, **Reshuffle**, the mini player, and the full player match the Music app. Simulator fixtures cannot verify authorization or system Music playback.
- Confirm the app icon appears in the Music permission prompt on a device. The iOS 27 Simulator shows a placeholder there for this app's icon.
- Check the home-screen icon in the Default (white), Dark, and Tinted icon styles (touch and hold the home screen, then Edit > Customize), and that the welcome screen shows the matching white or dark icon.

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
- Turn Show Play Counts off in Settings, and change Rediscovery and song sort on a playlist's screen; confirm the changes are immediately reflected and hidden counts are not read by VoiceOver.
- Verify Language opens the app's iOS Settings page and does not show nonfunctional in-app language choices.
- Switch App Language to Simplified Chinese and verify onboarding, playlists, queue controls, Settings, alerts, VoiceOver descriptions, the Home Screen app name, and the Music-permission prompt appear in Chinese.
- Confirm the Music permission status is current and denied/restricted states offer Open iOS Settings without displaying another authorization prompt.
- Tap the Continue card's **⋯** button, or touch and hold the card, and choose **Remove** (with VoiceOver, use the Remove action); verify the card disappears while Apple Music keeps playing, other preferences stay unchanged, and the next **Play** brings the card back.
- Change the song-list sorting between Default, both play-count directions, and singer; leave and reopen a playlist and confirm the choice is remembered.
- Generate several queues and confirm all playlist entries appear once and duplicates remain separate.
- Start playback, leave the app, and use Music, Lock Screen, and Control Center; then return and confirm the now-playing state updated.
- Let several songs advance and confirm earlier rows leave the visible queue, the current row moves to the top, and Back restores earlier rows.
- After several songs advance, confirm the current row is at the top of **Up Next**, and that after replacing Music's queue elsewhere, **Play** starts from that remaining row without restoring earlier songs.
- Quit and reopen Rediscover Shuffle while its Music queue is still active; confirm the **Continue** card restores the order at the current duplicate-safe position.
- Use the mini player's play/pause and next buttons and the full player's previous button (which restarts the song after a few seconds of playback); confirm Music responds and the highlighted row follows.
- Drag the full player's progress bar and confirm Music seeks to the same point; with VoiceOver, swipe up or down on it to skip 15 seconds. Start a drag and let a call or notification interrupt it; the bar should return to the playing position rather than stay where the finger was. A track over an hour long should show hours in its times.
- Leave the app and come back several times without changing the library; the playlist list should not flicker or reload its covers. To time loading on a device, record with Instruments' Points of Interest (os_signpost) and look for the **Load library** and **Generate order** intervals in the RediscoverShuffle subsystem.
- Leave the full player and a playing playlist open for a few minutes and confirm scrolling stays smooth and the phone does not run warm.
- Replace the queue in Music and confirm Rediscover Shuffle freezes the saved order instead of advancing it against unrelated playback.
- Confirm the Music queue follows the preview order and ordinary Music shuffle remains off.
- Try an unavailable song if one is present and confirm the rest of the queue can continue.
