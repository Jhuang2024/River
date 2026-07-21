import Foundation

/// Deterministic, platform-independent pseudo random number generator (SplitMix64).
///
/// The engine never uses `SystemRandomNumberGenerator` or standard library shuffle,
/// so the same seed always produces the same shuffle and the same bot mixing
/// decisions on every platform and OS version. State is codable so an in-progress
/// session snapshot reproduces exactly.
public struct SeededRNG: Codable, Equatable, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func nextUInt64() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform integer in `0..<upperBound` using rejection sampling
    /// (no modulo bias, deterministic by construction).
    public mutating func int(upperBound: Int) -> Int {
        precondition(upperBound > 0, "upperBound must be positive")
        let bound = UInt64(upperBound)
        let limit = UInt64.max - (UInt64.max % bound)
        while true {
            let value = nextUInt64()
            if value < limit {
                return Int(value % bound)
            }
        }
    }

    /// Uniform integer in a closed range.
    public mutating func int(in range: ClosedRange<Int>) -> Int {
        return range.lowerBound + int(upperBound: range.upperBound - range.lowerBound + 1)
    }

    /// Uniform double in [0, 1).
    public mutating func double01() -> Double {
        return Double(nextUInt64() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// Deterministic Fisher-Yates shuffle.
    public mutating func shuffle<T>(_ array: inout [T]) {
        guard array.count > 1 else { return }
        var i = array.count - 1
        while i > 0 {
            let j = int(upperBound: i + 1)
            if i != j {
                array.swapAt(i, j)
            }
            i -= 1
        }
    }

    /// Derive an independent stream from this seed without disturbing this generator.
    /// Used to give every hand / bot decision its own reproducible stream.
    public static func derive(seed: UInt64, stream: UInt64) -> SeededRNG {
        var mixer = SeededRNG(seed: seed ^ (stream &* 0x9E37_79B9_7F4A_7C15 &+ 0x2545_F491_4F6C_DD1D))
        _ = mixer.nextUInt64()
        return mixer
    }
}
