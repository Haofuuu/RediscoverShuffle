import Combine
import Foundation

@MainActor
final class PlaylistViewModel: ObservableObject {
    let playlist: LibraryPlaylist
    @Published private(set) var generatedOrder: [PlaylistEntry] = []
    @Published private(set) var playbackPosition: Int?

    private(set) var queueID: UUID

    private let shuffleEngine = WeightedShuffleEngine()

    init(
        playlist: LibraryPlaylist,
        generatedOrder: [PlaylistEntry] = [],
        queueID: UUID = UUID(),
        playbackPosition: Int? = nil
    ) {
        self.playlist = playlist
        self.generatedOrder = generatedOrder
        self.queueID = queueID
        self.playbackPosition = playbackPosition.map {
            QueueProgress.startIndex(savedPosition: $0, itemCount: generatedOrder.count)
        }
    }

    var visibleGeneratedOrder: [PlaylistEntry] {
        QueueProgress.remainingItems(in: generatedOrder, from: playbackPosition)
    }

    func reshuffle(bias: Double) {
        let candidates = playlist.entries.map {
            ShuffleCandidate(id: $0.id, playCount: $0.playCount, originalIndex: $0.originalIndex)
        }
        let shuffledCandidates = shuffleEngine.permutation(of: candidates, bias: bias)
        let entriesByID = Dictionary(uniqueKeysWithValues: playlist.entries.map { ($0.id, $0) })
        queueID = UUID()
        playbackPosition = nil
        generatedOrder = shuffledCandidates.compactMap { entriesByID[$0.id] }
    }

    /// Promotes the currently visible suffix into a new queue. This makes the
    /// current song position 1 and prevents replaying entries already passed.
    @discardableResult
    func prepareVisibleOrderForPlayback() -> Bool {
        let remainingOrder = visibleGeneratedOrder
        guard !remainingOrder.isEmpty else {
            return false
        }

        queueID = UUID()
        playbackPosition = nil
        generatedOrder = remainingOrder
        return true
    }

    @discardableResult
    func resetPlaybackPosition() -> Bool {
        guard playbackPosition != nil else {
            return false
        }

        playbackPosition = nil
        return true
    }

    @discardableResult
    func updatePlaybackPosition(_ position: Int) -> Bool {
        let normalizedPosition = QueueProgress.startIndex(
            savedPosition: position,
            itemCount: generatedOrder.count
        )
        guard playbackPosition != normalizedPosition else {
            return false
        }

        playbackPosition = normalizedPosition
        return true
    }
}
