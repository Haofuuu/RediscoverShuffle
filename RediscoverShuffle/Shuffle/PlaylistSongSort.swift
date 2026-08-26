import Foundation

enum PlaylistSongSortOption: String, CaseIterable, Hashable, Identifiable {
    case defaultOrder
    case playsLowToHigh
    case playsHighToLow
    case singers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .defaultOrder: return "Default"
        case .playsLowToHigh: return "Plays: Low to High"
        case .playsHighToLow: return "Plays: High to Low"
        case .singers: return "Singers: A to Z"
        }
    }

    func sorted<Element>(
        _ elements: [Element],
        value: (Element) -> PlaylistSongSortValue
    ) -> [Element] {
        elements.sorted {
            areInIncreasingOrder(value($0), value($1))
        }
    }

    private func areInIncreasingOrder(
        _ left: PlaylistSongSortValue,
        _ right: PlaylistSongSortValue
    ) -> Bool {
        switch self {
        case .defaultOrder:
            return left.originalIndex < right.originalIndex
        case .playsLowToHigh:
            if left.playCount != right.playCount {
                return left.playCount < right.playCount
            }
        case .playsHighToLow:
            if left.playCount != right.playCount {
                return left.playCount > right.playCount
            }
        case .singers:
            let artistComparison = left.artist.localizedStandardCompare(right.artist)
            if artistComparison != .orderedSame {
                return artistComparison == .orderedAscending
            }

            let titleComparison = left.title.localizedStandardCompare(right.title)
            if titleComparison != .orderedSame {
                return titleComparison == .orderedAscending
            }
        }

        return left.originalIndex < right.originalIndex
    }
}

struct PlaylistSongSortValue: Equatable {
    let originalIndex: Int
    let playCount: Int
    let artist: String
    let title: String
}
