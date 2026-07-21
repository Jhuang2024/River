import Foundation

/// Compact board-texture classification for assistance overlays (§9).
/// Pure derived information - never affects engine behaviour.
public enum BoardTexture {

    public struct Classification: Equatable, Sendable {
        public let paired: Bool
        /// All board cards share one suit (3+ cards).
        public let monotone: Bool
        /// Exactly two suits represented (flush draw possible on the flop).
        public let twoTone: Bool
        /// Three or more ranks packed closely enough for straight draws.
        public let connected: Bool
        /// Convenience: dry = unpaired, not connected, not suited-coordinated.
        public var dry: Bool {
            return !paired && !monotone && !twoTone && !connected
        }
    }

    public static func classify(_ board: [Card]) -> Classification {
        guard board.count >= 3 else {
            return Classification(paired: false, monotone: false, twoTone: false, connected: false)
        }
        var rankCounts: [Int: Int] = [:]
        var suitCounts: [Int: Int] = [:]
        for card in board {
            rankCounts[card.rank.rawValue, default: 0] += 1
            suitCounts[card.suit.rawValue, default: 0] += 1
        }
        let paired = rankCounts.values.contains { $0 >= 2 }
        let monotone = suitCounts.values.contains { $0 >= 3 } && suitCounts.count == 1
        let twoTone = suitCounts.count == 2
        // Connected: any three distinct ranks spanning four or fewer, treating
        // the ace as high and low.
        var ranks = Set(rankCounts.keys)
        if ranks.contains(14) {
            ranks.insert(1)
        }
        let sorted = ranks.sorted()
        var connected = false
        if sorted.count >= 3 {
            for i in 0...(sorted.count - 3) {
                if sorted[i + 2] - sorted[i] <= 4 {
                    connected = true
                    break
                }
            }
        }
        return Classification(paired: paired, monotone: monotone, twoTone: twoTone, connected: connected)
    }

    /// Short labels for the table overlay, e.g. ["Paired", "Two-tone"].
    public static func labels(for board: [Card]) -> [String] {
        let c = classify(board)
        guard board.count >= 3 else { return [] }
        var result: [String] = []
        if c.paired { result.append("Paired") }
        if c.monotone { result.append("Monotone") }
        else if c.twoTone { result.append("Two-tone") }
        if c.connected { result.append("Connected") }
        if c.dry { result.append("Dry") }
        else if !c.dry && (c.connected || c.monotone || c.twoTone) && !c.paired { result.append("Dynamic") }
        return result
    }
}
