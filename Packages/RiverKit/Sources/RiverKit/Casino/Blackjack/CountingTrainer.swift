import Foundation

/// Hi-Lo card counting trainer (§6). Purely educational, applies only to the
/// local fictional game; the dealer never reacts to the player's count.
public enum CountingTrainer {

    /// Running count of a card sequence under Hi-Lo.
    public static func runningCount(_ cards: [BlackjackCard]) -> Int {
        return cards.reduce(0) { $0 + $1.hiLoValue }
    }

    /// True count = running count / decks remaining, rounded toward zero.
    /// Decks remaining are rounded to the nearest half deck, floored at one
    /// half so early-shoe counts don't explode.
    public static func trueCount(running: Int, decksRemaining: Double) -> Int {
        let halves = max(1, Int((decksRemaining * 2).rounded()))
        let decks = Double(halves) / 2
        return Int((Double(running) / decks).rounded(.towardZero))
    }

    /// One card-removal drill: a short seeded sequence to count.
    public struct Drill: Hashable, Sendable {
        public let cards: [BlackjackCard]
        public let correctRunningCount: Int
    }

    /// Generates a deterministic drill of `count` cards.
    public static func drill(count: Int, seed: UInt64) -> Drill {
        var deck: [BlackjackCard] = []
        for suit in Suit.allCases {
            for rank in Rank.allCases {
                deck.append(BlackjackCard(rank, suit))
            }
        }
        var rng = SeededRNG(seed: seed)
        rng.shuffle(&deck)
        let cards = Array(deck.prefix(min(count, deck.count)))
        return Drill(cards: cards, correctRunningCount: runningCount(cards))
    }

    /// Full-shoe simulation: deals a seeded shoe in bursts so the player can
    /// practise keeping the count over a whole shoe. Returns cumulative
    /// running counts after each burst for checking answers.
    public struct ShoeSimulation: Hashable, Sendable {
        public let bursts: [[BlackjackCard]]
        public let runningCountAfterBurst: [Int]
        public let finalCount: Int
    }

    public static func shoeSimulation(decks: Int, burstSize: Int, seed: UInt64) -> ShoeSimulation {
        var shoe = BlackjackShoe(decks: decks, penetration: 1.0, seed: seed)
        var bursts: [[BlackjackCard]] = []
        var counts: [Int] = []
        var running = 0
        while shoe.remainingCount > 0 {
            var burst: [BlackjackCard] = []
            for _ in 0..<min(burstSize, shoe.remainingCount) {
                let card = shoe.deal()
                burst.append(card)
                running += card.hiLoValue
            }
            bursts.append(burst)
            counts.append(running)
        }
        return ShoeSimulation(bursts: bursts, runningCountAfterBurst: counts, finalCount: running)
    }
}
