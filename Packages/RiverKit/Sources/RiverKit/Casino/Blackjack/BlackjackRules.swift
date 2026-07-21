import Foundation

/// Configurable blackjack rules (§6). Values live in configuration, and the
/// basic-strategy engine reads the SAME configuration, so recommendations
/// always match the table being played.
public struct BlackjackRules: Codable, Hashable, Sendable {
    public static let configVersion = 1

    public var decks: Int
    /// false = dealer stands on soft 17 (S17), true = hits (H17).
    public var dealerHitsSoft17: Bool
    /// Blackjack pays 3:2. Bets must be even so the payout is a whole chip;
    /// no floating-point money anywhere (§6).
    public var blackjackPayoutNumerator: Int
    public var blackjackPayoutDenominator: Int
    public var doubleAfterSplitAllowed: Bool
    /// Maximum simultaneous hands after splitting (4 = resplit twice more).
    public var maxSplitHands: Int
    public var splitAcesOneCardOnly: Bool
    public var surrenderAllowed: Bool
    public var insuranceAllowed: Bool
    public var dealerPeeks: Bool
    /// Fraction of the shoe dealt before a reshuffle is required.
    public var penetration: Double

    public init(
        decks: Int = 6,
        dealerHitsSoft17: Bool = false,
        blackjackPayoutNumerator: Int = 3,
        blackjackPayoutDenominator: Int = 2,
        doubleAfterSplitAllowed: Bool = true,
        maxSplitHands: Int = 4,
        splitAcesOneCardOnly: Bool = true,
        surrenderAllowed: Bool = false,
        insuranceAllowed: Bool = true,
        dealerPeeks: Bool = true,
        penetration: Double = 0.75
    ) {
        self.decks = decks
        self.dealerHitsSoft17 = dealerHitsSoft17
        self.blackjackPayoutNumerator = blackjackPayoutNumerator
        self.blackjackPayoutDenominator = blackjackPayoutDenominator
        self.doubleAfterSplitAllowed = doubleAfterSplitAllowed
        self.maxSplitHands = maxSplitHands
        self.splitAcesOneCardOnly = splitAcesOneCardOnly
        self.surrenderAllowed = surrenderAllowed
        self.insuranceAllowed = insuranceAllowed
        self.dealerPeeks = dealerPeeks
        self.penetration = penetration
    }

    /// The default RIVER table (§6).
    public static let standard = BlackjackRules()

    /// Wager granularity: bets must divide cleanly for the blackjack payout
    /// and insurance (half the bet).
    public var betStep: Int {
        return blackjackPayoutDenominator
    }

    /// Exact 3:2 (or configured) blackjack winnings for a bet.
    public func blackjackWinnings(bet: Int) -> Int {
        precondition(bet % blackjackPayoutDenominator == 0, "bet must be a multiple of \(blackjackPayoutDenominator)")
        return bet * blackjackPayoutNumerator / blackjackPayoutDenominator
    }

    public func validate() -> [String] {
        var problems: [String] = []
        if decks < 1 || decks > 8 { problems.append("decks out of range") }
        if blackjackPayoutNumerator <= blackjackPayoutDenominator { problems.append("blackjack must pay a premium") }
        if blackjackPayoutDenominator < 1 { problems.append("bad payout denominator") }
        if maxSplitHands < 1 || maxSplitHands > 4 { problems.append("maxSplitHands out of range") }
        if penetration < 0.25 || penetration > 0.95 { problems.append("penetration out of range") }
        return problems
    }
}

/// A card in the shoe. Blackjack only cares about rank; suit is kept for
/// display and uses the shared Card type's suits.
public struct BlackjackCard: Codable, Hashable, Sendable {
    public let rank: Rank
    public let suit: Suit

    public init(_ rank: Rank, _ suit: Suit) {
        self.rank = rank
        self.suit = suit
    }

    /// Blackjack point value; aces count as 1 here and totals promote one
    /// ace to 11 when that does not bust (soft totals).
    public var pointValue: Int {
        switch rank {
        case .ace: return 1
        case .ten, .jack, .queen, .king: return 10
        default: return rank.rawValue
        }
    }

    /// Hi-Lo counting value (§6 counting trainer).
    public var hiLoValue: Int {
        switch pointValue {
        case 2...6: return 1
        case 10, 1: return -1
        default: return 0
        }
    }
}

/// Hand totals (§6): hard/soft handled in one place, tested exhaustively.
public enum BlackjackTotal {
    /// (best total ≤ 21 where possible, soft = an ace is counted as 11).
    public static func evaluate(_ cards: [BlackjackCard]) -> (total: Int, isSoft: Bool) {
        var hard = 0
        var aces = 0
        for card in cards {
            hard += card.pointValue
            if card.rank == .ace { aces += 1 }
        }
        if aces > 0 && hard + 10 <= 21 {
            return (hard + 10, true)
        }
        return (hard, false)
    }

    public static func isBlackjack(_ cards: [BlackjackCard]) -> Bool {
        return cards.count == 2 && evaluate(cards).total == 21
    }

    public static func isBust(_ cards: [BlackjackCard]) -> Bool {
        return evaluate(cards).total > 21
    }
}

/// A seeded multi-deck shoe with penetration-based reshuffle (§6). The whole
/// shoe order is fixed by the seed at shuffle time; nothing about play,
/// bankroll or history can change which card comes next (§3).
public struct BlackjackShoe: Codable, Hashable, Sendable {
    public private(set) var cards: [BlackjackCard]
    public private(set) var dealtCount: Int
    public let seed: UInt64
    public let decks: Int
    public let penetration: Double

    public init(decks: Int, penetration: Double, seed: UInt64) {
        self.decks = decks
        self.penetration = penetration
        self.seed = seed
        var built: [BlackjackCard] = []
        for _ in 0..<decks {
            for suit in Suit.allCases {
                for rank in Rank.allCases {
                    built.append(BlackjackCard(rank, suit))
                }
            }
        }
        var rng = SeededRNG(seed: seed)
        rng.shuffle(&built)
        self.cards = built
        self.dealtCount = 0
    }

    /// Test-only: a shoe whose first cards are exactly `orderedPrefix`,
    /// followed by the rest of a seeded shoe (each prefix card consumed
    /// once). Internal so gameplay can never construct rigged shoes.
    init(riggedPrefix: [BlackjackCard], decks: Int, penetration: Double) {
        self.decks = decks
        self.penetration = penetration
        self.seed = 0
        var remaining = BlackjackShoe(decks: decks, penetration: penetration, seed: 1).cards
        for card in riggedPrefix {
            if let index = remaining.firstIndex(of: card) {
                remaining.remove(at: index)
            }
        }
        self.cards = riggedPrefix + remaining
        self.dealtCount = 0
    }

    public var remainingCount: Int {
        return cards.count - dealtCount
    }

    /// Reshuffle happens BETWEEN rounds once the cut card is passed.
    public var needsReshuffle: Bool {
        return Double(dealtCount) >= Double(cards.count) * penetration
    }

    /// Decks remaining, for true-count conversion (round to half decks).
    public var decksRemaining: Double {
        return Double(remainingCount) / 52.0
    }

    public mutating func deal() -> BlackjackCard {
        precondition(dealtCount < cards.count, "shoe exhausted")
        let card = cards[dealtCount]
        dealtCount += 1
        return card
    }
}
