import Foundation

/// One resolved spin with per-bet payouts (§5, §12). The winning pocket is
/// drawn from the seeded RNG alone - the animation, bankroll, and history
/// have no influence (§3).
public struct RouletteSpinResult: Codable, Hashable, Sendable {
    public let seed: UInt64
    public let wheel: RouletteWheel
    public let pocket: Int
    /// Index of the pocket in the wheel's physical order (for animation).
    public let wheelIndex: Int
    public struct BetResult: Codable, Hashable, Sendable {
        public let bet: RouletteBet
        public let won: Bool
        /// Chips returned for this bet (stake + winnings when won).
        public let returned: Int
    }
    public let betResults: [BetResult]

    public var totalStaked: Int { betResults.reduce(0) { $0 + $1.bet.amount } }
    public var totalReturned: Int { betResults.reduce(0) { $0 + $1.returned } }
    public var net: Int { totalReturned - totalStaked }

    public var pocketLabel: String { RoulettePocket.label(pocket) }
    public var color: RoulettePocket.PocketColor { RoulettePocket.color(pocket) }
}

public enum RouletteEngine {

    /// The authoritative winning pocket for a seed. Uniform over the wheel's
    /// pockets; no other input exists, so odds can never shift (§3).
    public static func winningPocket(wheel: RouletteWheel, seed: UInt64) -> (pocket: Int, wheelIndex: Int) {
        var rng = SeededRNG.derive(seed: seed, stream: 71_001)
        let index = rng.int(upperBound: wheel.pocketOrder.count)
        return (wheel.pocketOrder[index], index)
    }

    /// Validates and settles a set of bets for a seeded spin. Overlapping
    /// bets settle independently; zeros lose every outside bet (§5).
    public static func spin(wheel: RouletteWheel, bets: [RouletteBet], seed: UInt64) throws -> RouletteSpinResult {
        for bet in bets {
            if let problem = RouletteLayout.validate(bet, wheel: wheel) {
                throw RouletteError.invalidBet(problem)
            }
        }
        let (pocket, index) = winningPocket(wheel: wheel, seed: seed)
        let results = bets.map { bet -> RouletteSpinResult.BetResult in
            let won = bet.numbers.contains(pocket)
            let returned = won ? bet.amount * (bet.kind.payoutOdds + 1) : 0
            return .init(bet: bet, won: won, returned: returned)
        }
        return RouletteSpinResult(seed: seed, wheel: wheel, pocket: pocket, wheelIndex: index, betResults: results)
    }
}

public enum RouletteError: Error, Equatable {
    case invalidBet(String)
}
