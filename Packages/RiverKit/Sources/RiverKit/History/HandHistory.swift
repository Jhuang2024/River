import Foundation

/// Complete, self-contained record of one played hand. Everything the review
/// screen shows is reconstructed from this value; it round-trips through JSON.
public struct HandHistory: Codable, Hashable, Identifiable, Sendable {
    public static let currentSchemaVersion = 1

    public let id: UUID
    public let schemaVersion: Int
    public let date: Date
    public let handNumber: Int
    public let seed: UInt64
    public let smallBlind: Int
    public let bigBlind: Int
    public let ante: Int
    public let buttonIndex: Int
    public let heroSeat: Int
    public let playerNames: [String]
    public let startingStacks: [Int]
    public let events: [HandEvent]
    public let decisions: [DecisionRecord]
    public let board: [Card]
    public let netChips: [Int]

    public init(id: UUID = UUID(), date: Date, heroSeat: Int, playerNames: [String], hand: PokerHand) {
        precondition(hand.isComplete, "history requires a completed hand")
        self.id = id
        self.schemaVersion = HandHistory.currentSchemaVersion
        self.date = date
        self.handNumber = hand.config.handNumber
        self.seed = hand.config.seed
        self.smallBlind = hand.config.smallBlind
        self.bigBlind = hand.config.bigBlind
        self.ante = hand.config.ante
        self.buttonIndex = hand.config.buttonIndex
        self.heroSeat = heroSeat
        self.playerNames = playerNames
        self.startingStacks = hand.config.stacks
        self.events = hand.events
        self.decisions = hand.decisions
        self.board = hand.board
        self.netChips = hand.seats.map { $0.stack - $0.startingStack }
    }

    public var heroNet: Int {
        guard netChips.indices.contains(heroSeat) else { return 0 }
        return netChips[heroSeat]
    }

    /// Total chips that went into the middle.
    public var potSize: Int {
        var total = 0
        for event in events {
            switch event {
            case .wonPot(_, let amount, _, _): total += amount
            case .wonWithoutShowdown(_, let amount): total += amount
            default: break
            }
        }
        return total
    }

    /// Whether the hand reached a showdown.
    public var wentToShowdown: Bool {
        return events.contains { event in
            if case .showedHand = event { return true }
            return false
        }
    }

    /// Seats whose hole cards appear in the event log (dealt or shown).
    public func holeCards(for seat: Int) -> [Card]? {
        for event in events {
            if case .dealtHoleCards(let s, let cards) = event, s == seat {
                return cards
            }
        }
        return nil
    }
}
