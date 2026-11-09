import Combine
import Foundation
import MediaPlayer

/// The order Music was handed before a relaunch, and where its songs sit
/// in Music's queue, so live progress can pick up again.
struct RestoredPlaybackTracking {
    let queueID: UUID
    let mappings: [GeneratedQueuePlaybackIndexMapping]
    /// Where in the order Music was last seen, if known.
    let expectedPosition: Int?
}

/// Keeps the most recently generated queue available across navigation and app
/// launches. Only opaque library identifiers, entry positions, and queue
/// progress are saved; MediaPlayer objects and song metadata stay in memory.
@MainActor
final class GeneratedQueueSession: ObservableObject {
    /// The order Music was handed, which the full player's Up Next follows.
    /// It stays apart from the page that dealt it: a reshuffle there deals a
    /// new order, but Music keeps playing this one until Play is tapped.
    struct PlayingQueue {
        let queueID: UUID
        let playlist: LibraryPlaylist
        let entries: [PlaylistEntry]
    }

    @Published private(set) var lastQueueViewModel: PlaylistViewModel?
    @Published private(set) var playingQueue: PlayingQueue?

    private let store: GeneratedQueueStore
    private var rememberedQueueID: UUID?
    private var submittedQueueID: UUID?
    private var persistedEntries: [StoredGeneratedQueue.Entry] = []
    private var playingEntries: [StoredGeneratedQueue.Entry] = []
    private var lastPlayerIndex: Int?

    init(store: GeneratedQueueStore = GeneratedQueueStore()) {
        self.store = store
    }

    func remember(_ viewModel: PlaylistViewModel) {
        guard !viewModel.generatedOrder.isEmpty else {
            return
        }

        if rememberedQueueID != viewModel.queueID {
            submittedQueueID = nil
            lastPlayerIndex = nil
            persistedEntries = storedEntries(for: viewModel.generatedOrder)
        }
        rememberedQueueID = viewModel.queueID
        lastQueueViewModel = viewModel
        persist(viewModel)
    }

    /// Records that this exact revision was handed to the system player. A
    /// preview-only reshuffle is intentionally not eligible for live progress
    /// reattachment on the next launch.
    func markSubmittedForPlayback(_ viewModel: PlaylistViewModel) {
        guard !viewModel.generatedOrder.isEmpty else {
            return
        }

        viewModel.resetPlaybackPosition()
        rememberedQueueID = viewModel.queueID
        submittedQueueID = viewModel.queueID
        lastPlayerIndex = nil
        persistedEntries = storedEntries(for: viewModel.generatedOrder)
        playingEntries = persistedEntries
        playingQueue = PlayingQueue(
            queueID: viewModel.queueID,
            playlist: viewModel.playlist,
            entries: viewModel.generatedOrder
        )
        lastQueueViewModel = viewModel
        persist(viewModel)
    }

    func invalidatePlaybackTracking(for queueID: UUID) {
        guard submittedQueueID == queueID else {
            return
        }

        submittedQueueID = nil
        playingQueue = nil
        playingEntries = []
        if let viewModel = lastQueueViewModel {
            persist(viewModel)
        }
    }

    /// Removes only Rediscover Shuffle's saved queue and its local progress.
    /// The system Music player and the user's source playlist are untouched.
    @discardableResult
    func clearSavedQueue() -> Bool {
        do {
            try store.clear()
        } catch {
            return false
        }

        lastQueueViewModel = nil
        playingQueue = nil
        rememberedQueueID = nil
        submittedQueueID = nil
        persistedEntries = []
        playingEntries = []
        lastPlayerIndex = nil
        return true
    }

