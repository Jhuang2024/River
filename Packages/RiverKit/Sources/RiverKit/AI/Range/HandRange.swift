import Foundation

/// An unordered pair of hole cards - one exact Hold'em starting combination.
/// There are exactly 1,326 of these. Blocker and flush logic operates on
/// exact combinations, never on canonical labels alone (§4).
public struct HoleCombo: Hashable, Codable, Sendable, CustomStringConvertible {
    /// Stored with the higher-ranked card first (ties broken by suit) so each
    /// unordered pair has one canonical representation.
    public let first: Card
    public let second: Card

    public init(_ a: Card, _ b: Card) {
        precondition(a != b, "a combination needs two different cards")
        if (a.rank.rawValue, a.suit.rawValue) >= (b.rank.rawValue, b.suit.rawValue) {
            self.first = a
            self.second = b
        } else {
            self.first = b
            self.second = a
        }
    }

    public var cards: [Card] {
        return [first, second]
    }

    public var isPair: Bool {
        return first.rank == second.rank
    }

    public var isSuited: Bool {
        return first.suit == second.suit
    }

    public func contains(_ card: Card) -> Bool {
        return first == card || second == card
    }

    /// Canonical label: "AA", "AKs", "T9o".
    public var label: String {
        if isPair {
            return first.rank.shortSymbol + second.rank.shortSymbol
        }
        return first.rank.shortSymbol + second.rank.shortSymbol + (isSuited ? "s" : "o")
    }

    public var description: String {
        return "\(first)\(second)"
    }

    /// All 1,326 combinations.
    public static let all: [HoleCombo] = {
        let deck = Deck.standard()
        var result: [HoleCombo] = []
        result.reserveCapacity(1326)
        for i in 0..<deck.count {
            for j in (i + 1)..<deck.count {
                result.append(HoleCombo(deck[i], deck[j]))
            }
        }
        return result
    }()

    /// The exact combinations for a canonical label ("AKs" → 4, "AKo" → 12,
    /// "AA" → 6). Returns [] for malformed labels.
    public static func combos(forLabel label: String) -> [HoleCombo] {
        let chars = Array(label)
        guard chars.count == 2 || chars.count == 3 else { return [] }
        func rank(_ c: Character) -> Rank? {
            switch c {
            case "A": return .ace
            case "K": return .king
            case "Q": return .queen
            case "J": return .jack
            case "T": return .ten
            case "9": return .nine
            case "8": return .eight
            case "7": return .seven
            case "6": return .six
            case "5": return .five
            case "4": return .four
            case "3": return .three
            case "2": return .two
            default: return nil
            }
        }
        guard let hi = rank(chars[0]), let lo = rank(chars[1]) else { return [] }
        if chars.count == 2 {
            guard hi == lo else { return [] }
            var result: [HoleCombo] = []
            for a in 0..<4 {
                for b in (a + 1)..<4 {
                    result.append(HoleCombo(Card(hi, Suit(rawValue: a)!), Card(lo, Suit(rawValue: b)!)))
                }
            }
            return result
        }
        guard hi != lo else { return [] }
        var result: [HoleCombo] = []
        if chars[2] == "s" {
            for s in 0..<4 {
                result.append(HoleCombo(Card(hi, Suit(rawValue: s)!), Card(lo, Suit(rawValue: s)!)))
            }
        } else if chars[2] == "o" {
            for a in 0..<4 {
                for b in 0..<4 where a != b {
                    result.append(HoleCombo(Card(hi, Suit(rawValue: a)!), Card(lo, Suit(rawValue: b)!)))
                }
            }
        }
        return result
    }
}

/// A weighted range over exact combinations: each combo carries a frequency
/// weight in 0...1. Supports removal, normalization, sampling and merging (§4).
public struct HandRange: Sendable, Equatable {
    /// Weight per combination; combos absent from the map have weight 0.
    public private(set) var weights: [HoleCombo: Double]

    public init() {
        self.weights = [:]
    }

