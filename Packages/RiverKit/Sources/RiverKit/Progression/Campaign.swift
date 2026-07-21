import Foundation

/// One Stakes Ladder tier (§23). All values are configuration, not code.
public struct CampaignTier: Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let purpose: String
    public let difficulty: BotDifficulty
    public let lineup: [BotProfile]
    public let bossName: String
    public let bossDescription: String
    public let bossLineup: [BotProfile]
    /// Variance-tolerant objectives (§24): decision quality over luck.
    public let handsRequired: Int
    /// Maximum blunders+significant mistakes per 100 analyzed decisions.
    public let maxSevereMistakeRate: Double
    /// Assistance allowed without a completion penalty (informational).
    public let suggestedAssistance: AssistanceHint

    public enum AssistanceHint: String, Sendable {
        case guided, hints, pure
    }
}

/// Per-tier progress, persisted (§52).
public struct TierProgress: Codable, Hashable, Sendable {
    public var handsPlayed: Int = 0
    public var analyzedDecisions: Int = 0
    public var severeMistakes: Int = 0
    public var bossHandsPlayed: Int = 0
    public var bossDecisions: Int = 0
    public var bossSevereMistakes: Int = 0
    public var completed: Bool = false

    public init() {}

    public var severeMistakeRate: Double {
        guard analyzedDecisions > 0 else { return 0 }
        return Double(severeMistakes) / Double(analyzedDecisions) * 100
    }
}

public struct CampaignProgress: Codable, Hashable, Sendable {
    public var tiers: [Int: TierProgress] = [:]

    public init() {}

    public func progress(for tier: Int) -> TierProgress {
        return tiers[tier] ?? TierProgress()
    }

    public var highestUnlockedTier: Int {
        var tier = 1
        while tier < CampaignLibrary.tiers.count && progress(for: tier).completed {
            tier += 1
        }
        return tier
    }

    /// Records a completed hand's grades toward a tier (boss table or normal).
    public mutating func record(tier: Int, isBoss: Bool, decisions: Int, severe: Int) {
        var state = progress(for: tier)
        if isBoss {
            state.bossHandsPlayed += 1
            state.bossDecisions += decisions
            state.bossSevereMistakes += severe
        } else {
            state.handsPlayed += 1
            state.analyzedDecisions += decisions
            state.severeMistakes += severe
        }
        // Completion check (§24): volume + decision quality + boss table.
        if let definition = CampaignLibrary.tier(tier) {
            let normalDone = state.handsPlayed >= definition.handsRequired
                && state.severeMistakeRate <= definition.maxSevereMistakeRate
            let bossDone = state.bossHandsPlayed >= CampaignLibrary.bossHandsRequired
                && (state.bossDecisions == 0
                    || Double(state.bossSevereMistakes) / Double(max(1, state.bossDecisions)) * 100 <= definition.maxSevereMistakeRate * 1.5)
            if normalDone && bossDone {
                state.completed = true
            }
        }
        tiers[tier] = state
    }
}

/// The seven-tier ladder (§23) and its boss characters (§25). Bosses are
/// strong or unusual — never cheating.
public enum CampaignLibrary {

    public static let bossHandsRequired = 20

    public static func tier(_ id: Int) -> CampaignTier? {
        return tiers.first { $0.id == id }
    }

