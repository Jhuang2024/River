import Foundation

/// Static configuration for one hand.
public struct HandConfig: Codable, Equatable, Sendable {
    /// Stack behind each seat at the start of the hand. A stack of 0 means the
    /// seat is not participating in this hand.
    public var stacks: [Int]
    public var buttonIndex: Int
    public var smallBlind: Int
    public var bigBlind: Int
    public var ante: Int
    public var seed: UInt64
    public var handNumber: Int

    public init(stacks: [Int], buttonIndex: Int, smallBlind: Int, bigBlind: Int, ante: Int = 0, seed: UInt64, handNumber: Int = 1) {
        self.stacks = stacks
        self.buttonIndex = buttonIndex
        self.smallBlind = smallBlind
        self.bigBlind = bigBlind
        self.ante = ante
        self.seed = seed
        self.handNumber = handNumber
    }
}

/// Per-seat state during a hand.
public struct SeatHandState: Codable, Equatable, Sendable {
    public let seatIndex: Int
    public let startingStack: Int
    /// Chips still behind (not committed).
    public internal(set) var stack: Int
    public internal(set) var holeCards: [Card]
    /// Chips committed on the current street only (blinds count, antes do not).
    public internal(set) var committedThisStreet: Int
    /// Total chips committed across the whole hand including antes.
    public internal(set) var committedTotal: Int
    public internal(set) var hasFolded: Bool

    /// Participating in this hand at all (had chips when the hand started).
    public var isParticipating: Bool {
        return startingStack > 0
    }

    /// Still eligible to win a pot.
    public var isLive: Bool {
        return isParticipating && !hasFolded
    }

    /// Live with no chips behind: cannot act further.
    public var isAllIn: Bool {
        return isLive && stack == 0
    }

    /// Live and still able to make decisions.
    public var canAct: Bool {
        return isLive && stack > 0
    }
}

/// Optional analysis metadata a caller may attach when applying an action.
/// The engine itself never computes equities; bots and the hero advisor pass
/// their own honest estimates here so hand reviews can show them later.
public struct DecisionAnnotation: Codable, Hashable, Sendable {
    /// Estimated equity/strength in [0, 1] at decision time, if computed.
    public var strengthEstimate: Double?
    /// What the basic advisor would have done, if computed.
    public var advisorKind: ActionKind?
    /// Short reasoning note ("pot odds 25%, estimated equity 40%").
    public var note: String?

    public init(strengthEstimate: Double? = nil, advisorKind: ActionKind? = nil, note: String? = nil) {
        self.strengthEstimate = strengthEstimate
        self.advisorKind = advisorKind
        self.note = note
    }
}

/// A snapshot of one decision point, stored for post-hand analysis (§35).
public struct DecisionRecord: Codable, Hashable, Sendable {
    public let seat: Int
    public let street: Street
    /// Pot size before the action (all committed chips).
    public let potBefore: Int
    /// Chips the seat needed to add to call (capped by stack).
    public let toCall: Int
    public let couldCheck: Bool
    public let couldRaise: Bool
    public let chosen: PlayerAction
    /// Chips actually added by the action.
    public let chipsAdded: Int
    /// Readable current made hand from the actor's own cards + board.
    public let handDescription: String
    /// toCall / (potBefore + toCall); 0 when nothing to call.
    public let potOdds: Double
    public let annotation: DecisionAnnotation?
}

/// Authoritative state machine for a single hand of No-Limit Texas Hold'em.
///
/// The engine is deterministic: the same `HandConfig` (including seed) and the
/// same sequence of applied actions always produce the same events, board and
/// results. It is completely independent of any UI.
public final class PokerHand {

    public let config: HandConfig
    public private(set) var seats: [SeatHandState]
    public private(set) var board: [Card]
    public private(set) var street: Street
    public private(set) var isComplete: Bool
    /// Seat currently required to act, nil when between streets or complete.
    public private(set) var actionOn: Int?
    /// Highest street commitment (the amount everyone must match).
    public private(set) var currentBet: Int
    /// Size of the last full bet/raise increment; the next full raise must
    /// increase the bet by at least this much. Starts at the big blind.
    public private(set) var lastFullRaiseSize: Int
    public private(set) var events: [HandEvent]
    public private(set) var decisions: [DecisionRecord]
    /// Final pots, available once the hand is complete.
    public private(set) var finalPots: [Pot]

