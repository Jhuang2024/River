import Foundation

/// One completed casino round (§12): mode, timestamp, seed, wager, outcome,
/// payout and the game-specific record needed to reconstruct and inspect it.
/// Seeds are shown to the player after the round for fairness (§3).
public struct CasinoRoundRecord: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public let game: CasinoGameKind
    public let date: Date
    public let seed: UInt64
    public let wagered: Int
    public let returned: Int
    /// Short human-readable outcome ("Dealer busts", "17 red", "3.3x").
    public let outcomeSummary: String
    public let detail: Detail

    public enum Detail: Codable, Hashable, Sendable {
        case blackjack(BlackjackDetail)
        case roulette(RouletteDetail)
        case plinko(PlinkoDetail)
    }

    /// Blackjack keeps cards, actions and strategy evaluation (§12).
    public struct BlackjackDetail: Codable, Hashable, Sendable {
        public struct HandRecord: Codable, Hashable, Sendable {
            public let cards: [BlackjackCard]
            public let actions: [BlackjackAction]
            public let outcome: BlackjackHandOutcome
            public let bet: Int
            public let returned: Int
            /// Actions that deviated from basic strategy, with what it said.
            public let strategyMistakes: [String]

            public init(cards: [BlackjackCard], actions: [BlackjackAction], outcome: BlackjackHandOutcome,
                        bet: Int, returned: Int, strategyMistakes: [String]) {
                self.cards = cards
                self.actions = actions
                self.outcome = outcome
                self.bet = bet
                self.returned = returned
                self.strategyMistakes = strategyMistakes
            }
        }
        public let hands: [HandRecord]
        public let dealerCards: [BlackjackCard]
        public let insuranceBet: Int
        public let insuranceReturned: Int
        public let rules: BlackjackRules

        public init(hands: [HandRecord], dealerCards: [BlackjackCard], insuranceBet: Int, insuranceReturned: Int, rules: BlackjackRules) {
            self.hands = hands
            self.dealerCards = dealerCards
            self.insuranceBet = insuranceBet
            self.insuranceReturned = insuranceReturned
            self.rules = rules
        }
    }

    /// Roulette keeps every placed bet and its individual payout (§12).
    public struct RouletteDetail: Codable, Hashable, Sendable {
        public let wheel: RouletteWheel
        public let pocket: Int
        public let bets: [RouletteSpinResult.BetResult]

        public init(wheel: RouletteWheel, pocket: Int, bets: [RouletteSpinResult.BetResult]) {
            self.wheel = wheel
            self.pocket = pocket
            self.bets = bets
        }
    }

    /// Plinko keeps the board, risk, slot, multiplier and path (§12).
    public struct PlinkoDetail: Codable, Hashable, Sendable {
        public let rows: PlinkoRows
        public let risk: PlinkoRisk
        public let slot: Int
        public let multiplierHundredths: Int
        public let path: [Bool]

        public init(rows: PlinkoRows, risk: PlinkoRisk, slot: Int, multiplierHundredths: Int, path: [Bool]) {
            self.rows = rows
            self.risk = risk
            self.slot = slot
            self.multiplierHundredths = multiplierHundredths
            self.path = path
        }
    }

    public init(id: UUID = UUID(), game: CasinoGameKind, date: Date, seed: UInt64,
                wagered: Int, returned: Int, outcomeSummary: String, detail: Detail) {
        self.id = id
        self.game = game
        self.date = date
        self.seed = seed
        self.wagered = wagered
        self.returned = returned
        self.outcomeSummary = outcomeSummary
        self.detail = detail
    }

    public var net: Int { returned - wagered }
}

/// Aggregated statistics per game and across the floor (§4, §5, §6, §8).
/// Pure functions over the stored records.
public struct CasinoStats: Hashable, Sendable {
    public var rounds = 0
    public var totalWagered = 0
    public var totalReturned = 0
    public var largestWin = 0

    // Blackjack (§6)
    public var bjWins = 0
    public var bjLosses = 0
    public var bjPushes = 0
    public var bjBlackjacks = 0
    public var bjDoubles = 0
    public var bjSplits = 0
    public var bjSurrenders = 0
    public var bjInsuranceTaken = 0
    public var bjInsuranceWon = 0
    public var bjDecisions = 0
    public var bjStrategyMistakes = 0