    /// Rebuilds the saved queue from fresh MediaPlayer objects after the music
    /// library has been authorized and loaded. An empty or temporarily missing
    /// playlist list does not erase the saved queue. Returns how to follow
    /// the order Music was last handed, when it may still be playing.
    func restoreIfNeeded(from playlists: [LibraryPlaylist]) -> RestoredPlaybackTracking? {
        guard lastQueueViewModel == nil,
              let storedQueue = store.load(),
              storedQueue.schemaVersion == StoredGeneratedQueue.currentSchemaVersion,
              let playlist = playlists.first(where: {
                  $0.persistentIDString == storedQueue.playlistPersistentID
              }),
              let restored = match(storedQueue.entries, in: playlist) else {
            return nil
        }

        let restoredPosition: Int?
        if let playerIndex = storedQueue.playbackPlayerIndex,
           restored.mappings.indices.contains(playerIndex) {
            restoredPosition = restored.mappings[playerIndex].displayPosition
        } else {
            restoredPosition = restoredPlaybackPosition(
                storedQueue.playbackPosition,
                storedEntryCount: storedQueue.entries.count,
                restoredStoredIndexes: restored.storedIndexes
            )
        }
        let viewModel = PlaylistViewModel(
            playlist: playlist,
            generatedOrder: restored.entries,
            queueID: storedQueue.queueID,
            playbackPosition: restoredPosition
        )
        rememberedQueueID = storedQueue.queueID
        submittedQueueID = storedQueue.submittedQueueID
        persistedEntries = storedQueue.entries
        lastPlayerIndex = storedQueue.playbackPlayerIndex
        lastQueueViewModel = viewModel

        // What Music was last handed: this order, or one saved apart from it
        // when a reshuffle dealt this one afterwards.
        var playbackTracking: RestoredPlaybackTracking?
        if let submittedQueueID = storedQueue.submittedQueueID {
            let playing: (stored: [StoredGeneratedQueue.Entry], queue: MatchedQueue, position: Int?)?
            if submittedQueueID == storedQueue.queueID {
                playing = (storedQueue.entries, restored, storedQueue.playbackPlayerIndex)
            } else if let stored = storedQueue.playingEntries,
                      let queue = match(stored, in: playlist) {
                playing = (stored, queue, nil)
            } else {
                playing = nil
            }
            if let playing {
                playingEntries = playing.stored
                playingQueue = PlayingQueue(
                    queueID: submittedQueueID,
                    playlist: playlist,
                    entries: playing.queue.entries
                )
                playbackTracking = RestoredPlaybackTracking(
                    queueID: submittedQueueID,
                    mappings: playing.queue.mappings,
                    expectedPosition: playing.position
                )
            }
        }
        return playbackTracking
    }

    private struct MatchedQueue {
        let entries: [PlaylistEntry]
        /// Where each matched entry sat in the saved order.
        let storedIndexes: [Int]
        /// One per saved entry, matched or not, as Music's queue holds them all.
        let mappings: [GeneratedQueuePlaybackIndexMapping]
    }

