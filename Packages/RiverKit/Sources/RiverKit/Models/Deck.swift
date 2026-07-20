import Foundation

/// A standard 52 card deck with deterministic seeded shuffling.
public struct Deck: Equatable, Sendable {
    public private(set) var cards: [Card]

    /// Creates an ordered standard deck (no jokers).
    public static func standard() -> [Card] {
        var result: [Card] = []
        result.reserveCapacity(52)
        for rank in Rank.allCases {
            for suit in Suit.allCases {
                result.append(Card(rank, suit))
            }
        }
        return result
    }

    /// A deck shuffled deterministically from the given seed.
    public init(seed: UInt64) {
        var rng = SeededRNG(seed: seed)
        var all = Deck.standard()
        rng.shuffle(&all)
        self.cards = all
    }

    /// A deck with an explicit card order. Used by tests and debug tooling to
    /// rig exact boards; never used by normal gameplay.
    public init(riggedOrder: [Card]) {
        self.cards = riggedOrder
    }

    public var count: Int {
        return cards.count
    }

    /// Deals a single card from the top.
    public mutating func deal() -> Card {
        precondition(!cards.isEmpty, "dealing from an empty deck")
        return cards.removeFirst()
    }

    /// Removes and discards the top card (classic burn before each street).
    public mutating func burn() {
        precondition(!cards.isEmpty, "burning from an empty deck")
        cards.removeFirst()
    }
}
