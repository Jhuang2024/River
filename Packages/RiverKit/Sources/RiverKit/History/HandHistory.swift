import Foundation

/// Complete, self-contained record of one played hand. Everything the review
/// screen shows is reconstructed from this value; it round-trips through JSON.
public struct HandHistory: Codable, Hashable, Identifiable, Sendable {
    /// v1: engine record only. v2: adds stored `analyses` (§32, §47); v1
    /// files decode with an empty analysis list.
    public static let currentSchemaVersion = 2

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
    /// Stored result-independent analyses of the hero's decisions (schema v2).
    public var analyses: [DecisionAnalysis] = []

    private enum CodingKeys: String, CodingKey {
        case id, schemaVersion, date, handNumber, seed, smallBlind, bigBlind
        case ante, buttonIndex, heroSeat, playerNames, startingStacks
        case events, decisions, board, netChips, analyses
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        date = try c.decode(Date.self, forKey: .date)
        handNumber = try c.decode(Int.self, forKey: .handNumber)
        seed = try c.decode(UInt64.self, forKey: .seed)
        smallBlind = try c.decode(Int.self, forKey: .smallBlind)
        bigBlind = try c.decode(Int.self, forKey: .bigBlind)
        ante = try c.decode(Int.self, forKey: .ante)
        buttonIndex = try c.decode(Int.self, forKey: .buttonIndex)
        heroSeat = try c.decode(Int.self, forKey: .heroSeat)
        playerNames = try c.decode([String].self, forKey: .playerNames)
        startingStacks = try c.decode([Int].self, forKey: .startingStacks)
        events = try c.decode([HandEvent].self, forKey: .events)
        decisions = try c.decode([DecisionRecord].self, forKey: .decisions)
        board = try c.decode([Card].self, forKey: .board)
        netChips = try c.decode([Int].self, forKey: .netChips)
        // v1 histories have no analyses; never fail on their absence (§47).
        analyses = ((try? c.decodeIfPresent([DecisionAnalysis].self, forKey: .analyses)) ?? nil) ?? []
    }

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
