import Foundation

/// Roulette pockets are Ints: 0 = single zero, 1...36, 37 = double zero
/// ("00", American wheel only).
public enum RoulettePocket {
    public static let doubleZero = 37

    public static func label(_ pocket: Int) -> String {
        return pocket == doubleZero ? "00" : "\(pocket)"
    }

    /// Standard red numbers; black is every other 1...36; zeros are green.
    public static let reds: Set<Int> = [1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36]

    public enum PocketColor: String, Codable, Sendable {
        case red, black, green
    }

    public static func color(_ pocket: Int) -> PocketColor {
        if pocket == 0 || pocket == doubleZero { return .green }
        return reds.contains(pocket) ? .red : .black
    }
}

/// Wheel variants (§5). The American wheel's extra pocket raises the house
/// edge — shown, never hidden.
public enum RouletteWheel: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case european
    case american

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .european: return "European"
        case .american: return "American"
        }
    }

    /// House edge on standard bets, for honest display (§5).
    public var houseEdgeDescription: String {
        switch self {
        case .european: return "One zero · house edge 2.7%"
        case .american: return "Zero and double zero · house edge 5.26% (higher)"
        }
    }

    /// Physical pocket order around the wheel, used by the animation and by
    /// the seeded spin. Standard casino orders.
    public var pocketOrder: [Int] {
        switch self {
        case .european:
            return [0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30,
                    8, 23, 10, 5, 24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7,
                    28, 12, 35, 3, 26]
        case .american:
            return [0, 28, 9, 26, 30, 11, 7, 20, 32, 17, 5, 22, 34, 15, 3, 24,
                    36, 13, 1, RoulettePocket.doubleZero, 27, 10, 25, 29, 12, 8,
                    19, 31, 18, 6, 21, 33, 16, 4, 23, 35, 14, 2]
        }
    }

    public var pocketCount: Int {
        return self == .european ? 37 : 38
    }
}

/// Every supported bet type with its standard payout odds (§5).
public enum RouletteBetKind: String, Codable, Hashable, Sendable, CaseIterable {
    case straightUp   // 35:1
    case split        // 17:1
    case street       // 11:1
    case corner       // 8:1
    case sixLine      // 5:1
    case dozen        // 2:1
    case column       // 2:1
    case red, black   // 1:1
    case odd, even    // 1:1
    case low, high    // 1:1

    /// Winnings per chip staked (stake returned separately).
    public var payoutOdds: Int {
        switch self {
        case .straightUp: return 35
        case .split: return 17
        case .street: return 11
        case .corner: return 8
        case .sixLine: return 5
        case .dozen, .column: return 2
        case .red, .black, .odd, .even, .low, .high: return 1
        }
    }

    public var displayName: String {
        switch self {
        case .straightUp: return "Straight up"
        case .split: return "Split"
        case .street: return "Street"
        case .corner: return "Corner"
        case .sixLine: return "Six line"
        case .dozen: return "Dozen"
        case .column: return "Column"
        case .red: return "Red"
        case .black: return "Black"
        case .odd: return "Odd"
        case .even: return "Even"
        case .low: return "Low 1–18"
        case .high: return "High 19–36"
        }
    }
}

/// A placed bet: a kind, the pockets it covers, and a stake.
public struct RouletteBet: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public let kind: RouletteBetKind
    /// Covered pockets, validated against the legal layout.
    public let numbers: Set<Int>
    public var amount: Int

    public init(id: UUID = UUID(), kind: RouletteBetKind, numbers: Set<Int>, amount: Int) {
        self.id = id
        self.kind = kind
        self.numbers = numbers
        self.amount = amount
    }

    public var label: String {
        switch kind {
        case .straightUp, .split, .street, .corner, .sixLine:
            let sorted = numbers.sorted().map { RoulettePocket.label($0) }
            return "\(kind.displayName) \(sorted.joined(separator: "·"))"
        case .dozen:
            let low = numbers.min() ?? 1
            return low == 1 ? "1st dozen" : (low == 13 ? "2nd dozen" : "3rd dozen")
        case .column:
            let low = numbers.min() ?? 1
            return "Column \(low)"
        default:
            return kind.displayName
        }
    }
}

/// Layout validation (§5): chips can only sit on legal, unambiguous spots.
public enum RouletteLayout {

    /// Row (0-based) and column (0-based, 0 = numbers 1,4,7…) of 1...36.
    static func position(of number: Int) -> (row: Int, column: Int)? {
        guard (1...36).contains(number) else { return nil }
        return ((number - 1) / 3, (number - 1) % 3)
    }

