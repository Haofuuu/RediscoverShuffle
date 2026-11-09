import Testing
@testable import RediscoverShuffleCore

@Suite("Queue progress")
struct QueueProgressTests {
    @Test("The player index distinguishes duplicate song occurrences")
    func duplicateOccurrencesUsePlayerIndex() {
        let queue = [10, 20, 20, 30]

        #expect(
            QueueProgress.matchingPosition(
                playerIndex: 2,
                nowPlayingID: 20,
                queueIDs: queue
            ) == 2
        )
    }

    @Test("Without Music's index, the occurrence nearest the expected place wins")
    func nearestOccurrenceWhenIndexIsUnknown() {
        let queue = [10, 20, 30, 20, 40]

        #expect(QueueProgress.nearestPosition(of: 20, in: queue, expectedPosition: 0) == 1)
        #expect(QueueProgress.nearestPosition(of: 20, in: queue, expectedPosition: 4) == 3)
        #expect(QueueProgress.nearestPosition(of: 20, in: queue, expectedPosition: 2) == 3)
        #expect(QueueProgress.nearestPosition(of: 40, in: queue, expectedPosition: 0) == 4)
        #expect(QueueProgress.nearestPosition(of: 50, in: queue, expectedPosition: 0) == nil)
    }

    @Test("A mismatched item or invalid index is rejected")
    func invalidSnapshotsAreRejected() {
        let queue = [10, 20, 30]

        #expect(QueueProgress.matchingPosition(playerIndex: 1, nowPlayingID: 30, queueIDs: queue) == nil)
        #expect(QueueProgress.matchingPosition(playerIndex: -1, nowPlayingID: 10, queueIDs: queue) == nil)
        #expect(QueueProgress.matchingPosition(playerIndex: 3, nowPlayingID: 30, queueIDs: queue) == nil)
    }

    @Test("Advancing hides earlier entries without mutating the generated order")
    func advancingProjectsTheRemainingOrder() {
        let generatedOrder = ["first", "second", "third", "fourth"]

        #expect(QueueProgress.remainingItems(in: generatedOrder, from: nil) == generatedOrder)
        #expect(
            QueueProgress.remainingItems(in: generatedOrder, from: 2)
                == ["third", "fourth"]
        )
        #expect(generatedOrder == ["first", "second", "third", "fourth"])
    }

    @Test("Replaying the visible order excludes passed entries and renumbers from one")
    func replayUsesOnlyRemainingOrder() {
        let generatedOrder = ["first", "second", "third", "fourth"]
        let replayedOrder = QueueProgress.remainingItems(in: generatedOrder, from: 2)

        #expect(replayedOrder == ["third", "fourth"])
        #expect(Array(replayedOrder.indices).map { $0 + 1 } == [1, 2])
    }

    @Test("Moving backward restores earlier entries")
    func movingBackwardRestoresEntries() {
        let generatedOrder = [1, 2, 3, 4]

        #expect(QueueProgress.remainingItems(in: generatedOrder, from: 3) == [4])
        #expect(QueueProgress.remainingItems(in: generatedOrder, from: 1) == [2, 3, 4])
    }

    @Test("Saved positions are clamped safely")
    func savedPositionsAreClamped() {
        let generatedOrder = [1, 2, 3]

        #expect(QueueProgress.remainingItems(in: generatedOrder, from: -5) == generatedOrder)
        #expect(QueueProgress.remainingItems(in: generatedOrder, from: 3).isEmpty)
        #expect(QueueProgress.remainingItems(in: generatedOrder, from: 99).isEmpty)
    }

    @Test("Missing restored entries preserve raw player-index alignment")
    func missingEntriesPreservePlayerIndices() {
        let projections = QueueProgress.displayProjections(
            forVisibleEntries: [false, true, false, true]
        )

        #expect(
            projections == [
                QueueProgressProjection(displayPosition: 0, isVisibleEntry: false),
                QueueProgressProjection(displayPosition: 0, isVisibleEntry: true),
                QueueProgressProjection(displayPosition: 1, isVisibleEntry: false),
                QueueProgressProjection(displayPosition: 1, isVisibleEntry: true),
            ]
        )
    }
}