    // Roulette (§5)
    public var rouletteWinsByKind: [RouletteBetKind: Int] = [:]
    public var rouletteBetsByKind: [RouletteBetKind: Int] = [:]
    public var pocketFrequency: [Int: Int] = [:]
    public var redCount = 0
    public var blackCount = 0
    public var greenCount = 0
    public var europeanSpins = 0
    public var americanSpins = 0

    // Plinko (§4)
    public var ballsDropped = 0
    public var highestMultiplierHundredths = 0
    public var multiplierSumHundredths = 0
    public var longestLosingStreak = 0
    public var slotDistribution: [Int: Int] = [:]
    public var resultsByRows: [Int: Int] = [:]
    public var resultsByRisk: [PlinkoRisk: Int] = [:]

    public var net: Int { totalReturned - totalWagered }

    public var bjDecisionAccuracy: Double {
        guard bjDecisions > 0 else { return 0 }
        return Double(bjDecisions - bjStrategyMistakes) / Double(bjDecisions)
    }

    public var averageMultiplierHundredths: Int {
        guard ballsDropped > 0 else { return 0 }
        return multiplierSumHundredths / ballsDropped
    }

    /// Aggregates records (optionally one game only).
    public static func compute(records: [CasinoRoundRecord], game: CasinoGameKind? = nil) -> CasinoStats {
        var stats = CasinoStats()
        var plinkoLosingRun = 0
        for record in records {
            if let game, record.game != game { continue }
            stats.rounds += 1
            stats.totalWagered += record.wagered
            stats.totalReturned += record.returned
            stats.largestWin = max(stats.largestWin, record.net)

            switch record.detail {
            case .blackjack(let detail):
                for hand in detail.hands {
                    switch hand.outcome {
                    case .win: stats.bjWins += 1
                    case .blackjack:
                        stats.bjWins += 1
                        stats.bjBlackjacks += 1
                    case .push: stats.bjPushes += 1
                    case .loss, .bust, .dealerBlackjack: stats.bjLosses += 1
                    case .surrender:
                        stats.bjLosses += 1
                        stats.bjSurrenders += 1
                    }
                    if hand.actions.contains(.double) { stats.bjDoubles += 1 }
                    if hand.actions.contains(.split) { stats.bjSplits += 1 }
                    stats.bjDecisions += hand.actions.count
                    stats.bjStrategyMistakes += hand.strategyMistakes.count
                }
                if detail.insuranceBet > 0 {
                    stats.bjInsuranceTaken += 1
                    if detail.insuranceReturned > 0 { stats.bjInsuranceWon += 1 }
                }
            case .roulette(let detail):
                if detail.wheel == .european { stats.europeanSpins += 1 } else { stats.americanSpins += 1 }
                stats.pocketFrequency[detail.pocket, default: 0] += 1
                switch RoulettePocket.color(detail.pocket) {
                case .red: stats.redCount += 1
                case .black: stats.blackCount += 1
                case .green: stats.greenCount += 1
                }
                for betResult in detail.bets {
                    stats.rouletteBetsByKind[betResult.bet.kind, default: 0] += 1
                    if betResult.won {
                        stats.rouletteWinsByKind[betResult.bet.kind, default: 0] += 1
                    }
                }
            case .plinko(let detail):
                stats.ballsDropped += 1
                stats.highestMultiplierHundredths = max(stats.highestMultiplierHundredths, detail.multiplierHundredths)
                stats.multiplierSumHundredths += detail.multiplierHundredths
                stats.slotDistribution[detail.slot, default: 0] += 1
                stats.resultsByRows[detail.rows.rawValue, default: 0] += 1
                stats.resultsByRisk[detail.risk, default: 0] += 1
                if record.net < 0 {
                    plinkoLosingRun += 1
                    stats.longestLosingStreak = max(stats.longestLosingStreak, plinkoLosingRun)
                } else {
                    plinkoLosingRun = 0
                }
            }
        }
        return stats
    }
}

/// Casino achievements (§10): variety and skill, never volume-of-losses.
public enum CasinoAchievementLibrary {

