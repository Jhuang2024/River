import Foundation

/// Player decisions (§6). Only legal actions are ever offered.
public enum BlackjackAction: String, Codable, Hashable, Sendable {
    case hit
    case stand
    case double
    case split
    case surrender

    public var displayName: String {
        switch self {
        case .hit: return "Hit"
        case .stand: return "Stand"
        case .double: return "Double"
        case .split: return "Split"
        case .surrender: return "Surrender"
        }
    }
}

/// One player hand (a split creates additional hands).
public struct BlackjackHand: Codable, Hashable, Sendable {
    public var cards: [BlackjackCard]
    public var bet: Int
    public var isDoubled: Bool = false
    public var isSurrendered: Bool = false
    public var isFromSplit: Bool = false
    public var isFromSplitAces: Bool = false
    public var isFinished: Bool = false
    /// Actions taken, for history and strategy grading (§12).
    public var actions: [BlackjackAction] = []

    public init(cards: [BlackjackCard], bet: Int) {
        self.cards = cards
        self.bet = bet
    }

    public var total: Int { BlackjackTotal.evaluate(cards).total }
    public var isSoft: Bool { BlackjackTotal.evaluate(cards).isSoft }
    public var isBust: Bool { BlackjackTotal.isBust(cards) }
    /// A natural only counts on an original (non-split) two-card hand.
    public var isNatural: Bool { !isFromSplit && BlackjackTotal.isBlackjack(cards) }
}

/// Where the round currently is. An explicit state machine (§14): the rules
/// engine is authoritative and animation merely follows it.
public enum BlackjackPhase: Codable, Hashable, Sendable {
    case betting
    /// Dealer shows an ace and insurance is offered (before peeking).
    case insuranceOffer
    /// The player is acting on hand `handIndex`.
    case playerTurn(handIndex: Int)
    case dealerTurn
    case settled
}

/// Per-hand settlement outcome for display and statistics.
public enum BlackjackHandOutcome: String, Codable, Hashable, Sendable {
    case blackjack
    case win
    case push
    case loss
    case bust
    case surrender
    case dealerBlackjack
}

public struct BlackjackSettlement: Codable, Hashable, Sendable {
    public struct HandResult: Codable, Hashable, Sendable {
        public let outcome: BlackjackHandOutcome
        public let bet: Int
        /// Chips returned to the player for this hand (stake + winnings).
        public let returned: Int
    }
    public let hands: [HandResult]
    public let insuranceBet: Int
    public let insuranceReturned: Int
    /// Total chips returned across hands and insurance.
    public var totalReturned: Int {
        return hands.reduce(0) { $0 + $1.returned } + insuranceReturned
    }
    /// Total chips staked across hands and insurance.
    public var totalStaked: Int {
        return hands.reduce(0) { $0 + $1.bet } + insuranceBet
    }
    public var net: Int { totalReturned - totalStaked }
}

public enum BlackjackError: Error, Equatable {
    case wrongPhase
    case illegalAction
    case invalidBet
}

/// The complete round state machine. Pure value type: every transition is a
/// mutating func, fully Codable for save/resume (§15), and driven only by the
/// shoe's seeded order — never by bankroll, history or streaks (§3).
public struct BlackjackRound: Codable, Hashable, Sendable {
    public let rules: BlackjackRules
    public private(set) var shoe: BlackjackShoe
    public private(set) var phase: BlackjackPhase
    public private(set) var hands: [BlackjackHand]
    public private(set) var dealerCards: [BlackjackCard]
    /// The hole card is hidden until the dealer's turn (or a peeked natural).
    public private(set) var dealerHoleRevealed: Bool
    public private(set) var insuranceBet: Int
    public private(set) var settlement: BlackjackSettlement?
    /// The shoe seed + position define the round for fairness inspection (§3).
    public var fairness: (seed: UInt64, position: Int) { (shoe.seed, roundStartPosition) }
    private var roundStartPosition: Int

