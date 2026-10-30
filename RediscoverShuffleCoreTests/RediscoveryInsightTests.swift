import Testing
@testable import RediscoverShuffleCore

@Suite("Rediscovery insight")
struct RediscoveryInsightTests {
    @Test("An empty playlist has nothing to rediscover")
    func emptyPlaylist() {
        let insight = RediscoveryInsight(playCounts: [])
        #expect(insight.isEmpty)
        #expect(insight.unplayedCount == 0)
        #expect(insight.overlookedCount == 0)
    }

    @Test("Unplayed songs are counted and classified separately")
    func unplayedSongs() {
        let insight = RediscoveryInsight(playCounts: [0, 0, 12, 40, 41])
        #expect(insight.unplayedCount == 2)
        #expect(insight.freshness(forPlayCount: 0) == .unplayed)
    }

    @Test("Songs played at most a quarter as often as the median are overlooked")
    func overlookedThreshold() {
        // Median of the sorted counts [1, 3, 10, 40, 41, 50, 80] is 40.
        let insight = RediscoveryInsight(playCounts: [40, 1, 50, 3, 80, 10, 41])
        #expect(insight.overlookedCount == 3)
        #expect(insight.freshness(forPlayCount: 10) == .overlooked)
        #expect(insight.freshness(forPlayCount: 11) == .familiar)
        #expect(insight.freshness(forPlayCount: 40) == .familiar)
    }

    @Test("Evenly played playlists have no overlooked songs", arguments: [
        [1, 1, 1, 1],
        [3, 3, 2, 3],
        [100, 120, 90, 110],
    ])
    func evenlyPlayed(counts: [Int]) {
        let insight = RediscoveryInsight(playCounts: counts)
        #expect(insight.overlookedCount == 0)
        #expect(insight.isEmpty)
    }

    @Test("Negative play counts are treated as unplayed")
    func negativeCounts() {
        let insight = RediscoveryInsight(playCounts: [-1, 5, 5])
        #expect(insight.unplayedCount == 1)
        #expect(insight.freshness(forPlayCount: -3) == .unplayed)
    }

    @Test("Duplicate entries each count toward the summary")
    func duplicateEntries() {
        let insight = RediscoveryInsight(playCounts: [0, 0, 2, 2, 20, 20, 20, 20, 20])
        #expect(insight.unplayedCount == 2)
        #expect(insight.overlookedCount == 2)
    }
}
