import Combine
import Foundation

@MainActor
final class PlaylistViewModel: ObservableObject {
    let playlist: LibraryPlaylist
    @Published private(set) var generatedOrder: [PlaylistEntry] = []

    private let shuffleEngine = WeightedShuffleEngine()

    init(playlist: LibraryPlaylist) {
        self.playlist = playlist
    }

    func reshuffle(bias: Double) {
        let candidates = playlist.entries.map {
            ShuffleCandidate(id: $0.id, playCount: $0.playCount, originalIndex: $0.originalIndex)
        }
        let shuffledCandidates = shuffleEngine.permutation(of: candidates, bias: bias)
        let entriesByID = Dictionary(uniqueKeysWithValues: playlist.entries.map { ($0.id, $0) })
        generatedOrder = shuffledCandidates.compactMap { entriesByID[$0.id] }
    }
}