    public init(weights: [HoleCombo: Double]) {
        self.weights = weights.filter { $0.value > 0 }
    }

    /// A uniform range over every combination not blocked by `excluding`.
    public static func uniform(excluding dead: Set<Card> = []) -> HandRange {
        var weights: [HoleCombo: Double] = [:]
        for combo in HoleCombo.all where !combo.contains(any: dead) {
            weights[combo] = 1
        }
        return HandRange(weights: weights)
    }

    /// Builds a range from canonical labels with per-label weights.
    public static func fromLabels(_ labels: [String: Double]) -> HandRange {
        var weights: [HoleCombo: Double] = [:]
        for (label, weight) in labels {
            guard weight > 0 else { continue }
            for combo in HoleCombo.combos(forLabel: label) {
                weights[combo] = min(1, max(0, weight))
            }
        }
        return HandRange(weights: weights)
    }

    public var isEmpty: Bool {
        return weights.isEmpty
    }

    /// Total weighted combinations (e.g. all AA at weight 0.5 counts as 3).
    public var comboCount: Double {
        return weights.values.reduce(0, +)
    }

    public func weight(of combo: HoleCombo) -> Double {
        return weights[combo] ?? 0
    }

    public mutating func set(_ combo: HoleCombo, weight: Double) {
        if weight > 0 {
            weights[combo] = min(1, weight)
        } else {
            weights.removeValue(forKey: combo)
        }
    }

    /// Multiplies a combo's weight (used by posterior updates).
    public mutating func scale(_ combo: HoleCombo, by factor: Double) {
        if let current = weights[combo] {
            let updated = current * factor
            if updated > 0 {
                weights[combo] = updated
            } else {
                weights.removeValue(forKey: combo)
            }
        }
    }

    /// Removes every combination containing any dead card (board or known
    /// hole cards).
    public mutating func removeCombos(containing dead: Set<Card>) {
        guard !dead.isEmpty else { return }
        weights = weights.filter { !$0.key.contains(any: dead) }
    }

    public func removingCombos(containing dead: Set<Card>) -> HandRange {
        var copy = self
        copy.removeCombos(containing: dead)
        return copy
    }

    /// Rescales the maximum weight to 1 (relative normalization keeps ratios).
    public mutating func normalize() {
        guard let maxWeight = weights.values.max(), maxWeight > 0 else { return }
        for key in weights.keys {
            weights[key]! /= maxWeight
        }
    }

    /// Applies a floor so no surviving combo collapses to zero (§15). The
    /// floor is relative to the maximum weight.
    public mutating func applyFloor(_ relativeFloor: Double) {
        guard let maxWeight = weights.values.max(), maxWeight > 0 else { return }
        let floorValue = maxWeight * relativeFloor
        for key in weights.keys where weights[key]! < floorValue {
            weights[key] = floorValue
        }
    }

    /// Deterministically samples one combination proportionally to weight,
    /// avoiding the given dead cards. Returns nil if nothing is available.
    public func sample(excluding dead: Set<Card>, rng: inout SeededRNG) -> HoleCombo? {
        // Deterministic iteration order: sort by combo identity.
        var total = 0.0
        var eligible: [(HoleCombo, Double)] = []
        for (combo, weight) in weights where !combo.contains(any: dead) {
            eligible.append((combo, weight))
            total += weight
        }
        guard total > 0 else { return nil }
        eligible.sort { lhs, rhs in
            if lhs.0.first != rhs.0.first { return lhs.0.first < rhs.0.first }
            return lhs.0.second < rhs.0.second
        }
        var target = rng.double01() * total
        for (combo, weight) in eligible {
            target -= weight
            if target <= 0 {
                return combo
            }
        }
        return eligible.last?.0
    }

    /// Merge keeping the maximum weight per combo.
    public func merged(with other: HandRange) -> HandRange {
        var result = weights
        for (combo, weight) in other.weights {
            result[combo] = max(result[combo] ?? 0, weight)
        }
        return HandRange(weights: result)
    }

