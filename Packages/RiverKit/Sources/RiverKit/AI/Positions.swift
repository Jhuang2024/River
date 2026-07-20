import Foundation

/// Standard six-max positions (§5), context-aware for short-handed tables.
public enum TablePosition: Int, Codable, CaseIterable, Comparable, Sendable {
    case underTheGun = 0
    case hijack = 1
    case cutoff = 2
    case button = 3
    case smallBlind = 4
    case bigBlind = 5

    public static func < (lhs: TablePosition, rhs: TablePosition) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }

    public var shortName: String {
        switch self {
        case .underTheGun: return "UTG"
        case .hijack: return "HJ"
        case .cutoff: return "CO"
        case .button: return "BTN"
        case .smallBlind: return "SB"
        case .bigBlind: return "BB"
        }
    }

    /// Relative lateness for strategy scaling: 0 = earliest, 1 = button.
    /// Blinds act last preflop but are positionally worst postflop; they get
    /// dedicated range tables rather than a lateness score.
    public var lateness: Double {
        switch self {
        case .underTheGun: return 0
        case .hijack: return 0.4
        case .cutoff: return 0.7
        case .button: return 1
        case .smallBlind: return 0.2
        case .bigBlind: return 0.1
        }
    }

    /// Maps a seat's clockwise offset from the button to a position, given the
    /// number of participating players (2...6). Offset 0 = button.
    ///
    /// Heads-up: the button is also the small blind (offset 0 → smallBlind
    /// semantics are handled by the caller; we report .button) and the other
    /// player is the big blind.
    public static func position(offsetFromButton offset: Int, playerCount: Int) -> TablePosition {
        precondition(playerCount >= 2 && playerCount <= 6)
        precondition(offset >= 0 && offset < playerCount)
        if playerCount == 2 {
            return offset == 0 ? .button : .bigBlind
        }
        if offset == 0 { return .button }
        if offset == 1 { return .smallBlind }
        if offset == 2 { return .bigBlind }
        // Remaining seats fill from UTG forward; with fewer players the
        // earliest positions disappear first (context-aware naming).
        let seatsAfterBlinds = playerCount - 3
        let indexAmongField = offset - 3 // 0-based among non-blind, non-button seats
        // indexAmongField 0 is the first to act preflop.
        switch seatsAfterBlinds - indexAmongField {
        case 1: return .cutoff       // last of the field before the button
        case 2: return .hijack
        default: return .underTheGun
        }
    }
}