    private var deck: Deck
    /// Seats that have taken a voluntary action since the last full bet/raise
    /// on this street. Blind posts do not count (that is what gives the big
    /// blind its preflop option).
    private var actedThisStreet: Set<Int>
    /// Seats barred from raising because they already acted and the action was
    /// then re-opened only by an all-in raise smaller than a full raise.
    private var raiseBarred: Set<Int>

    // MARK: - Setup

    public convenience init(config: HandConfig) {
        self.init(config: config, riggedDeck: nil)
    }

    /// `riggedDeck` lets tests and debug tooling force exact cards. The rigged
    /// order must contain 52 unique cards; normal play always passes nil.
    public init(config: HandConfig, riggedDeck: [Card]?) {
        precondition(config.smallBlind > 0 && config.bigBlind >= config.smallBlind, "invalid blinds")
        precondition(config.ante >= 0, "invalid ante")
        self.config = config
        self.board = []
        self.street = .preflop
        self.isComplete = false
        self.actionOn = nil
        self.currentBet = 0
        self.lastFullRaiseSize = config.bigBlind
        self.events = []
        self.decisions = []
        self.finalPots = []
        self.actedThisStreet = []
        self.raiseBarred = []
        if let rigged = riggedDeck {
            precondition(Set(rigged).count == 52 && rigged.count == 52, "rigged deck must be 52 unique cards")
            self.deck = Deck(riggedOrder: rigged)
        } else {
            self.deck = Deck(seed: config.seed)
        }
        var initialSeats: [SeatHandState] = []
        for (index, stack) in config.stacks.enumerated() {
            precondition(stack >= 0, "negative stack")
            initialSeats.append(SeatHandState(
                seatIndex: index,
                startingStack: stack,
                stack: stack,
                holeCards: [],
                committedThisStreet: 0,
                committedTotal: 0,
                hasFolded: !(stack > 0)
            ))
        }
        self.seats = initialSeats

        let participants = seats.filter { $0.isParticipating }
        precondition(participants.count >= 2, "a hand needs at least two players")
        precondition(seats.indices.contains(config.buttonIndex) && seats[config.buttonIndex].isParticipating, "button must be a participating seat")

        events.append(.handStarted(
            handNumber: config.handNumber,
            button: config.buttonIndex,
            smallBlind: config.smallBlind,
            bigBlind: config.bigBlind,
            ante: config.ante,
            stacks: config.stacks
        ))

        postAntesAndBlinds()
        dealHoleCards()
        beginPreflopAction()
    }

    // MARK: - Public derived state

    /// All chips committed so far (what the table displays as the pot).
    public var pot: Int {
        return seats.reduce(0) { $0 + $1.committedTotal }
    }

    public var liveSeatIndices: [Int] {
        return seats.filter { $0.isLive }.map { $0.seatIndex }
    }

    public var bigBlindSeat: Int {
        let sb = smallBlindSeat
        return nextParticipant(after: sb)
    }

    public var smallBlindSeat: Int {
        if participantCount == 2 {
            return config.buttonIndex
        }
        return nextParticipant(after: config.buttonIndex)
    }

    private var participantCount: Int {
        return seats.filter { $0.isParticipating }.count
    }

    // MARK: - Seat traversal

    /// Next participating seat clockwise, skipping empty seats.
    private func nextParticipant(after index: Int) -> Int {
        var i = index
        for _ in 0..<seats.count {
            i = (i + 1) % seats.count
            if seats[i].isParticipating {
                return i
            }
        }
        return index
    }

    /// A seat still owing a decision this street: live, has chips, and either
    /// has not matched the current bet or has not acted since the last full raise.
    private func isPending(_ seat: SeatHandState) -> Bool {
        guard seat.canAct else { return false }
        if seat.committedThisStreet < currentBet { return true }
        return !actedThisStreet.contains(seat.seatIndex)
    }

    private func nextPendingSeat(after index: Int) -> Int? {
        var i = index
        for _ in 0..<seats.count {
            i = (i + 1) % seats.count
            if seats[i].isParticipating && isPending(seats[i]) {
                return i
            }
        }
        return nil
    }

    private var bettingRoundComplete: Bool {
        return !seats.contains { $0.isParticipating && isPending($0) }
    }

    // MARK: - Hand setup steps

    private func commit(seat index: Int, amount: Int, countsTowardStreet: Bool) {
        precondition(amount >= 0)
        let pay = min(amount, seats[index].stack)
        seats[index].stack -= pay
        seats[index].committedTotal += pay
        if countsTowardStreet {
            seats[index].committedThisStreet += pay
        }
    }

