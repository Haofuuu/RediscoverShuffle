import Combine
import Foundation
import MediaPlayer
import OSLog

struct GeneratedQueuePlaybackProgress: Equatable {
    let queueID: UUID
    let playerIndex: Int
    let position: Int
    let isCurrentEntryVisible: Bool
}

struct GeneratedQueuePlaybackIndexMapping: Equatable {
    let mediaItemPersistentID: MPMediaEntityPersistentID
    let displayPosition: Int
    let isVisibleEntry: Bool
}

@MainActor
final class MusicPlaybackService: ObservableObject {
    /// `nil` when the system Music player has no current item.
    @Published private(set) var nowPlaying: NowPlayingSnapshot?
    @Published private(set) var playbackState: MPMusicPlaybackState = .stopped
    @Published private(set) var isPreparing = false
    @Published private(set) var generatedQueueProgress: GeneratedQueuePlaybackProgress?
    @Published private(set) var generatedQueueInvalidationID: UUID?
    @Published var errorMessage: String?

    private lazy var player = MPMusicPlayerController.systemMusicPlayer
    private let logger = Logger(subsystem: "RediscoverShuffle", category: "Playback")
    private var notificationObservers: [NSObjectProtocol] = []
    private var trackedQueueID: UUID?
    private var trackedQueueMappings: [GeneratedQueuePlaybackIndexMapping] = []
    private var hasMatchedTrackedQueue = false
    private var isInstallingTrackedQueue = false
    private var isAwaitingUnavailableItemSkip = false

    init() {
        synchronizePlayerState()
    }