    public init(rules: BlackjackRules, shoe: BlackjackShoe) {
        self.rules = rules
        self.shoe = shoe
        self.phase = .betting
        self.hands = []
        self.dealerCards = []
        self.dealerHoleRevealed = false
        self.insuranceBet = 0
        self.settlement = nil
        self.roundStartPosition = shoe.dealtCount
    }

    public var dealerUpcard: BlackjackCard? {
        return dealerCards.first
    }

    public var dealerTotal: Int { BlackjackTotal.evaluate(dealerCards).total }

    // MARK: - Dealing

    /// Deals the round for a bet. Bet must be positive and a multiple of the
    /// rules' bet step so 3:2 and insurance stay integer-exact.
    public mutating func deal(bet: Int) throws {
        guard case .betting = phase else { throw BlackjackError.wrongPhase }
        guard bet > 0, bet % rules.betStep == 0 else { throw BlackjackError.invalidBet }
        roundStartPosition = shoe.dealtCount
        var hand = BlackjackHand(cards: [], bet: bet)
        hand.cards.append(shoe.deal())
        dealerCards.append(shoe.deal())
        hand.cards.append(shoe.deal())
        dealerCards.append(shoe.deal())
        hands = [hand]

        if rules.insuranceAllowed && dealerUpcard?.rank == .ace {
            phase = .insuranceOffer
            return
        }
        resolveAfterInsuranceDecision()
    }

    /// Take or decline insurance, then the dealer peeks.
    public mutating func decideInsurance(take: Bool) throws {
        guard case .insuranceOffer = phase else { throw BlackjackError.wrongPhase }
        insuranceBet = take ? hands[0].bet / 2 : 0
        resolveAfterInsuranceDecision()
    }

    private mutating func resolveAfterInsuranceDecision() {
        // Dealer peeks with a ten or ace showing (§6): a dealer natural ends
        // the round immediately instead of letting doubles/splits pile up.
        let upValue = dealerUpcard?.pointValue ?? 0
        if rules.dealerPeeks && (upValue == 1 || upValue == 10) && BlackjackTotal.isBlackjack(dealerCards) {
            dealerHoleRevealed = true
            settle()
            return
        }
        if hands[0].isNatural {
            dealerHoleRevealed = true
            settle()
            return
        }
        phase = .playerTurn(handIndex: 0)
    }

    // MARK: - Legal actions

    public func legalActions(handIndex: Int) -> [BlackjackAction] {
        guard case .playerTurn(let current) = phase, current == handIndex,
              hands.indices.contains(handIndex) else { return [] }
        let hand = hands[handIndex]
        guard !hand.isFinished else { return [] }
        var actions: [BlackjackAction] = [.hit, .stand]
        let isTwoCards = hand.cards.count == 2
        if isTwoCards && !(hand.isFromSplitAces && rules.splitAcesOneCardOnly) {
            if !hand.isFromSplit || rules.doubleAfterSplitAllowed {
                actions.append(.double)
            }
        }
        if isTwoCards && hand.cards[0].pointValue == hand.cards[1].pointValue
            && hands.count < rules.maxSplitHands {
            actions.append(.split)
        }
        if rules.surrenderAllowed && isTwoCards && !hand.isFromSplit && hands.count == 1 {
            actions.append(.surrender)
        }
        return actions
    }

    // MARK: - Player actions