    private func postAntesAndBlinds() {
        if config.ante > 0 {
            var i = config.buttonIndex
            for _ in 0..<participantCount {
                i = nextParticipant(after: i)
                let pay = min(config.ante, seats[i].stack)
                if pay > 0 {
                    // Antes are dead money: they do not count toward calling.
                    commit(seat: i, amount: pay, countsTowardStreet: false)
                    events.append(.postedAnte(seat: i, amount: pay))
                }
            }
        }
        let sb = smallBlindSeat
        let bb = bigBlindSeat
        let sbPay = min(config.smallBlind, seats[sb].stack)
        commit(seat: sb, amount: sbPay, countsTowardStreet: true)
        events.append(.postedSmallBlind(seat: sb, amount: sbPay))
        let bbPay = min(config.bigBlind, seats[bb].stack)
        commit(seat: bb, amount: bbPay, countsTowardStreet: true)
        events.append(.postedBigBlind(seat: bb, amount: bbPay))
        // The full big blind is the bet to match even if the big blind was
        // all-in for less; side pots reconcile the difference at showdown.
        currentBet = config.bigBlind
        lastFullRaiseSize = config.bigBlind
    }

    private func dealHoleCards() {
        // One card at a time, two rounds, starting left of the button.
        var dealt: [Int: [Card]] = [:]
        for _ in 0..<2 {
            var i = config.buttonIndex
            for _ in 0..<participantCount {
                i = nextParticipant(after: i)
                dealt[i, default: []].append(deck.deal())
            }
        }
        var i = config.buttonIndex
        for _ in 0..<participantCount {
            i = nextParticipant(after: i)
            let cards = dealt[i] ?? []
            seats[i].holeCards = cards
            events.append(.dealtHoleCards(seat: i, cards: cards))
        }
    }

    private func beginPreflopAction() {
        // First to act preflop is the seat after the big blind. In heads-up
        // play that is the button/small blind, which is correct.
        if bettingRoundComplete {
            // Everyone is already all-in from blinds/antes: run the board out.
            advanceAfterAction(lastActor: bigBlindSeat)
            return
        }
        actionOn = nextPendingSeat(after: bigBlindSeat)
        if actionOn == nil {
            advanceAfterAction(lastActor: bigBlindSeat)
        }
    }

    // MARK: - Legal actions

    /// The legal actions for a seat, or nil when it is not that seat's turn.
    public func availableActions(for seatIndex: Int) -> AvailableActions? {
        guard !isComplete, actionOn == seatIndex, seats.indices.contains(seatIndex) else {
            return nil
        }
        let seat = seats[seatIndex]
        let owed = max(0, currentBet - seat.committedThisStreet)
        let callCost = min(owed, seat.stack)
        let canCheck = owed == 0
        let maxTo = seat.committedThisStreet + seat.stack

        var betRaise: BetRaiseOptions? = nil
        let barred = raiseBarred.contains(seatIndex)
        if !barred && maxTo > currentBet && seat.stack > callCost {
            if currentBet == 0 {
                let minFull = min(config.bigBlind, maxTo)
                betRaise = BetRaiseOptions(kind: .bet, minTo: min(minFull, maxTo), minFullTo: minFull, maxTo: maxTo)
            } else {
                let minFull = currentBet + lastFullRaiseSize
                betRaise = BetRaiseOptions(kind: .raise, minTo: min(minFull, maxTo), minFullTo: minFull, maxTo: maxTo)
            }
        }
        return AvailableActions(
            seat: seatIndex,
            canFold: true,
            canCheck: canCheck,
            callCost: callCost,
            fullAmountOwed: owed,
            betRaise: betRaise
        )
    }

    // MARK: - Applying actions

