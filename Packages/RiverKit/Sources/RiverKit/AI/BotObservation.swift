import Foundation

/// Public information about one opponent as seen from a bot's chair.
public struct OpponentPublicState: Equatable, Sendable {
    public let seatIndex: Int
    public let stack: Int
    public let committedThisStreet: Int
    public let committedTotal: Int
    public let hasFolded: Bool
    public let isAllIn: Bool
}

/// Everything an AI player is allowed to know when making a decision.
///
/// This is the single choke point for hidden-information isolation: the
/// observation contains the bot's OWN hole cards only, opponent hole cards are
/// structurally absent, and the event history is filtered so no
/// `dealtHoleCards` event for another seat survives. Bots receive nothing else.
public struct BotObservation: Equatable, Sendable {
    public let seat: Int
    public let holeCards: [Card]
    public let board: [Card]
    public let street: Street
    public let pot: Int
    public let currentBet: Int
    public let bigBlind: Int
    public let buttonIndex: Int
    public let myStack: Int
    public let myCommittedThisStreet: Int
    public let opponents: [OpponentPublicState]
    public let available: AvailableActions
    /// Hand events visible to this seat (own hole cards, all public actions).
    public let visibleEvents: [HandEvent]
    /// Observed public tendencies per seat, from previous completed hands
    /// (§29). Populated by the session layer; empty when unavailable.
    public var observedTendencies: [Int: SeatTendencies] = [:]
    /// Public tournament information (players remaining, payouts, stacks).
    /// nil in cash games - ICM never leaks into cash decisions.
    public var tournamentContext: TournamentContext? = nil

    /// Copy with tendencies attached (observations are otherwise immutable).
    public func with(tendencies: [Int: SeatTendencies]) -> BotObservation {
        var copy = self
        copy.observedTendencies = tendencies
        return copy
    }

    public func with(tournament: TournamentContext?) -> BotObservation {
        var copy = self
        copy.tournamentContext = tournament
        return copy
    }

    /// Opponents still contesting the pot.
    public var activeOpponentCount: Int {
        return opponents.filter { !$0.hasFolded }.count
    }

    /// True when this seat is on the button.
    public var hasButton: Bool {
        return seat == buttonIndex
    }
}

extension PokerHand {
    /// Builds the legal-information-only view for the seat currently acting.
    /// Returns nil when it is not that seat's turn.
    public func observation(for seatIndex: Int) -> BotObservation? {
        guard let available = availableActions(for: seatIndex) else { return nil }
        let me = seats[seatIndex]
        let opponents = seats.filter { $0.seatIndex != seatIndex && $0.isParticipating }.map { seat in
            OpponentPublicState(
                seatIndex: seat.seatIndex,
                stack: seat.stack,
                committedThisStreet: seat.committedThisStreet,
                committedTotal: seat.committedTotal,
                hasFolded: seat.hasFolded,
                isAllIn: seat.isAllIn
            )
        }
        // Strip every other player's private cards from the history.
        let visible = events.filter { event in
            if let owner = event.privateSeat {
                return owner == seatIndex
            }
            return true
        }
        return BotObservation(
            seat: seatIndex,
            holeCards: me.holeCards,
            board: board,
            street: street,
            pot: pot,
            currentBet: currentBet,
            bigBlind: config.bigBlind,
            buttonIndex: config.buttonIndex,
            myStack: me.stack,
            myCommittedThisStreet: me.committedThisStreet,
            opponents: opponents,
            available: available,
            visibleEvents: visible
        )
    }
}
