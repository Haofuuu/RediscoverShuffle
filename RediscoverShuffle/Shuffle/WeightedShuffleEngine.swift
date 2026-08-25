import Foundation

/// The Apple-independent value used by the weighted shuffle algorithm.
/// `id` identifies a playlist *entry*, not merely a song, so repeated songs
/// at different playlist positions remain independent candidates.
struct ShuffleCandidate<ID: Hashable>: Equatable {
    let id: ID
    let playCount: Int
    let originalIndex: Int
}

struct WeightedShuffleElement<Candidate> {
    let candidate: Candidate
    let weight: Double
    let key: Double

    fileprivate let inputOffset: Int
}

/// Produces a full weighted-random permutation using exponential random keys.
/// No Apple frameworks or media types are used here, which keeps the math easy
/// to test on any Swift platform.
struct WeightedShuffleEngine {
    static let supportedBiasRange = 0.0 ... 5.0

    static func weight(playCount: Int, bias: Double) -> Double {
        let safePlayCount = max(0, playCount)
        let finiteBias = bias.isFinite ? bias : 0.0
        let safeBias = min(max(finiteBias, supportedBiasRange.lowerBound), supportedBiasRange.upperBound)
        let result = pow(Double(safePlayCount) + 1.0, -safeBias)

        guard result.isFinite, result > 0.0 else {
            return Double.leastNonzeroMagnitude
        }
        return result
    }

    func permutation<ID: Hashable>(
        of candidates: [ShuffleCandidate<ID>],
        bias: Double
    ) -> [ShuffleCandidate<ID>] {
        var generator = SystemRandomNumberGenerator()
        return permutation(of: candidates, bias: bias, using: &generator)
    }

    func permutation<ID: Hashable, Generator: RandomNumberGenerator>(
        of candidates: [ShuffleCandidate<ID>],
        bias: Double,
        using generator: inout Generator
    ) -> [ShuffleCandidate<ID>] {
        keyedPermutation(of: candidates, bias: bias, using: &generator).map(\.candidate)
    }

    /// Internal so unit tests can verify the mathematical properties without
    /// relying on flaky statistical assertions.
    func keyedPermutation<ID: Hashable, Generator: RandomNumberGenerator>(
        of candidates: [ShuffleCandidate<ID>],
        bias: Double,
        using generator: inout Generator
    ) -> [WeightedShuffleElement<ShuffleCandidate<ID>>] {
        candidates.enumerated().map { inputOffset, candidate in
            let candidateWeight = Self.weight(playCount: candidate.playCount, bias: bias)
            let uniformValue = Self.openUnitIntervalValue(using: &generator)
            var key = -log(uniformValue) / candidateWeight

            if !key.isFinite || key < 0.0 {
                key = Double.greatestFiniteMagnitude
            }

            return WeightedShuffleElement(
                candidate: candidate,
                weight: candidateWeight,
                key: key,
                inputOffset: inputOffset
            )
        }
        .sorted { left, right in
            if left.key == right.key {
                return left.inputOffset < right.inputOffset
            }
            return left.key < right.key
        }
    }

    private static func openUnitIntervalValue<Generator: RandomNumberGenerator>(
        using generator: inout Generator
    ) -> Double {
        let rawValue = generator.next()
        let denominator = Double(UInt64.max)
        var value = (Double(rawValue) + 0.5) / denominator

        if !value.isFinite || value <= 0.0 {
            value = Double.leastNonzeroMagnitude
        } else if value >= 1.0 {
            value = 1.0 - Double.ulpOfOne
        }
        return value
    }
}