    public mutating func apply(_ action: BlackjackAction, handIndex: Int) throws {
        guard legalActions(handIndex: handIndex).contains(action) else {
            throw BlackjackError.illegalAction
        }
        hands[handIndex].actions.append(action)
        switch action {
        case .hit:
            hands[handIndex].cards.append(shoe.deal())
            if hands[handIndex].isBust || hands[handIndex].total == 21 {
                finishHand(handIndex)
            } else if hands[handIndex].isFromSplitAces && rules.splitAcesOneCardOnly {
                finishHand(handIndex)
            }
        case .stand:
            finishHand(handIndex)
        case .double:
            hands[handIndex].bet *= 2
            hands[handIndex].isDoubled = true
            hands[handIndex].cards.append(shoe.deal())
            finishHand(handIndex)
        case .split:
            let hand = hands[handIndex]
            let splittingAces = hand.cards[0].rank == .ace
            var first = BlackjackHand(cards: [hand.cards[0]], bet: hand.bet)
            var second = BlackjackHand(cards: [hand.cards[1]], bet: hand.bet)
            first.isFromSplit = true
            second.isFromSplit = true
            first.isFromSplitAces = splittingAces
            second.isFromSplitAces = splittingAces
            first.actions = hand.actions
            first.cards.append(shoe.deal())
            second.cards.append(shoe.deal())
            hands[handIndex] = first
            hands.insert(second, at: handIndex + 1)
            if splittingAces && rules.splitAcesOneCardOnly {
                // One card each, both hands complete (§6).
                finishHand(handIndex + 1)
                finishHand(handIndex)
            } else if hands[handIndex].total == 21 {
                finishHand(handIndex)
            }
        case .surrender:
            hands[handIndex].isSurrendered = true
            finishHand(handIndex)
        }
    }

    private mutating func finishHand(_ handIndex: Int) {
        hands[handIndex].isFinished = true
        advanceTurn(from: handIndex)
    }

    private mutating func advanceTurn(from handIndex: Int) {
        guard case .playerTurn = phase else { return }
        if let next = hands.indices.first(where: { !hands[$0].isFinished }) {
            phase = .playerTurn(handIndex: next)
            return
        }
        // All hands done: dealer plays only if someone can still win.
        let anyLive = hands.contains { !$0.isBust && !$0.isSurrendered }
        dealerHoleRevealed = true
        if anyLive {
            phase = .dealerTurn
            playDealer()
        } else {
            settle()
        }
    }

    // MARK: - Dealer

    private mutating func playDealer() {
        while true {
            let (total, soft) = BlackjackTotal.evaluate(dealerCards)
            if total > 21 { break }
            if total > 17 { break }
            if total == 17 {
                if soft && rules.dealerHitsSoft17 {
                    dealerCards.append(shoe.deal())
                    continue
                }
                break
            }
            dealerCards.append(shoe.deal())
        }
        settle()
    }

    // MARK: - Settlement (§6): exact integer chips, every path covered.

    private mutating func settle() {
        let dealerNatural = BlackjackTotal.isBlackjack(dealerCards)
        let dealerFinal = dealerTotal
        let dealerBust = dealerFinal > 21

        var results: [BlackjackSettlement.HandResult] = []
        for hand in hands {
            let outcome: BlackjackHandOutcome
            let returned: Int
            if hand.isSurrendered {
                outcome = .surrender
                returned = hand.bet / 2
            } else if dealerNatural {
                if hand.isNatural {
                    outcome = .push
                    returned = hand.bet
                } else {
                    outcome = .dealerBlackjack
                    returned = 0
                }
            } else if hand.isNatural {
                outcome = .blackjack
                returned = hand.bet + rules.blackjackWinnings(bet: hand.bet)
            } else if hand.isBust {
                outcome = .bust
                returned = 0
            } else if dealerBust || hand.total > dealerFinal {
                outcome = .win
                returned = hand.bet * 2
            } else if hand.total == dealerFinal {
                outcome = .push
                returned = hand.bet
            } else {
                outcome = .loss
                returned = 0
            }
            results.append(.init(outcome: outcome, bet: hand.bet, returned: returned))
        }

        // Insurance pays 2:1 when the dealer has a natural.
        let insuranceReturned = dealerNatural ? insuranceBet * 3 : 0

        settlement = BlackjackSettlement(
            hands: results,
            insuranceBet: insuranceBet,
            insuranceReturned: insuranceReturned
        )
        dealerHoleRevealed = true
        phase = .settled
    }

    /// Total chips the round has taken from the bankroll so far (stakes for
    /// all hands including doubles/splits, plus insurance).
    public var totalStaked: Int {
        return hands.reduce(0) { $0 + $1.bet } + insuranceBet
    }
}