    /// Validates and applies a voluntary action for the seat currently on turn.
    public func apply(_ action: PlayerAction, by seatIndex: Int, annotation: DecisionAnnotation? = nil) throws {
        guard !isComplete else { throw EngineError.handComplete }
        guard seats.indices.contains(seatIndex) else { throw EngineError.seatNotInHand(seat: seatIndex) }
        guard actionOn == seatIndex else { throw EngineError.notPlayersTurn(seat: seatIndex) }
        guard let available = availableActions(for: seatIndex) else { throw EngineError.notPlayersTurn(seat: seatIndex) }

        let potBefore = pot
        let stackBefore = seats[seatIndex].stack
        let streetBefore = street

        switch action.kind {
        case .fold:
            seats[seatIndex].hasFolded = true
            actedThisStreet.insert(seatIndex)

        case .check:
            guard available.canCheck else { throw EngineError.checkNotAllowed }
            actedThisStreet.insert(seatIndex)

        case .call:
            guard available.canCall else { throw EngineError.nothingToCall }
            commit(seat: seatIndex, amount: available.callCost, countsTowardStreet: true)
            actedThisStreet.insert(seatIndex)

        case .bet, .raise:
            guard let options = available.betRaise else { throw EngineError.betOrRaiseNotAllowed }
            if options.kind == .bet && action.kind == .raise { throw EngineError.mustUseBetWhenUnopened }
            if options.kind == .raise && action.kind == .bet { throw EngineError.mustUseRaiseWhenFacingBet }
            let target = action.toAmount
            guard options.isLegal(toAmount: target) else {
                throw EngineError.amountNotLegal(minimum: options.minTo, maximum: options.maxTo)
            }
            let toAdd = target - seats[seatIndex].committedThisStreet
            guard toAdd > 0 && toAdd <= seats[seatIndex].stack else {
                throw EngineError.amountNotLegal(minimum: options.minTo, maximum: options.maxTo)
            }
            let isFull = target >= options.minFullTo
            let previouslyActed = actedThisStreet
            commit(seat: seatIndex, amount: toAdd, countsTowardStreet: true)
            if isFull {
                // A full bet/raise re-opens the action for everyone.
                lastFullRaiseSize = currentBet == 0 ? target : target - currentBet
                raiseBarred.removeAll()
            } else {
                // An all-in below the full minimum does NOT re-open the action:
                // players who already acted may now only call or fold.
                raiseBarred.formUnion(previouslyActed)
            }
            currentBet = target
            actedThisStreet = [seatIndex]
        }

        let added = stackBefore - seats[seatIndex].stack
        let isAllIn = seats[seatIndex].isAllIn
        events.append(.action(
            seat: seatIndex,
            street: streetBefore,
            kind: action.kind,
            added: added,
            toTotal: seats[seatIndex].committedThisStreet,
            isAllIn: isAllIn
        ))

        let handDesc: String
        if board.count >= 3 {
            handDesc = HandEvaluator.evaluate(hole: seats[seatIndex].holeCards, board: board).readableDescription
        } else {
            handDesc = PreflopHands.label(for: seats[seatIndex].holeCards)
        }
        let owed = available.callCost
        let potOdds = owed > 0 ? Double(owed) / Double(potBefore + owed) : 0
        decisions.append(DecisionRecord(
            seat: seatIndex,
            street: streetBefore,
            potBefore: potBefore,
            toCall: owed,
            couldCheck: available.canCheck,
            couldRaise: available.betRaise != nil,
            chosen: action,
            chipsAdded: added,
            handDescription: handDesc,
            potOdds: potOdds,
            annotation: annotation
        ))

        advanceAfterAction(lastActor: seatIndex)
    }

    // MARK: - Hand flow

    private func advanceAfterAction(lastActor: Int) {
        let live = seats.filter { $0.isLive }
        if live.count <= 1 {
            finishByFolds()
            return
        }
        if !bettingRoundComplete {
            actionOn = nextPendingSeat(after: lastActor)
            if actionOn != nil {
                return
            }
        }
        // Betting round finished: move to the next street or showdown.
        actionOn = nil
        advanceStreets()
    }

    /// Deals forward through streets. When fewer than two players can still
    /// act, remaining streets are run out with no betting.
    private func advanceStreets() {
        while true {
            if street == .river {
                finishAtShowdown()
                return
            }
            startNextStreet()
            let actors = seats.filter { $0.canAct && $0.isLive }
            if actors.count >= 2 {
                actionOn = nextPendingSeat(after: config.buttonIndex)
                if actionOn != nil {
                    return
                }
            }
            // Nobody (or only one player) can act: keep dealing.
        }
    }

