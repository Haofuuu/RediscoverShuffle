import XCTest

#if SWIFT_PACKAGE
@testable import RediscoverShuffleCore
#else
@testable import RediscoverShuffle
#endif

final class WeightedShuffleEngineTests: XCTestCase {
    private let engine = WeightedShuffleEngine()

    func testEmptyInputReturnsEmptyOutput() {
        var generator = SequenceRandomNumberGenerator(values: [1])
        let result: [ShuffleCandidate<String>] = engine.permutation(of: [], bias: 0.8, using: &generator)
        XCTAssertTrue(result.isEmpty)
    }

    func testOneItemInputReturnsThatItem() {
        let item = ShuffleCandidate(id: "only", playCount: 42, originalIndex: 0)
        var generator = SequenceRandomNumberGenerator(values: [123])
        XCTAssertEqual(engine.permutation(of: [item], bias: 5.0, using: &generator), [item])
    }

    func testEveryInputEntryAppearsExactlyOnce() {
        let candidates = makeCandidates(count: 25)
        var generator = SeededRandomNumberGenerator(seed: 9)
        let result = engine.permutation(of: candidates, bias: 0.8, using: &generator)

        XCTAssertEqual(result.count, candidates.count)
        XCTAssertEqual(Set(result.map(\.id)), Set(candidates.map(\.id)))
    }

    func testNoEntriesAreDuplicatedOrOmitted() {
        let candidates = makeCandidates(count: 40)
        var generator = SeededRandomNumberGenerator(seed: 83)
        let result = engine.permutation(of: candidates, bias: 1.4, using: &generator)
        let counts = Dictionary(grouping: result, by: \.id).mapValues(\.count)

        XCTAssertEqual(counts.count, candidates.count)
        XCTAssertTrue(counts.values.allSatisfy { $0 == 1 })
    }

    func testDuplicateSongsAtDifferentPlaylistPositionsRemainSeparate() {
        let repeatedSongAtStart = ShuffleCandidate(id: "same-song-position-0", playCount: 3, originalIndex: 0)
        let repeatedSongAtEnd = ShuffleCandidate(id: "same-song-position-8", playCount: 3, originalIndex: 8)
        var generator = SeededRandomNumberGenerator(seed: 4)

        let result = engine.permutation(
            of: [repeatedSongAtStart, repeatedSongAtEnd],
            bias: 1.0,
            using: &generator
        )

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(Set(result.map(\.id)), Set([repeatedSongAtStart.id, repeatedSongAtEnd.id]))
        XCTAssertEqual(Set(result.map(\.originalIndex)), Set([0, 8]))
    }

    func testBiasZeroGivesEveryCandidateEqualWeight() {
        for playCount in [0, 1, 10, 1_000, Int.max] {
            XCTAssertEqual(WeightedShuffleEngine.weight(playCount: playCount, bias: 0.0), 1.0)
        }
    }

    func testHigherPlayCountsProduceLowerWeightsWhenBiasIsPositive() {
        let unplayedWeight = WeightedShuffleEngine.weight(playCount: 0, bias: 1.0)
        let occasionalWeight = WeightedShuffleEngine.weight(playCount: 5, bias: 1.0)
        let frequentWeight = WeightedShuffleEngine.weight(playCount: 100, bias: 1.0)

        XCTAssertGreaterThan(unplayedWeight, occasionalWeight)
        XCTAssertGreaterThan(occasionalWeight, frequentWeight)
    }

    func testZeroPlaySongsProduceValidWeights() {
        for bias in 0 ... 5 {
            let weight = WeightedShuffleEngine.weight(playCount: 0, bias: Double(bias))
            XCTAssertEqual(weight, 1.0)
            XCTAssertTrue(weight.isFinite)
            XCTAssertGreaterThan(weight, 0.0)
        }
    }

    func testAlgorithmProducesFiniteKeysForValidInput() {
        let candidates = makeCandidates(count: 5)
        var generator = SequenceRandomNumberGenerator(
            values: [0, 1, UInt64.max / 2, UInt64.max - 1, UInt64.max]
        )

        let ranked = engine.keyedPermutation(of: candidates, bias: 5.0, using: &generator)

        XCTAssertEqual(ranked.count, candidates.count)
        XCTAssertTrue(ranked.allSatisfy { $0.key.isFinite && $0.key >= 0.0 })
        XCTAssertTrue(ranked.allSatisfy { $0.weight.isFinite && $0.weight > 0.0 })
    }

    func testSupportedBiasRangeIsZeroThroughFive() {
        XCTAssertEqual(WeightedShuffleEngine.supportedBiasRange.lowerBound, 0.0)
        XCTAssertEqual(WeightedShuffleEngine.supportedBiasRange.upperBound, 5.0)
    }

    func testSeededRandomnessIsDeterministic() {
        let candidates = makeCandidates(count: 30)
        var firstGenerator = SeededRandomNumberGenerator(seed: 0xC0FFEE)
        var secondGenerator = SeededRandomNumberGenerator(seed: 0xC0FFEE)

        let first = engine.permutation(of: candidates, bias: 0.8, using: &firstGenerator)
        let second = engine.permutation(of: candidates, bias: 0.8, using: &secondGenerator)

        XCTAssertEqual(first, second)
    }

    func testOriginalInputArrayIsNotMutated() {
        let candidates = makeCandidates(count: 12)
        let originalSnapshot = candidates
        var generator = SeededRandomNumberGenerator(seed: 100)

        _ = engine.permutation(of: candidates, bias: 1.7, using: &generator)

        XCTAssertEqual(candidates, originalSnapshot)
    }

    private func makeCandidates(count: Int) -> [ShuffleCandidate<Int>] {
        (0 ..< count).map {
            ShuffleCandidate(id: $0, playCount: $0 * 3, originalIndex: $0)
        }
    }
}

private struct SequenceRandomNumberGenerator: RandomNumberGenerator {
    let values: [UInt64]
    private var index = 0

    init(values: [UInt64]) {
        self.values = values
    }

    mutating func next() -> UInt64 {
        guard !values.isEmpty else { return 0 }
        defer { index += 1 }
        return values[index % values.count]
    }
}

private struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}