    private func startObservingPlayer() {
        player.beginGeneratingPlaybackNotifications()

        let center = NotificationCenter.default
        notificationObservers.append(center.addObserver(
            forName: .MPMusicPlayerControllerNowPlayingItemDidChange,
            object: player,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshPlayerState() }
        })
        notificationObservers.append(center.addObserver(
            forName: .MPMusicPlayerControllerPlaybackStateDidChange,
            object: player,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshPlayerState() }
        })
        notificationObservers.append(center.addObserver(
            forName: .MPMusicPlayerControllerQueueDidChange,
            object: player,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleQueueDidChange() }
        })

    }

    deinit {
        let center = NotificationCenter.default
        notificationObservers.forEach(center.removeObserver)
        if !notificationObservers.isEmpty {
            Task { @MainActor in
                MPMusicPlayerController.systemMusicPlayer.endGeneratingPlaybackNotifications()
            }
        }
    }

    func setQueueAndPlay(entries: [PlaylistEntry], queueID: UUID) {
        guard !entries.isEmpty else {
            errorMessage = String(localized: "This playlist has no songs to play.")
            return
        }

        isPreparing = true
        errorMessage = nil
        trackedQueueID = queueID
        trackedQueueMappings = entries.enumerated().map { index, entry in
            GeneratedQueuePlaybackIndexMapping(
                mediaItemPersistentID: entry.mediaItem.persistentID,
                displayPosition: index,
                isVisibleEntry: true
            )
        }
        hasMatchedTrackedQueue = false
        isInstallingTrackedQueue = true
        isAwaitingUnavailableItemSkip = false
        generatedQueueProgress = nil
        generatedQueueInvalidationID = nil
        player.shuffleMode = .off
        player.repeatMode = .none
        player.setQueue(with: MPMediaItemCollection(items: entries.map(\.mediaItem)))

        player.prepareToPlay { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isPreparing = false
                if let error {
                    self.logger.error("Queue preparation failed: \(error.localizedDescription, privacy: .public)")
                    self.errorMessage = String(
                        localized: "Music couldn’t start this queue. A song in it may be unavailable."
                    )
                    self.isInstallingTrackedQueue = false
                    self.isAwaitingUnavailableItemSkip = true
                    self.refreshPlayerState()
                    return
                }
                self.player.play()
                self.refreshPlayerState()
            }
        }
    }

    /// Reattaches live progress after a relaunch only when the system player's
    /// current item and duplicate-safe queue index match the saved order.
    func restoreQueueTracking(
        queueID: UUID,
        mappings: [GeneratedQueuePlaybackIndexMapping]
    ) {
        guard !mappings.isEmpty else {
            return
        }

        trackedQueueID = queueID
        trackedQueueMappings = mappings
        hasMatchedTrackedQueue = false
        isInstallingTrackedQueue = false
        isAwaitingUnavailableItemSkip = false
        generatedQueueProgress = nil
        generatedQueueInvalidationID = nil

        // MediaPlayer can briefly report no current item during cold launch.
        // Keep the saved mapping pending so a later notification or foreground
        // refresh gets another chance to validate it.
        if let item = player.nowPlayingItem {
            refreshGeneratedQueueProgress(with: item)
        }
    }

    /// Refreshes state that may have changed while the app was suspended.
    func synchronizePlayerState() {
        // Reading the player before authorization can bypass the onboarding prompt.
        guard MPMediaLibrary.authorizationStatus() == .authorized else {
            return
        }
        if notificationObservers.isEmpty {
            startObservingPlayer()
        }
        refreshPlayerState()
    }

    /// MediaPlayer does not expose a per-item preparation error. This action
    /// lets the listener move past an unavailable item without rebuilding the
    /// rest of the generated queue.
    func skipUnavailableItemAndContinue() {
        errorMessage = nil
        player.skipToNextItem()
        player.play()
        refreshPlayerState()
    }

    func dismissPlaybackError() {
        errorMessage = nil
        if isAwaitingUnavailableItemSkip {
            clearTrackedQueue(invalidate: true)
        }
    }

    var isPlaying: Bool {
        playbackState == .playing
    }

    func togglePlayPause() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        refreshPlayerState()
    }

    func skipToNextItem() {
        player.skipToNextItem()
        refreshPlayerState()
    }

    /// Matches the Music app: a few seconds into a song, "previous" restarts it.
    func skipToPreviousItem() {
        if player.currentPlaybackTime > 3 {
            player.skipToBeginning()
        } else {
            player.skipToPreviousItem()
        }
        refreshPlayerState()
    }

    var playbackStateDescription: String {
        switch playbackState {
        case .playing: return String(localized: "Playing")
        case .paused: return String(localized: "Paused")
        case .stopped: return String(localized: "Stopped")
        case .interrupted: return String(localized: "Interrupted")
        case .seekingForward: return String(localized: "Seeking forward")
        case .seekingBackward: return String(localized: "Seeking backward")
        @unknown default: return String(localized: "Playback state unavailable")
        }
    }

    private func refreshPlayerState() {
        guard MPMediaLibrary.authorizationStatus() == .authorized else {
            return
        }
        playbackState = player.playbackState
        guard let item = player.nowPlayingItem else {
            nowPlaying = nil
            if playbackState == .stopped, hasMatchedTrackedQueue {
                clearTrackedQueue(invalidate: true)
            }
            return
        }

        nowPlaying = NowPlayingSnapshot(
            title: safeText(item.title, fallback: String(localized: "Unknown Title")),
            artist: safeText(item.artist, fallback: String(localized: "Unknown Artist")),
            artwork: item.artwork
        )
        refreshGeneratedQueueProgress(with: item)
    }

    private func refreshGeneratedQueueProgress(with item: MPMediaItem) {
        guard let trackedQueueID else {
            return
        }

        switch queueMatch(
            for: item,
            in: trackedQueueMappings
        ) {
        case .unavailable:
            return
        case .mismatch:
            if !isInstallingTrackedQueue, !isAwaitingUnavailableItemSkip {
                clearTrackedQueue(invalidate: true)
            }
            return
        case let .match(playerIndex, mapping):
            hasMatchedTrackedQueue = true
            isAwaitingUnavailableItemSkip = false
            if !isPreparing {
                isInstallingTrackedQueue = false
            }
            generatedQueueProgress = GeneratedQueuePlaybackProgress(
                queueID: trackedQueueID,
                playerIndex: playerIndex,
                position: mapping.displayPosition,
                isCurrentEntryVisible: mapping.isVisibleEntry
            )
        }
    }

    private enum QueueMatchResult {
        case unavailable
        case mismatch
        case match(Int, GeneratedQueuePlaybackIndexMapping)
    }

    private func queueMatch(
        for item: MPMediaItem,
        in mappings: [GeneratedQueuePlaybackIndexMapping]
    ) -> QueueMatchResult {
        let playerIndex = player.indexOfNowPlayingItem
        guard playerIndex != NSNotFound else {
            return .unavailable
        }
        guard mappings.indices.contains(playerIndex) else {
            return .mismatch
        }

        guard QueueProgress.matchingPosition(
            playerIndex: playerIndex,
            nowPlayingID: item.persistentID,
            queueIDs: mappings.map(\.mediaItemPersistentID)
        ) != nil else {
            return .mismatch
        }

        return .match(playerIndex, mappings[playerIndex])
    }

    private func handleQueueDidChange() {
        guard trackedQueueID != nil, !isInstallingTrackedQueue else {
            return
        }

        clearTrackedQueue(invalidate: true)
    }

    private func clearTrackedQueue(invalidate: Bool) {
        let invalidatedQueueID = trackedQueueID
        trackedQueueID = nil
        trackedQueueMappings = []
        hasMatchedTrackedQueue = false
        isInstallingTrackedQueue = false
        isAwaitingUnavailableItemSkip = false
        generatedQueueProgress = nil
        if invalidate {
            generatedQueueInvalidationID = invalidatedQueueID
        }
    }

    private func safeText(_ value: String?, fallback: String) -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallback
        }
        return value
    }
}