    public static let tiers: [CampaignTier] = [
        CampaignTier(
            id: 1, name: "Kitchen Table",
            purpose: "Learn the controls and spot the obvious mistakes.",
            difficulty: .beginner,
            lineup: [
                .callingStation(name: "Gus", symbolName: "cup.and.saucer.fill", difficulty: .beginner),
                .callingStation(name: "Peppa", symbolName: "teddybear.fill", difficulty: .beginner),
                .nit(name: "Marta", symbolName: "eyeglasses", difficulty: .beginner),
                .nit(name: "Olen", symbolName: "clock.fill", difficulty: .beginner),
                .looseAggressive(name: "Bobby", symbolName: "bicycle", difficulty: .beginner)
            ],
            bossName: "The Collector",
            bossDescription: "Never folds a pair, never believes your story. Bluffs die here — value bets feast.",
            bossLineup: [
                .callingStation(name: "The Collector", symbolName: "archivebox.fill", difficulty: .intermediate),
                .callingStation(name: "Peppa", symbolName: "teddybear.fill", difficulty: .beginner),
                .nit(name: "Marta", symbolName: "eyeglasses", difficulty: .beginner),
                .callingStation(name: "Gus", symbolName: "cup.and.saucer.fill", difficulty: .beginner),
                .nit(name: "Olen", symbolName: "clock.fill", difficulty: .beginner)
            ],
            handsRequired: 30, maxSevereMistakeRate: 20, suggestedAssistance: .guided
        ),
        CampaignTier(
            id: 2, name: "Campus Game",
            purpose: "Position, opening ranges, and honest value betting.",
            difficulty: .beginner,
            lineup: [
                .looseAggressive(name: "Dana", symbolName: "bolt.fill", difficulty: .beginner),
                .callingStation(name: "Tomo", symbolName: "backpack.fill", difficulty: .beginner),
                .nit(name: "Priya", symbolName: "book.fill", difficulty: .intermediate),
                .looseAggressive(name: "Rex", symbolName: "flame.fill", difficulty: .beginner),
                .callingStation(name: "Milo", symbolName: "gamecontroller.fill", difficulty: .beginner)
            ],
            bossName: "The Wall",
            bossDescription: "Folds, folds, folds — then appears with the nuts. Steal small pots; believe big bets.",
            bossLineup: [
                .nit(name: "The Wall", symbolName: "square.stack.3d.up.fill", difficulty: .advanced),
                .nit(name: "Priya", symbolName: "book.fill", difficulty: .intermediate),
                .callingStation(name: "Tomo", symbolName: "backpack.fill", difficulty: .beginner),
                .looseAggressive(name: "Dana", symbolName: "bolt.fill", difficulty: .beginner),
                .callingStation(name: "Milo", symbolName: "gamecontroller.fill", difficulty: .beginner)
            ],
            handsRequired: 40, maxSevereMistakeRate: 15, suggestedAssistance: .guided
        ),
        CampaignTier(
            id: 3, name: "Local Room",
            purpose: "Three-bets, continuation bets, and blind defence.",
            difficulty: .intermediate,
            lineup: BotProfile.defaultLineup(difficulty: .intermediate),
            bossName: "The Flood",
            bossDescription: "Pressure on every street. Your bluff catchers will be tested — bring discipline.",
            bossLineup: [
                .maniac(name: "The Flood", symbolName: "water.waves", difficulty: .advanced),
                .looseAggressive(name: "Dana", symbolName: "bolt.fill", difficulty: .intermediate),
                .nit(name: "Ivan", symbolName: "clock.fill", difficulty: .intermediate),
                .callingStation(name: "Gus", symbolName: "cup.and.saucer.fill", difficulty: .intermediate),
                .solidRegular(name: "Vera", symbolName: "chart.bar.fill", difficulty: .intermediate)
            ],
            handsRequired: 50, maxSevereMistakeRate: 12, suggestedAssistance: .hints
        ),
        CampaignTier(
            id: 4, name: "City Regulars",
            purpose: "Range awareness, turn play, and adapting to opponents.",
            difficulty: .intermediate,
            lineup: [
                .solidRegular(name: "Vera", symbolName: "chart.bar.fill", difficulty: .intermediate),
                .solidRegular(name: "Hollis", symbolName: "briefcase.fill", difficulty: .intermediate),
                .looseAggressive(name: "Dana", symbolName: "bolt.fill", difficulty: .intermediate),
                .trapper(name: "Sable", symbolName: "moon.fill", difficulty: .intermediate),
                .nit(name: "Ivan", symbolName: "clock.fill", difficulty: .intermediate)
            ],
            bossName: "The Mirror",
            bossDescription: "Watches everything you do and adjusts. Vary your play or be read like a book.",
            bossLineup: [
                .solidRegular(name: "The Mirror", symbolName: "circle.grid.cross.fill", difficulty: .advanced),
                .solidRegular(name: "Hollis", symbolName: "briefcase.fill", difficulty: .intermediate),
                .trapper(name: "Sable", symbolName: "moon.fill", difficulty: .intermediate),
                .looseAggressive(name: "Dana", symbolName: "bolt.fill", difficulty: .intermediate),
                .nit(name: "Ivan", symbolName: "clock.fill", difficulty: .intermediate)
            ],
            handsRequired: 60, maxSevereMistakeRate: 10, suggestedAssistance: .hints
        ),
        CampaignTier(
            id: 5, name: "Private Game",
            purpose: "Unusual styles and strong exploitative adjustments.",
            difficulty: .advanced,
            lineup: BotProfile.defaultLineup(difficulty: .advanced),
            bossName: "The Surgeon",
            bossDescription: "Precise sizes, disciplined rivers, few mistakes. Win by making fewer.",
            bossLineup: [
                .solidRegular(name: "The Surgeon", symbolName: "scissors", difficulty: .elite),
                .trapper(name: "Sable", symbolName: "moon.fill", difficulty: .advanced),
                .maniac(name: "Kaz", symbolName: "tornado", difficulty: .advanced),
                .callingStation(name: "Gus", symbolName: "cup.and.saucer.fill", difficulty: .advanced),
                .looseAggressive(name: "Dana", symbolName: "bolt.fill", difficulty: .advanced)
            ],
            handsRequired: 70, maxSevereMistakeRate: 8, suggestedAssistance: .hints
        ),
        CampaignTier(
            id: 6, name: "High Stakes",
            purpose: "Advanced opponents, hard rivers, mixed strategies.",
            difficulty: .advanced,
            lineup: [
                .solidRegular(name: "Vera", symbolName: "chart.bar.fill", difficulty: .elite),
                .looseAggressive(name: "Dana", symbolName: "bolt.fill", difficulty: .elite),
                .trapper(name: "Sable", symbolName: "moon.fill", difficulty: .advanced),
                .maniac(name: "Kaz", symbolName: "tornado", difficulty: .advanced),
                .solidRegular(name: "Hollis", symbolName: "briefcase.fill", difficulty: .advanced)
            ],
            bossName: "The Flood Returns",
            bossDescription: "The pressure game, perfected. Elite aggression with a memory.",
            bossLineup: [
                .maniac(name: "The Flood", symbolName: "water.waves", difficulty: .elite),
                .looseAggressive(name: "Dana", symbolName: "bolt.fill", difficulty: .elite),
                .solidRegular(name: "Vera", symbolName: "chart.bar.fill", difficulty: .elite),
                .trapper(name: "Sable", symbolName: "moon.fill", difficulty: .advanced),
                .solidRegular(name: "Hollis", symbolName: "briefcase.fill", difficulty: .advanced)
            ],
            handsRequired: 80, maxSevereMistakeRate: 7, suggestedAssistance: .pure
        ),
        CampaignTier(
            id: 7, name: "Final Table",
            purpose: "The complete test: elite lineup, minimal help.",
            difficulty: .elite,
            lineup: BotProfile.defaultLineup(difficulty: .elite),
            bossName: "The Finalist",
            bossDescription: "A tournament killer at a cash table. Stack pressure, ICM instincts, zero charity.",
            bossLineup: [
                .solidRegular(name: "The Finalist", symbolName: "crown.fill", difficulty: .elite),
                .solidRegular(name: "The Surgeon", symbolName: "scissors", difficulty: .elite),
                .maniac(name: "The Flood", symbolName: "water.waves", difficulty: .elite),
                .nit(name: "The Wall", symbolName: "square.stack.3d.up.fill", difficulty: .elite),
                .callingStation(name: "The Collector", symbolName: "archivebox.fill", difficulty: .elite)
            ],
            handsRequired: 100, maxSevereMistakeRate: 6, suggestedAssistance: .pure
        )
    ]
}