    public static let all: [AchievementDefinition] = [
        AchievementDefinition(id: "cas.plinko.100", title: "Century Drop", detail: "Drop 100 Plinko balls.", symbolName: "circle.grid.3x3.fill"),
        AchievementDefinition(id: "cas.plinko.edge", title: "Edge Case", detail: "Land a ball in an edge slot.", symbolName: "arrow.down.to.line"),
        AchievementDefinition(id: "cas.plinko.session50", title: "Long Runner", detail: "Complete a 50-ball Plinko session.", symbolName: "repeat"),
        AchievementDefinition(id: "cas.plinko.even", title: "House Weather", detail: "Finish a 20+ ball session within 10% of break-even.", symbolName: "equal.circle"),
        AchievementDefinition(id: "cas.roulette.varied", title: "Full Spread", detail: "Place every roulette bet type at least once.", symbolName: "square.grid.3x3.topleft.filled"),
        AchievementDefinition(id: "cas.roulette.straight", title: "Called It", detail: "Win a straight-up roulette bet.", symbolName: "target"),
        AchievementDefinition(id: "cas.roulette.100", title: "Wheel Regular", detail: "Complete 100 spins.", symbolName: "circle.circle"),
        AchievementDefinition(id: "cas.roulette.multi", title: "Spread the Table", detail: "Win with three or more bets on one spin.", symbolName: "square.stack.3d.up"),
        AchievementDefinition(id: "cas.bj.natural", title: "Natural", detail: "Be dealt a blackjack.", symbolName: "sparkles"),
        AchievementDefinition(id: "cas.bj.100correct", title: "By the Book", detail: "Make 100 correct basic-strategy decisions.", symbolName: "book.fill"),
        AchievementDefinition(id: "cas.bj.cleanshoe", title: "Clean Shoe", detail: "Play 20 consecutive decisions without a strategy mistake.", symbolName: "checkmark.shield.fill"),
        AchievementDefinition(id: "cas.bj.counted", title: "Kept the Count", detail: "Count a full practice shoe correctly.", symbolName: "number.circle.fill")
    ]

    /// Extra evidence the record log can't hold (drill results, sessions).
    public struct Evidence: Sendable {
        public let records: [CasinoRoundRecord]
        public let plinkoSessionLengths: [Int]
        /// Session (length, |net| ÷ wagered) pairs for break-even checks.
        public let plinkoSessionCloseness: [(balls: Int, drift: Double)]
        public let fullShoeCountedCorrectly: Bool
        public let longestCorrectDecisionRun: Int

        public init(records: [CasinoRoundRecord],
                    plinkoSessionLengths: [Int] = [],
                    plinkoSessionCloseness: [(balls: Int, drift: Double)] = [],
                    fullShoeCountedCorrectly: Bool = false,
                    longestCorrectDecisionRun: Int = 0) {
            self.records = records
            self.plinkoSessionLengths = plinkoSessionLengths
            self.plinkoSessionCloseness = plinkoSessionCloseness
            self.fullShoeCountedCorrectly = fullShoeCountedCorrectly
            self.longestCorrectDecisionRun = longestCorrectDecisionRun
        }
    }

    public static func unlocked(evidence: Evidence) -> Set<String> {
        var result = Set<String>()
        let stats = CasinoStats.compute(records: evidence.records)

        if stats.ballsDropped >= 100 { result.insert("cas.plinko.100") }
        if evidence.plinkoSessionLengths.contains(where: { $0 >= 50 }) { result.insert("cas.plinko.session50") }
        if evidence.plinkoSessionCloseness.contains(where: { $0.balls >= 20 && $0.drift <= 0.10 }) {
            result.insert("cas.plinko.even")
        }
        for record in evidence.records {
            if case .plinko(let detail) = record.detail {
                if detail.slot == 0 || detail.slot == detail.rows.rawValue {
                    result.insert("cas.plinko.edge")
                }
            }
            if case .roulette(let detail) = record.detail {
                if detail.bets.filter({ $0.won }).count >= 3 { result.insert("cas.roulette.multi") }
            }
        }
        let placedKinds = Set(stats.rouletteBetsByKind.filter { $0.value > 0 }.keys)
        if placedKinds == Set(RouletteBetKind.allCases) { result.insert("cas.roulette.varied") }
        if (stats.rouletteWinsByKind[.straightUp] ?? 0) > 0 { result.insert("cas.roulette.straight") }
        if stats.europeanSpins + stats.americanSpins >= 100 { result.insert("cas.roulette.100") }

        if stats.bjBlackjacks > 0 { result.insert("cas.bj.natural") }
        if stats.bjDecisions - stats.bjStrategyMistakes >= 100 { result.insert("cas.bj.100correct") }
        if evidence.longestCorrectDecisionRun >= 20 { result.insert("cas.bj.cleanshoe") }
        if evidence.fullShoeCountedCorrectly { result.insert("cas.bj.counted") }
        return result
    }
}
