import Foundation

/// A single pot layer. The first pot is the main pot; later pots are side pots.
public struct Pot: Codable, Equatable, Sendable {
    public let amount: Int
    /// Seats (indices into the hand's seat array) eligible to win this pot.
    public let eligibleSeats: [Int]

    public init(amount: Int, eligibleSeats: [Int]) {
        self.amount = amount
        self.eligibleSeats = eligibleSeats
    }
}

/// Builds exact main and side pots from total chips committed by every seat.
///
/// Layered algorithm (property-tested for exact chip conservation):
///  1. The single highest committer gets any chips above the second-highest
///     commitment refunded (an uncalled bet).
///  2. Distinct commitment levels of LIVE (unfolded) seats define layers.
///  3. Each layer collects `min(committed, level) - min(committed, prev)` from
///     EVERY seat, so folded players' dead money lands in the right layer.
///  4. A layer's eligible winners are the live seats committed at or above it.
///
/// Every chip committed during the hand ends up in exactly one pot or one
/// refund; the sums always match.
public enum PotBuilder {

    public struct Result: Equatable, Sendable {
        public let pots: [Pot]
        /// Per-seat refund of uncalled bets (usually all zero, or one entry).
        public let refunds: [Int]
    }

    /// - Parameters:
    ///   - committed: total chips committed by each seat over the whole hand
    ///     (blinds, antes and all streets).
    ///   - liveSeats: seats that have not folded.
    public static func build(committed: [Int], liveSeats: Set<Int>) -> Result {
        let n = committed.count
        var adjusted = committed
        var refunds = [Int](repeating: 0, count: n)

        // Refund the uncalled portion of the single highest commitment.
        if n > 1 {
            var topSeat = 0
            for i in 1..<n where adjusted[i] > adjusted[topSeat] {
                topSeat = i
            }
            var second = 0
            for i in 0..<n where i != topSeat {
                second = max(second, adjusted[i])
            }
            if adjusted[topSeat] > second {
                refunds[topSeat] = adjusted[topSeat] - second
                adjusted[topSeat] = second
            }
        }

        var levels = Set<Int>()
        for seat in liveSeats where adjusted[seat] > 0 {
            levels.insert(adjusted[seat])
        }
        let sortedLevels = levels.sorted()

        var pots: [Pot] = []
        var previous = 0
        for level in sortedLevels {
            var amount = 0
            for i in 0..<n {
                amount += max(0, min(adjusted[i], level) - previous)
            }
            let eligible = liveSeats.filter { adjusted[$0] >= level }.sorted()
            if amount > 0 {
                pots.append(Pot(amount: amount, eligibleSeats: eligible))
            }
            previous = level
        }

        // Dead money from folded seats above the top live level joins the last
        // pot (cannot occur under engine invariants, but stay conservative).
        if let maxLevel = sortedLevels.last {
            var residue = 0
            for i in 0..<n {
                residue += max(0, adjusted[i] - maxLevel)
            }
            if residue > 0, let last = pots.last {
                pots[pots.count - 1] = Pot(amount: last.amount + residue, eligibleSeats: last.eligibleSeats)
            }
        }

        return Result(pots: pots, refunds: refunds)
    }
}