    public func filtered(_ isIncluded: (HoleCombo, Double) -> Bool) -> HandRange {
        return HandRange(weights: weights.filter { isIncluded($0.key, $0.value) })
    }
}

extension HoleCombo {
    public func contains(any cards: Set<Card>) -> Bool {
        return cards.contains(first) || cards.contains(second)
    }
}

/// The 169 canonical starting hands ordered strongest first by heads-up
/// all-in equity against a random hand (computed offline with the validated
/// evaluator; 20,000 trials per hand, fixed seed).
public enum HandOrdering {
    public static let byEquityVsRandom: [String] = [
        "AA", "KK", "QQ", "JJ", "TT", "99", "88", "AKs", "77", "AQs", "AKo", "AJs", "ATs",
        "AQo", "AJo", "KQs", "66", "KJs", "ATo", "A9s", "A7s", "KTs", "A8s", "KQo", "A9o", "55",
        "KJo", "QJs", "A8o", "K9s", "KTo", "A6s", "QTs", "A5s", "A3s", "A7o", "A4s", "K8s", "QJo",
        "K9o", "K7s", "A5o", "A2s", "Q9s", "JTs", "QTo", "K6s", "A6o", "44", "A4o", "K5s", "Q8s",
        "J9s", "K8o", "Q9o", "A3o", "JTo", "A2o", "K7o", "Q7s", "K4s", "T9s", "K6o", "J8s", "33",
        "K3s", "Q8o", "Q6s", "J9o", "K5o", "K2s", "Q5s", "K4o", "Q4s", "J7s", "T8s", "Q7o", "Q3s",
        "J8o", "K3o", "T9o", "T7s", "98s", "Q6o", "J5s", "J6s", "22", "Q2s", "K2o", "Q5o", "97s",
        "T8o", "J7o", "Q4o", "J4s", "T6s", "J6o", "J3s", "Q3o", "98o", "J2s", "T7o", "T5s", "J5o",
        "87s", "96s", "Q2o", "J4o", "97o", "T6o", "T4s", "86s", "95s", "T3s", "87o", "76s", "T2s",
        "J2o", "J3o", "94s", "T5o", "85s", "96o", "75s", "T4o", "65s", "86o", "93s", "76o", "84s",
        "92s", "95o", "T3o", "74s", "T2o", "54s", "64s", "94o", "85o", "73s", "83s", "75o", "93o",
        "82s", "63s", "92o", "53s", "84o", "65o", "54o", "72s", "64o", "74o", "43s", "52s", "83o",
        "62s", "73o", "82o", "42s", "53o", "63o", "32s", "43o", "52o", "72o", "62o", "42o", "32o"
    ]

    /// Number of exact combinations for a canonical label.
    public static func comboCount(for label: String) -> Int {
        if label.count == 2 { return 6 }
        return label.hasSuffix("s") ? 4 : 12
    }

    /// A range containing roughly the top `percent` (0...1) of all 1,326
    /// combinations, taking hands in equity order. The boundary hand is
    /// included at a fractional weight so range sizes vary smoothly.
    public static func topPercentRange(_ percent: Double) -> HandRange {
        let target = max(0, min(1, percent)) * 1326.0
        var taken = 0.0
        var labels: [String: Double] = [:]
        for label in byEquityVsRandom {
            if taken >= target { break }
            let count = Double(comboCount(for: label))
            let remaining = target - taken
            if remaining >= count {
                labels[label] = 1
                taken += count
            } else {
                labels[label] = remaining / count
                taken = target
            }
        }
        return HandRange.fromLabels(labels)
    }

    /// Percentile (0 = strongest) of a canonical label in the ordering, by
    /// cumulative combination count.
    public static func percentile(of label: String) -> Double {
        var cumulative = 0.0
        for candidate in byEquityVsRandom {
            let count = Double(comboCount(for: candidate))
            if candidate == label {
                return (cumulative + count / 2) / 1326.0
            }
            cumulative += count
        }
        return 1
    }

    public static func percentile(of combo: HoleCombo) -> Double {
        return percentile(of: combo.label)
    }
}