    /// Finds a saved order's songs in the playlist as it is now. Songs that
    /// have left the playlist are skipped, and duplicates keep their places.
    private func match(
        _ storedEntries: [StoredGeneratedQueue.Entry],
        in playlist: LibraryPlaylist
    ) -> MatchedQueue? {
        let persistentIDs = storedEntries.compactMap {
            MPMediaEntityPersistentID($0.mediaItemPersistentID)
        }
        guard persistentIDs.count == storedEntries.count else {
            return nil
        }

        var usedEntryIDs: Set<PlaylistEntryIdentifier> = []
        var matchedEntries = Array<PlaylistEntry?>(
            repeating: nil,
            count: storedEntries.count
        )

        // Reserve exact occurrence matches before any persistent-ID fallback.
        // Otherwise, an early shuffled duplicate can consume the exact match
        // belonging to a later duplicate occurrence.
        for (storedIndex, storedEntry) in storedEntries.enumerated() {
            guard let exactEntry = playlist.entries.first(where: {
                !usedEntryIDs.contains($0.id)
                    && $0.originalIndex == storedEntry.originalIndex
                    && String($0.mediaItem.persistentID) == storedEntry.mediaItemPersistentID
            }) else {
                continue
            }

            matchedEntries[storedIndex] = exactEntry
            usedEntryIDs.insert(exactEntry.id)
        }

        for (storedIndex, storedEntry) in storedEntries.enumerated()
            where matchedEntries[storedIndex] == nil
                && storedEntry.mediaItemPersistentID != "0" {
            guard let fallbackEntry = playlist.entries.first(where: {
                !usedEntryIDs.contains($0.id)
                    && String($0.mediaItem.persistentID) == storedEntry.mediaItemPersistentID
            }) else {
                continue
            }

            matchedEntries[storedIndex] = fallbackEntry
            usedEntryIDs.insert(fallbackEntry.id)
        }

        var entries: [PlaylistEntry] = []
        var storedIndexes: [Int] = []
        let displayProjections = QueueProgress.displayProjections(
            forVisibleEntries: matchedEntries.map { $0 != nil }
        )
        var mappings: [GeneratedQueuePlaybackIndexMapping] = []
        for storedIndex in storedEntries.indices {
            let projection = displayProjections[storedIndex]
            mappings.append(
                GeneratedQueuePlaybackIndexMapping(
                    mediaItemPersistentID: persistentIDs[storedIndex],
                    displayPosition: projection.displayPosition,
                    isVisibleEntry: projection.isVisibleEntry
                )
            )

            if let entry = matchedEntries[storedIndex] {
                entries.append(entry)
                storedIndexes.append(storedIndex)
            }
        }

        guard !entries.isEmpty else {
            return nil
        }
        return MatchedQueue(entries: entries, storedIndexes: storedIndexes, mappings: mappings)
    }

    func updatePlaybackProgress(_ progress: GeneratedQueuePlaybackProgress) {
        guard let viewModel = lastQueueViewModel,
              viewModel.queueID == progress.queueID else {
            return
        }

        let positionChanged = viewModel.updatePlaybackPosition(progress.position)
        let playerIndexChanged = lastPlayerIndex != progress.playerIndex
        guard positionChanged || playerIndexChanged else {
            return
        }

        lastPlayerIndex = progress.playerIndex
        persist(viewModel)
    }

    private func restoredPlaybackPosition(
        _ storedPosition: Int?,
        storedEntryCount: Int,
        restoredStoredIndexes: [Int]
    ) -> Int? {
        guard let storedPosition else {
            return nil
        }
        guard storedPosition < storedEntryCount else {
            return restoredStoredIndexes.count
        }

        if let firstRemainingIndex = restoredStoredIndexes.firstIndex(where: {
            $0 >= storedPosition
        }) {
            return firstRemainingIndex
        }

        return restoredStoredIndexes.count
    }

    private func persist(_ viewModel: PlaylistViewModel) {
        if persistedEntries.isEmpty {
            persistedEntries = storedEntries(for: viewModel.generatedOrder)
        }
        let storedQueue = StoredGeneratedQueue(
            schemaVersion: StoredGeneratedQueue.currentSchemaVersion,
            queueID: viewModel.queueID,
            playlistPersistentID: viewModel.playlist.persistentIDString,
            entries: persistedEntries,
            playbackPosition: viewModel.playbackPosition,
            submittedQueueID: submittedQueueID,
            playbackPlayerIndex: lastPlayerIndex,
            playingEntries: submittedQueueID != nil
                && submittedQueueID != viewModel.queueID
                && !playingEntries.isEmpty ? playingEntries : nil
        )
        store.save(storedQueue)
    }

    private func storedEntries(
        for entries: [PlaylistEntry]
    ) -> [StoredGeneratedQueue.Entry] {
        entries.map {
            StoredGeneratedQueue.Entry(
                originalIndex: $0.originalIndex,
                mediaItemPersistentID: String($0.mediaItem.persistentID)
            )
        }
    }
}
