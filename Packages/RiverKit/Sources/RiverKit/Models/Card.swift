import Foundation

/// One of the four French suits. Raw values are stable and used in persistence.
public enum Suit: Int, Codable, CaseIterable, Hashable, Sendable {
    case clubs = 0
    case diamonds = 1
    case hearts = 2
    case spades = 3

    public var symbol: String {
        switch self {
        case .clubs: return "♣"
        case .diamonds: return "♦"
        case .hearts: return "♥"
        case .spades: return "♠"
        }
    }

    public var name: String {
        switch self {
        case .clubs: return "clubs"
        case .diamonds: return "diamonds"
        case .hearts: return "hearts"
        case .spades: return "spades"
        }
    }
}

/// Card rank. Raw value is the poker value: 2...14 where 14 is the ace.
public enum Rank: Int, Codable, CaseIterable, Hashable, Comparable, Sendable {
    case two = 2
    case three = 3
    case four = 4
    case five = 5
    case six = 6
    case seven = 7
    case eight = 8
    case nine = 9
    case ten = 10
    case jack = 11
    case queen = 12
    case king = 13
    case ace = 14

    public static func < (lhs: Rank, rhs: Rank) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }

    /// Short display symbol: "2"..."9", "T", "J", "Q", "K", "A".
    public var symbol: String {
        switch self {
        case .ten: return "10"
        case .jack: return "J"
        case .queen: return "Q"
        case .king: return "K"
        case .ace: return "A"
        default: return String(rawValue)
        }
    }

    /// Compact single character symbol used in hand labels ("T" instead of "10").
    public var shortSymbol: String {
        if self == .ten { return "T" }
        return symbol
    }

    /// Lowercase singular English name, e.g. "king".
    public var name: String {
        switch self {
        case .two: return "two"
        case .three: return "three"
        case .four: return "four"
        case .five: return "five"
        case .six: return "six"
        case .seven: return "seven"
        case .eight: return "eight"
        case .nine: return "nine"
        case .ten: return "ten"
        case .jack: return "jack"
        case .queen: return "queen"
        case .king: return "king"
        case .ace: return "ace"
        }
    }

    /// Lowercase plural English name, e.g. "kings", "sixes".
    public var pluralName: String {
        if self == .six { return "sixes" }
        return name + "s"
    }
}

/// A single playing card.
public struct Card: Hashable, Codable, Sendable, CustomStringConvertible, Identifiable, Comparable {
    public let rank: Rank
    public let suit: Suit

    public init(_ rank: Rank, _ suit: Suit) {
        self.rank = rank
        self.suit = suit
    }

    /// Stable identifier 0...51.
    public var id: Int {
        return (rank.rawValue - 2) * 4 + suit.rawValue
    }

    public var description: String {
        return rank.shortSymbol + suit.symbol
    }

    /// Sorted by rank first (descending use sites sort explicitly), then suit.
    public static func < (lhs: Card, rhs: Card) -> Bool {
        if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
        return lhs.suit.rawValue < rhs.suit.rawValue
    }
}