    private func startNextStreet() {
        for i in seats.indices {
            seats[i].committedThisStreet = 0
        }
        currentBet = 0
        lastFullRaiseSize = config.bigBlind
        actedThisStreet = []
        raiseBarred = []
        switch street {
        case .preflop:
            street = .flop
            deck.burn()
            let cards = [deck.deal(), deck.deal(), deck.deal()]
            board.append(contentsOf: cards)
            events.append(.dealtBoard(street: .flop, cards: cards))
        case .flop:
            street = .turn
            deck.burn()
            let card = deck.deal()
            board.append(card)
            events.append(.dealtBoard(street: .turn, cards: [card]))
        case .turn:
            street = .river
            deck.burn()
            let card = deck.deal()
            board.append(card)
            events.append(.dealtBoard(street: .river, cards: [card]))
        case .river:
            break
        }
    }

    /// Everyone else folded: the last live seat wins everything without
    /// showdown. Every other claim was abandoned, so the winner takes ALL
    /// committed chips — even chips above their own all-in level (this can
    /// happen when deeper players open-fold after calling). The only money
    /// that comes back as a refund is the winner's own uncalled excess, which
    /// exists only when the winner out-committed every other seat.
    private func finishByFolds() {
        actionOn = nil
        guard let winner = seats.first(where: { $0.isLive })?.seatIndex else {
            fatalError("hand ended with no live seats")
        }
        let committed = seats.map { $0.committedTotal }
        let total = committed.reduce(0, +)
        var secondHighest = 0
        for (index, amount) in committed.enumerated() where index != winner {
            secondHighest = max(secondHighest, amount)
        }
        var refund = 0
        if committed[winner] > secondHighest {
            refund = committed[winner] - secondHighest
            seats[winner].stack += refund
            seats[winner].committedTotal -= refund
            events.append(.refundedUncalledBet(seat: winner, amount: refund))
        }
        let winnings = total - refund
        seats[winner].stack += winnings
        finalPots = [Pot(amount: winnings, eligibleSeats: [winner])]
        events.append(.wonWithoutShowdown(seat: winner, amount: winnings))
        finishHand()
    }

    private func finishAtShowdown() {
        actionOn = nil
        let liveIndices = seats.filter { $0.isLive }.map { $0.seatIndex }
        let committed = seats.map { $0.committedTotal }
        let result = PotBuilder.build(committed: committed, liveSeats: Set(liveIndices))
        applyRefunds(result.refunds)
        finalPots = result.pots

        // Evaluate every live hand once.
        var values: [Int: HandValue] = [:]
        var orderedLive: [Int] = []
        var i = config.buttonIndex
        for _ in 0..<seats.count {
            i = (i + 1) % seats.count
            if seats[i].isLive {
                orderedLive.append(i)
            }
        }
        for seat in orderedLive {
            let value = HandEvaluator.evaluate(hole: seats[seat].holeCards, board: board)
            values[seat] = value
            events.append(.showedHand(seat: seat, cards: seats[seat].holeCards, valueDescription: value.readableDescription))
        }

        // Award side pots first (highest index), then the main pot, matching
        // live-table procedure. Odd chips go to the first winner left of the
        // button within each pot.
        for potIndex in stride(from: result.pots.count - 1, through: 0, by: -1) {
            let potLayer = result.pots[potIndex]
            guard let best = potLayer.eligibleSeats.compactMap({ values[$0] }).max() else { continue }
            let winners = potLayer.eligibleSeats.filter { values[$0] == best }
            let share = potLayer.amount / winners.count
            var odd = potLayer.amount - share * winners.count
            var payouts: [Int: Int] = [:]
            for seat in winners {
                payouts[seat] = share
            }
            for seat in orderedLive where odd > 0 {
                if winners.contains(seat) {
                    payouts[seat, default: 0] += 1
                    odd -= 1
                }
            }
            for seat in orderedLive {
                if let amount = payouts[seat], amount > 0 {
                    seats[seat].stack += amount
                    events.append(.wonPot(
                        seat: seat,
                        amount: amount,
                        potIndex: potIndex,
                        handDescription: values[seat]?.readableDescription ?? ""
                    ))
                }
            }
        }
        finishHand()
    }

    private func applyRefunds(_ refunds: [Int]) {
        for (seat, amount) in refunds.enumerated() where amount > 0 {
            seats[seat].stack += amount
            seats[seat].committedTotal -= amount
            events.append(.refundedUncalledBet(seat: seat, amount: amount))
        }
    }

    private func finishHand() {
        isComplete = true
        let finalStacks = seats.map { $0.stack }
        let net = seats.map { $0.stack - $0.startingStack }
        events.append(.handEnded(finalStacks: finalStacks, netChips: net))
    }
}
