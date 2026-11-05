import Combine
import Foundation
import MediaPlayer

struct RestoredGeneratedQueue {
    let viewModel: PlaylistViewModel
    let playbackIndexMappings: [GeneratedQueuePlaybackIndexMapping]
}

/// Keeps the most recently generated queue available across navigation and app
/// launches. Only opaque library identifiers, entry positions, and queue
/// progress are saved; MediaPlayer objects and song metadata stay in memory.
@MainActor
final class GeneratedQueueSession: ObservableObject {
    @Published private(set) var lastQueueViewModel: PlaylistViewModel?

    private let store: GeneratedQueueStore
    private var rememberedQueueID: UUID?
    private var submittedQueueID: UUID?
    private var persistedEntries: [StoredGeneratedQueue.Entry] = []
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
        lastQueueViewModel = viewModel
        persist(viewModel)
    }

    func shouldRestorePlaybackTracking(for queueID: UUID) -> Bool {
        submittedQueueID == queueID
    }

    func invalidatePlaybackTracking(for queueID: UUID) {
        guard submittedQueueID == queueID,
              let viewModel = lastQueueViewModel else {
            return
        }

        submittedQueueID = nil
        persist(viewModel)
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
        rememberedQueueID = nil
        submittedQueueID = nil
        persistedEntries = []
        lastPlayerIndex = nil
        return true
    }

    /// Rebuilds the saved queue from fresh MediaPlayer objects after the music
    /// library has been authorized and loaded. An empty or temporarily missing
    /// playlist list does not erase the saved queue.
    func restoreIfNeeded(from playlists: [LibraryPlaylist]) -> RestoredGeneratedQueue? {
        guard lastQueueViewModel == nil,
              let storedQueue = store.load(),
              storedQueue.schemaVersion == StoredGeneratedQueue.currentSchemaVersion,
              let playlist = playlists.first(where: {
                  $0.persistentIDString == storedQueue.playlistPersistentID
              }) else {
            return nil
        }

        let persistentIDs = storedQueue.entries.compactMap {
            MPMediaEntityPersistentID($0.mediaItemPersistentID)
        }
        guard persistentIDs.count == storedQueue.entries.count else {
            return nil
        }

        var usedEntryIDs: Set<PlaylistEntryIdentifier> = []
        var matchedEntries = Array<PlaylistEntry?>(
            repeating: nil,
            count: storedQueue.entries.count
        )

        // Reserve exact occurrence matches before any persistent-ID fallback.
        // Otherwise, an early shuffled duplicate can consume the exact match
        // belonging to a later duplicate occurrence.
        for (storedIndex, storedEntry) in storedQueue.entries.enumerated() {
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

        for (storedIndex, storedEntry) in storedQueue.entries.enumerated()
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

        var restoredEntries: [PlaylistEntry] = []
        var restoredStoredIndexes: [Int] = []
        let displayProjections = QueueProgress.displayProjections(
            forVisibleEntries: matchedEntries.map { $0 != nil }
        )
        var playbackIndexMappings: [GeneratedQueuePlaybackIndexMapping] = []
        for storedIndex in storedQueue.entries.indices {
            let entry = matchedEntries[storedIndex]
            let projection = displayProjections[storedIndex]
            playbackIndexMappings.append(
                GeneratedQueuePlaybackIndexMapping(
                    mediaItemPersistentID: persistentIDs[storedIndex],
                    displayPosition: projection.displayPosition,
                    isVisibleEntry: projection.isVisibleEntry
                )
            )

            if let entry {
                restoredEntries.append(entry)
                restoredStoredIndexes.append(storedIndex)
            }
        }

        guard !restoredEntries.isEmpty else {
            return nil
        }

        let restoredPosition: Int?
        if let playerIndex = storedQueue.playbackPlayerIndex,
           playbackIndexMappings.indices.contains(playerIndex) {
            restoredPosition = playbackIndexMappings[playerIndex].displayPosition
        } else {
            restoredPosition = restoredPlaybackPosition(
                storedQueue.playbackPosition,
                storedEntryCount: storedQueue.entries.count,
                restoredStoredIndexes: restoredStoredIndexes
            )
        }
        let viewModel = PlaylistViewModel(
            playlist: playlist,
            generatedOrder: restoredEntries,
            queueID: storedQueue.queueID,
            playbackPosition: restoredPosition
        )
        rememberedQueueID = storedQueue.queueID
        submittedQueueID = storedQueue.submittedQueueID
        persistedEntries = storedQueue.entries
        lastPlayerIndex = storedQueue.playbackPlayerIndex
        lastQueueViewModel = viewModel
        return RestoredGeneratedQueue(
            viewModel: viewModel,
            playbackIndexMappings: playbackIndexMappings
        )
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
            playbackPlayerIndex: lastPlayerIndex
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
