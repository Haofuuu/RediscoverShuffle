import Foundation

struct QueueProgressProjection: Equatable {
    let displayPosition: Int
    let isVisibleEntry: Bool
}

/// Apple-independent helpers for projecting a generated queue around the
/// system player's current index.
enum QueueProgress {
    static func matchingPosition<ID: Equatable>(
        playerIndex: Int,
        nowPlayingID: ID,
        queueIDs: [ID]
    ) -> Int? {
        guard queueIDs.indices.contains(playerIndex),
              queueIDs[playerIndex] == nowPlayingID else {
            return nil
        }

        return playerIndex
    }

    static func startIndex(savedPosition: Int?, itemCount: Int) -> Int {
        guard let savedPosition else {
            return 0
        }

        return min(max(savedPosition, 0), max(itemCount, 0))
    }

    static func remainingItems<Element>(
        in items: [Element],
        from savedPosition: Int?
    ) -> [Element] {
        Array(items.dropFirst(startIndex(savedPosition: savedPosition, itemCount: items.count)))
    }

    /// Maps raw system-player indices onto a display that may omit library
    /// entries which can no longer be reconstructed after relaunch.
    static func displayProjections(
        forVisibleEntries visibleEntries: [Bool]
    ) -> [QueueProgressProjection] {
        var visiblePosition = 0
        return visibleEntries.map { isVisibleEntry in
            defer {
                if isVisibleEntry {
                    visiblePosition += 1
                }
            }
            return QueueProgressProjection(
                displayPosition: visiblePosition,
                isVisibleEntry: isVisibleEntry
            )
        }
    }
}
