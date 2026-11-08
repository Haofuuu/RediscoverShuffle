import Foundation

/// How a song's play count compares with the rest of its playlist.
enum PlayFreshness: Equatable {
    case unplayed
    case overlooked
    case familiar
}

/// Apple-independent summary of how much of a playlist is waiting to be
/// rediscovered. A song is overlooked when it has been played, but no more
/// than a quarter as often as the playlist's median song.
struct RediscoveryInsight: Equatable {
    let unplayedCount: Int
    let overlookedCount: Int

    private let medianPlayCount: Int

    init(playCounts: [Int]) {
        let counts = playCounts.map { max(0, $0) }.sorted()
        medianPlayCount = counts.isEmpty ? 0 : counts[(counts.count - 1) / 2]
        unplayedCount = counts.prefix { $0 == 0 }.count

        let median = medianPlayCount
        overlookedCount = counts.count {
            $0 > 0 && $0 * 4 <= median
        }
    }

    var isEmpty: Bool {
        unplayedCount == 0 && overlookedCount == 0
    }

    func freshness(forPlayCount playCount: Int) -> PlayFreshness {
        if playCount <= 0 {
            return .unplayed
        }
        if playCount * 4 <= medianPlayCount {
            return .overlooked
        }
        return .familiar
    }
}
