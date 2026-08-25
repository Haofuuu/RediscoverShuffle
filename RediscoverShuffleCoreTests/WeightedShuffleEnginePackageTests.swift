import Testing
@testable import RediscoverShuffleCore

@Suite("Weighted shuffle engine")
struct WeightedShuffleEnginePackageTests {
    private let engine = WeightedShuffleEngine()

    @Test("Empty input returns empty output")
    func emptyInput() {
        var generator = PackageSequenceGenerator(values: [1])
        let result: [ShuffleCandidate<String>] = engine.permutation(of: [], bias: 0.8, using: &generator)
        #expect(result.isEmpty)
    }

    @Test("One item returns that item")
    func oneItem() {
        let item = ShuffleCandidate(id: "only", playCount: 42, originalIndex: 0)
        var generator = PackageSequenceGenerator(values: [123])
        #expect(engine.permutation(of: [item], bias: 5.0, using: &generator) == [item])
    }

    @Test("Every entry appears exactly once")
    func everyEntryOnce() {
        let candidates = makeCandidates(count: 25)
        var generator = PackageSeededGenerator(seed: 9)
        let result = engine.permutation(of: candidates, bias: 0.8, using: &generator)
        #expect(result.count == candidates.count)
        #expect(Set(result.map(\.id)) == Set(candidates.map(\.id)))
    }

    @Test("No entries are duplicated or omitted")
    func noDuplicatesOrOmissions() {
        let candidates = makeCandidates(count: 40)
        var generator = PackageSeededGenerator(seed: 83)
        let result = engine.permutation(of: candidates, bias: 1.4, using: &generator)
        let counts = Dictionary(grouping: result, by: \.id).mapValues(\.count)
        #expect(counts.count == candidates.count)
        #expect(counts.values.allSatisfy { $0 == 1 })
    }

    @Test("Repeated songs at distinct positions remain distinct")
    func duplicateSongPositions() {
        let first = ShuffleCandidate(id: "song-position-0", playCount: 3, originalIndex: 0)
        let second = ShuffleCandidate(id: "song-position-8", playCount: 3, originalIndex: 8)
        var generator = PackageSeededGenerator(seed: 4)
        let result = engine.permutation(of: [first, second], bias: 1.0, using: &generator)
        #expect(result.count == 2)
        #expect(Set(result.map(\.id)) == Set([first.id, second.id]))
        #expect(Set(result.map(\.originalIndex)) == Set([0, 8]))
    }

    @Test("Bias zero gives equal weights")
    func zeroBiasWeights() {
        for playCount in [0, 1, 10, 1_000, Int.max] {
            #expect(WeightedShuffleEngine.weight(playCount: playCount, bias: 0.0) == 1.0)
        }
    }

    @Test("Higher play counts have lower positive-bias weights")
    func weightOrdering() {
        let unplayed = WeightedShuffleEngine.weight(playCount: 0, bias: 1.0)
        let occasional = WeightedShuffleEngine.weight(playCount: 5, bias: 1.0)
        let frequent = WeightedShuffleEngine.weight(playCount: 100, bias: 1.0)
        #expect(unplayed > occasional)
        #expect(occasional > frequent)
    }

    @Test("Zero-play entries have valid weights")
    func zeroPlayWeight() {
        for bias in 0 ... 5 {
            let weight = WeightedShuffleEngine.weight(playCount: 0, bias: Double(bias))
            #expect(weight == 1.0)
            #expect(weight.isFinite)
            #expect(weight > 0.0)
        }
    }

    @Test("Keys are finite for valid input")
    func finiteKeys() {
        var generator = PackageSequenceGenerator(
            values: [0, 1, UInt64.max / 2, UInt64.max - 1, UInt64.max]
        )
        let ranked = engine.keyedPermutation(of: makeCandidates(count: 5), bias: 5.0, using: &generator)
        #expect(ranked.count == 5)
        #expect(ranked.allSatisfy { $0.key.isFinite && $0.key >= 0.0 })
        #expect(ranked.allSatisfy { $0.weight.isFinite && $0.weight > 0.0 })
    }

    @Test("Supported bias range is zero through five")
    func supportedBiasRange() {
        #expect(WeightedShuffleEngine.supportedBiasRange.lowerBound == 0.0)
        #expect(WeightedShuffleEngine.supportedBiasRange.upperBound == 5.0)
    }

    @Test("Seeded output is deterministic")
    func deterministicOutput() {
        let candidates = makeCandidates(count: 30)
        var first = PackageSeededGenerator(seed: 0xC0FFEE)
        var second = PackageSeededGenerator(seed: 0xC0FFEE)
        #expect(
            engine.permutation(of: candidates, bias: 0.8, using: &first)
                == engine.permutation(of: candidates, bias: 0.8, using: &second)
        )
    }

    @Test("Input is not mutated")
    func inputNotMutated() {
        let candidates = makeCandidates(count: 12)
        let original = candidates
        var generator = PackageSeededGenerator(seed: 100)
        _ = engine.permutation(of: candidates, bias: 1.7, using: &generator)
        #expect(candidates == original)
    }

    private func makeCandidates(count: Int) -> [ShuffleCandidate<Int>] {
        (0 ..< count).map {
            ShuffleCandidate(id: $0, playCount: $0 * 3, originalIndex: $0)
        }
    }
}

private struct PackageSequenceGenerator: RandomNumberGenerator {
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

private struct PackageSeededGenerator: RandomNumberGenerator {
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
