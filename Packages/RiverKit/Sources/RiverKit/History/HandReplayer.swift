import Foundation

/// Reconstructs table state at any point of a recorded hand by folding the
/// event log forward. Used by the replay screen, and cross-checked in tests
/// against the engine's own final stacks.
public struct HandReplayer {

    public struct SeatSnapshot: Equatable, Sendable {
        public var stack: Int
        public var committedThisStreet: Int
        public var committedTotal: Int
        public var hasFolded: Bool
        public var holeCards: [Card]?
        public var showedCards: Bool
        public var isAllIn: Bool
    }

    public struct Snapshot: Equatable, Sendable {
        public var seats: [SeatSnapshot]
        public var board: [Card]
        public var street: Street
        public var pot: Int
        /// Seat that acted in the event that produced this snapshot, if any.
        public var lastActor: Int?
        /// Human-readable line describing the event, e.g. "Dana raises to 12".
        public var caption: String
    }

    public let history: HandHistory

    public init(history: HandHistory) {
        self.history = history
    }

    /// Number of replay steps (one per event).
    public var stepCount: Int {
        return history.events.count
    }

    /// Snapshot AFTER applying events[0...step]. Pass step = -1 for the deal.
    public func snapshot(afterStep step: Int, revealAll: Bool) -> Snapshot {
        var seats = history.startingStacks.map { stack in
            SeatSnapshot(stack: stack, committedThisStreet: 0, committedTotal: 0, hasFolded: false, holeCards: nil, showedCards: false, isAllIn: false)
        }
        var board: [Card] = []
        var street = Street.preflop
        var lastActor: Int? = nil
        var caption = "Hand #\(history.handNumber)"

        func name(_ seat: Int) -> String {
            if history.playerNames.indices.contains(seat) {
                return history.playerNames[seat]
            }
            return "Seat \(seat + 1)"
        }

        let upper = min(step, history.events.count - 1)
        if upper >= 0 {
            for index in 0...upper {
                let event = history.events[index]
                switch event {
                case .handStarted:
                    caption = "Hand #\(history.handNumber) begins"
                case .postedAnte(let seat, let amount):
                    seats[seat].stack -= amount
                    seats[seat].committedTotal += amount
                    caption = "\(name(seat)) posts ante \(amount)"
                    lastActor = seat
                case .postedSmallBlind(let seat, let amount):
                    seats[seat].stack -= amount
                    seats[seat].committedTotal += amount
                    seats[seat].committedThisStreet += amount
                    caption = "\(name(seat)) posts small blind \(amount)"
                    lastActor = seat
                case .postedBigBlind(let seat, let amount):
                    seats[seat].stack -= amount
                    seats[seat].committedTotal += amount
                    seats[seat].committedThisStreet += amount
                    caption = "\(name(seat)) posts big blind \(amount)"
                    lastActor = seat
                case .dealtHoleCards(let seat, let cards):
                    seats[seat].holeCards = cards
                    caption = "Dealing"
                case .action(let seat, let actionStreet, let kind, let added, let toTotal, let isAllIn):
                    street = actionStreet
                    seats[seat].stack -= added
                    seats[seat].committedTotal += added
                    seats[seat].committedThisStreet = toTotal
                    if kind == .fold {
                        seats[seat].hasFolded = true
                    }
                    if isAllIn {
                        seats[seat].isAllIn = true
                    }
                    lastActor = seat
                    switch kind {
                    case .fold: caption = "\(name(seat)) folds"
                    case .check: caption = "\(name(seat)) checks"
                    case .call: caption = "\(name(seat)) calls \(added)"
                    case .bet: caption = "\(name(seat)) bets \(toTotal)" + (isAllIn ? " (all-in)" : "")
                    case .raise: caption = "\(name(seat)) raises to \(toTotal)" + (isAllIn ? " (all-in)" : "")
                    }
                case .dealtBoard(let dealtStreet, let cards):
                    street = dealtStreet
                    board.append(contentsOf: cards)
                    for i in seats.indices {
                        seats[i].committedThisStreet = 0
                    }
                    caption = "\(dealtStreet.name): \(cards.map { $0.description }.joined(separator: " "))"
                    lastActor = nil
                case .refundedUncalledBet(let seat, let amount):
                    seats[seat].stack += amount
                    seats[seat].committedTotal -= amount
                    caption = "\(name(seat)) takes back \(amount)"
                    lastActor = seat
                case .wonWithoutShowdown(let seat, let amount):
                    seats[seat].stack += amount
                    caption = "\(name(seat)) wins \(amount)"
                    lastActor = seat
                case .showedHand(let seat, let cards, let valueDescription):
                    seats[seat].holeCards = cards
                    seats[seat].showedCards = true
                    caption = "\(name(seat)) shows \(cards.map { $0.description }.joined(separator: " ")) — \(valueDescription)"
                    lastActor = seat
                case .wonPot(let seat, let amount, let potIndex, let handDescription):
                    seats[seat].stack += amount
                    let potName = potIndex == 0 ? "the main pot" : "side pot \(potIndex)"
                    caption = "\(name(seat)) wins \(amount) from \(potName)" + (handDescription.isEmpty ? "" : " with \(handDescription)")
                    lastActor = seat
                case .handEnded:
                    caption = "Hand complete"
                    lastActor = nil
                }
            }
        }

        if !revealAll {
            for i in seats.indices where i != history.heroSeat && !seats[i].showedCards {
                seats[i].holeCards = nil
            }
        }

        var pot = 0
        for seat in seats {
            pot += seat.committedTotal
        }
        // After pots are distributed the committed chips have been paid out;
        // recompute pot as committed minus distributed so it drains naturally.
        var distributed = 0
        if upper >= 0 {
            for index in 0...upper {
                switch history.events[index] {
                case .wonPot(_, let amount, _, _): distributed += amount
                case .wonWithoutShowdown(_, let amount): distributed += amount
                default: break
                }
            }
        }
        pot = max(0, pot - distributed)

        return Snapshot(seats: seats, board: board, street: street, pot: pot, lastActor: lastActor, caption: caption)
    }
}
