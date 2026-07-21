import Foundation

/// Recognizable playing styles (§9). Archetypes are bounded modifications of
/// one coherent strategic baseline, not unrelated procedural code.
public enum BotArchetype: String, Codable, CaseIterable, Sendable {
    case nit
    case callingStation
    case looseAggressive
    case maniac
    case solidRegular
    case trapper

    public var displayName: String {
        switch self {
        case .nit: return "Nit"
        case .callingStation: return "Calling Station"
        case .looseAggressive: return "Loose-Aggressive"
        case .maniac: return "Maniac"
        case .solidRegular: return "Solid Regular"
        case .trapper: return "Trapper"
        }
    }
}

/// Difficulty changes strategic quality only — never dealt cards (§10).
public enum BotDifficulty: String, Codable, CaseIterable, Sendable {
    case beginner
    case intermediate
    case advanced
    case elite

    public var displayName: String {
        switch self {
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .advanced: return "Advanced"
        case .elite: return "Elite"
        }
    }

    /// Monte Carlo budget for one bot decision (§17, §46).
    public var equityIterations: Int {
        switch self {
        case .beginner: return 90
        case .intermediate: return 160
        case .advanced: return 260
        case .elite: return 380
        }
    }

    /// Score noise: beginners misjudge spots, elite bots rarely do.
    public var decisionNoise: Double {
        switch self {
        case .beginner: return 0.5
        case .intermediate: return 0.22
        case .advanced: return 0.1
        case .elite: return 0.05
        }
    }
}

/// Tunable personality for one AI opponent. Parameters shift frequencies and
/// thresholds; they never override legal play.
public struct BotProfile: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    /// SF Symbol name used as the avatar.
    public var symbolName: String
    public var archetype: BotArchetype
    public var difficulty: BotDifficulty
    /// 0...1: fraction of starting hands willingly played.
    public var looseness: Double
    /// 0...1: preference for betting/raising over calling.
    public var aggression: Double
    /// 0...1: how often bluffing lines are taken when available.
    public var bluffFrequency: Double
    /// 0...1: reluctance to fold to aggression once invested.
    public var callStickiness: Double
    /// 0...1: how much bet sizes wander from standard sizings.
    public var sizingJitter: Double
    /// 0...1: how well position adjusts opening/calling ranges.
    public var positionAwareness: Double
    /// Short flavor note shown on the opponent card.
    public var note: String

    public init(id: UUID = UUID(), name: String, symbolName: String, archetype: BotArchetype, difficulty: BotDifficulty, looseness: Double, aggression: Double, bluffFrequency: Double, callStickiness: Double, sizingJitter: Double, positionAwareness: Double, note: String) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.archetype = archetype
        self.difficulty = difficulty
        self.looseness = looseness
        self.aggression = aggression
        self.bluffFrequency = bluffFrequency
        self.callStickiness = callStickiness
        self.sizingJitter = sizingJitter
        self.positionAwareness = positionAwareness
        self.note = note
    }

    // MARK: - Presets

    public static func nit(name: String, symbolName: String, difficulty: BotDifficulty) -> BotProfile {
        return BotProfile(
            name: name,
            symbolName: symbolName,
            archetype: .nit,
            difficulty: difficulty,
            looseness: 0.11,
            aggression: 0.45,
            bluffFrequency: 0.05,
            callStickiness: 0.15,
            sizingJitter: 0.10,
            positionAwareness: difficulty == .beginner ? 0.2 : 0.6,
            note: "Plays very few hands. Big bets mean business."
        )
    }

    public static func callingStation(name: String, symbolName: String, difficulty: BotDifficulty) -> BotProfile {
        return BotProfile(
            name: name,
            symbolName: symbolName,
            archetype: .callingStation,
            difficulty: difficulty,
            looseness: 0.55,
            aggression: 0.15,
            bluffFrequency: 0.03,
            callStickiness: 0.85,
            sizingJitter: 0.25,
            positionAwareness: difficulty == .beginner ? 0.1 : 0.35,
            note: "Hates folding. Don't bluff — value bet relentlessly."
        )
    }

    public static func looseAggressive(name: String, symbolName: String, difficulty: BotDifficulty) -> BotProfile {
        return BotProfile(
            name: name,
            symbolName: symbolName,
            archetype: .looseAggressive,
            difficulty: difficulty,
            looseness: 0.42,
            aggression: 0.78,
            bluffFrequency: 0.35,
            callStickiness: 0.45,
            sizingJitter: 0.30,
            positionAwareness: difficulty == .beginner ? 0.3 : 0.7,
            note: "Constant pressure, plenty of bluffs. Buckle up."
        )
    }

    public static func maniac(name: String, symbolName: String, difficulty: BotDifficulty) -> BotProfile {
        return BotProfile(
            name: name,
            symbolName: symbolName,
            archetype: .maniac,
            difficulty: difficulty,
            looseness: 0.62,
            aggression: 0.95,
            bluffFrequency: 0.55,
            callStickiness: 0.55,
            sizingJitter: 0.45,
            positionAwareness: difficulty == .beginner ? 0.2 : 0.5,
            note: "Raises everything, overbets often. Let them hang themselves."
        )
    }

    public static func solidRegular(name: String, symbolName: String, difficulty: BotDifficulty) -> BotProfile {
        return BotProfile(
            name: name,
            symbolName: symbolName,
            archetype: .solidRegular,
            difficulty: difficulty,
            looseness: 0.30,
            aggression: 0.60,
            bluffFrequency: 0.25,
            callStickiness: 0.42,
            sizingJitter: 0.12,
            positionAwareness: 0.85,
            note: "Disciplined ranges, sensible sizes. Few easy chips here."
        )
    }

    public static func trapper(name: String, symbolName: String, difficulty: BotDifficulty) -> BotProfile {
        return BotProfile(
            name: name,
            symbolName: symbolName,
            archetype: .trapper,
            difficulty: difficulty,
            looseness: 0.24,
            aggression: 0.35,
            bluffFrequency: 0.12,
            callStickiness: 0.6,
            sizingJitter: 0.18,
            positionAwareness: 0.6,
            note: "Quiet until it isn't. Sudden raises mean monsters."
        )
    }

    /// The standard five-bot lineup for a quick cash session. Higher
    /// difficulties introduce the fuller archetype cast.
    public static func defaultLineup(difficulty: BotDifficulty) -> [BotProfile] {
        switch difficulty {
        case .beginner, .intermediate:
            return [
                .nit(name: "Marta", symbolName: "eyeglasses", difficulty: difficulty),
                .callingStation(name: "Gus", symbolName: "cup.and.saucer.fill", difficulty: difficulty),
                .looseAggressive(name: "Dana", symbolName: "bolt.fill", difficulty: difficulty),
                .nit(name: "Ivan", symbolName: "clock.fill", difficulty: difficulty),
                .looseAggressive(name: "Rex", symbolName: "flame.fill", difficulty: difficulty)
            ]
        case .advanced, .elite:
            return [
                .solidRegular(name: "Vera", symbolName: "chart.bar.fill", difficulty: difficulty),
                .callingStation(name: "Gus", symbolName: "cup.and.saucer.fill", difficulty: difficulty),
                .looseAggressive(name: "Dana", symbolName: "bolt.fill", difficulty: difficulty),
                .maniac(name: "Kaz", symbolName: "tornado", difficulty: difficulty),
                .trapper(name: "Sable", symbolName: "moon.fill", difficulty: difficulty)
            ]
        }
    }
}