    /// All legal splits: horizontal and vertical neighbours, plus zero splits.
    public static func legalSplits(wheel: RouletteWheel) -> Set<Set<Int>> {
        var result: Set<Set<Int>> = []
        for n in 1...36 {
            guard let pos = position(of: n) else { continue }
            if pos.column < 2 { result.insert([n, n + 1]) }
            if pos.row < 11 { result.insert([n, n + 3]) }
        }
        result.insert([0, 1]); result.insert([0, 2]); result.insert([0, 3])
        if wheel == .american {
            let dz = RoulettePocket.doubleZero
            result.insert([dz, 2]); result.insert([dz, 3]); result.insert([0, dz])
        }
        return result
    }

    /// The twelve standard streets.
    public static var legalStreets: Set<Set<Int>> {
        var result: Set<Set<Int>> = []
        for row in 0..<12 {
            result.insert([row * 3 + 1, row * 3 + 2, row * 3 + 3])
        }
        return result
    }

    /// All legal 2×2 corners.
    public static var legalCorners: Set<Set<Int>> {
        var result: Set<Set<Int>> = []
        for n in 1...36 {
            guard let pos = position(of: n), pos.column < 2, pos.row < 11 else { continue }
            result.insert([n, n + 1, n + 3, n + 4])
        }
        return result
    }

    /// All legal six lines (two adjacent streets).
    public static var legalSixLines: Set<Set<Int>> {
        var result: Set<Set<Int>> = []
        for row in 0..<11 {
            let start = row * 3 + 1
            result.insert(Set(start...(start + 5)))
        }
        return result
    }

    public static let dozens: [Set<Int>] = [
        Set(1...12), Set(13...24), Set(25...36)
    ]

    /// Columns keyed by their lowest number (1, 2, 3).
    public static let columns: [Set<Int>] = [
        Set(stride(from: 1, through: 34, by: 3)),
        Set(stride(from: 2, through: 35, by: 3)),
        Set(stride(from: 3, through: 36, by: 3))
    ]

    /// Validates a bet's coverage for the wheel. Returns nil when legal, or a
    /// human-readable problem.
    public static func validate(_ bet: RouletteBet, wheel: RouletteWheel) -> String? {
        guard bet.amount > 0 else { return "bet has no stake" }
        let numbers = bet.numbers
        let validPockets = Set(wheel.pocketOrder)
        guard numbers.isSubset(of: validPockets) else { return "bet covers pockets not on this wheel" }
        switch bet.kind {
        case .straightUp:
            guard numbers.count == 1 else { return "straight-up covers one number" }
        case .split:
            guard legalSplits(wheel: wheel).contains(numbers) else { return "not an adjacent split" }
        case .street:
            guard legalStreets.contains(numbers) else { return "not a legal street" }
        case .corner:
            guard legalCorners.contains(numbers) else { return "not a legal corner" }
        case .sixLine:
            guard legalSixLines.contains(numbers) else { return "not a legal six line" }
        case .dozen:
            guard dozens.contains(numbers) else { return "not a dozen" }
        case .column:
            guard columns.contains(numbers) else { return "not a column" }
        case .red:
            guard numbers == RoulettePocket.reds else { return "red bet must cover the red numbers" }
        case .black:
            guard numbers == Set(1...36).subtracting(RoulettePocket.reds) else { return "black bet must cover the black numbers" }
        case .odd:
            guard numbers == Set((1...36).filter { $0 % 2 == 1 }) else { return "odd bet malformed" }
        case .even:
            guard numbers == Set((1...36).filter { $0 % 2 == 0 }) else { return "even bet malformed" }
        case .low:
            guard numbers == Set(1...18) else { return "low bet malformed" }
        case .high:
            guard numbers == Set(19...36) else { return "high bet malformed" }
        }
        return nil
    }

    /// Convenience constructors for outside bets.
    public static func outsideBet(_ kind: RouletteBetKind, amount: Int) -> RouletteBet? {
        switch kind {
        case .red: return RouletteBet(kind: .red, numbers: RoulettePocket.reds, amount: amount)
        case .black: return RouletteBet(kind: .black, numbers: Set(1...36).subtracting(RoulettePocket.reds), amount: amount)
        case .odd: return RouletteBet(kind: .odd, numbers: Set((1...36).filter { $0 % 2 == 1 }), amount: amount)
        case .even: return RouletteBet(kind: .even, numbers: Set((1...36).filter { $0 % 2 == 0 }), amount: amount)
        case .low: return RouletteBet(kind: .low, numbers: Set(1...18), amount: amount)
        case .high: return RouletteBet(kind: .high, numbers: Set(19...36), amount: amount)
        default: return nil
        }
    }
}
