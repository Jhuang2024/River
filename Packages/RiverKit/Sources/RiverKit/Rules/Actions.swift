import Foundation

/// Betting streets in order.
public enum Street: Int, Codable, Comparable, CaseIterable, Sendable {
    case preflop = 0
    case flop = 1
    case turn = 2
    case river = 3

    public static func < (lhs: Street, rhs: Street) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }

    public var name: String {
        switch self {
        case .preflop: return "Preflop"
        case .flop: return "Flop"
        case .turn: return "Turn"
        case .river: return "River"
        }
    }
}

/// The kind of a voluntary player action.
public enum ActionKind: String, Codable, Equatable, Sendable {
    case fold
    case check
    case call
    case bet
    case raise
}

/// A voluntary action submitted to the engine.
///
/// For `.bet` and `.raise`, `toAmount` is the TOTAL the player is betting to on
/// this street (a "raise to 30" has `toAmount == 30`), never the increment.
/// For other kinds `toAmount` is ignored and should be 0.
public struct PlayerAction: Codable, Hashable, Sendable {
    public let kind: ActionKind
    public let toAmount: Int

    public init(kind: ActionKind, toAmount: Int = 0) {
        self.kind = kind
        self.toAmount = toAmount
    }

    public static let fold = PlayerAction(kind: .fold)
    public static let check = PlayerAction(kind: .check)
    public static let call = PlayerAction(kind: .call)

    public static func bet(to amount: Int) -> PlayerAction {
        return PlayerAction(kind: .bet, toAmount: amount)
    }

    public static func raise(to amount: Int) -> PlayerAction {
        return PlayerAction(kind: .raise, toAmount: amount)
    }
}

/// Options for a legal bet or raise.
public struct BetRaiseOptions: Equatable, Sendable {
    /// `.bet` when opening the betting on a street, `.raise` otherwise.
    public let kind: ActionKind
    /// Smallest legal "to" amount. Equals `maxTo` when only an all-in below the
    /// full minimum is possible.
    public let minTo: Int
    /// The "to" amount that constitutes a full bet/raise (reopens the action).
    public let minFullTo: Int
    /// The all-in "to" amount (street commitment plus remaining stack).
    public let maxTo: Int

    public init(kind: ActionKind, minTo: Int, minFullTo: Int, maxTo: Int) {
        self.kind = kind
        self.minTo = minTo
        self.minFullTo = minFullTo
        self.maxTo = maxTo
    }

    /// Whether a given "to" amount is legal: at or above the full minimum, or
    /// exactly all-in (an all-in below the full minimum is always permitted).
    public func isLegal(toAmount: Int) -> Bool {
        if toAmount == maxTo { return true }
        return toAmount >= minFullTo && toAmount < maxTo
    }
}

/// Everything a player is currently allowed to do.
public struct AvailableActions: Equatable, Sendable {
    public let seat: Int
    /// Folding is always legal when it is your turn (even if unwise with no bet).
    public let canFold: Bool
    public let canCheck: Bool
    /// Chips the player must ADD to call, already capped by their stack
    /// (0 when there is nothing to call).
    public let callCost: Int
    /// The uncapped amount owed; when larger than `callCost` the call is all-in.
    public let fullAmountOwed: Int
    /// Bet/raise options, or nil when betting is not allowed.
    public let betRaise: BetRaiseOptions?

    public init(seat: Int, canFold: Bool, canCheck: Bool, callCost: Int, fullAmountOwed: Int, betRaise: BetRaiseOptions?) {
        self.seat = seat
        self.canFold = canFold
        self.canCheck = canCheck
        self.callCost = callCost
        self.fullAmountOwed = fullAmountOwed
        self.betRaise = betRaise
    }

    public var canCall: Bool {
        return callCost > 0
    }

    public var isCallAllIn: Bool {
        return callCost > 0 && callCost < fullAmountOwed
    }
}

/// Validation and sequencing errors thrown by the engine.
public enum EngineError: Error, Equatable, Sendable {
    case handComplete
    case notPlayersTurn(seat: Int)
    case checkNotAllowed
    case nothingToCall
    case mustUseBetWhenUnopened
    case mustUseRaiseWhenFacingBet
    case betOrRaiseNotAllowed
    case amountNotLegal(minimum: Int, maximum: Int)
    case seatNotInHand(seat: Int)
}
