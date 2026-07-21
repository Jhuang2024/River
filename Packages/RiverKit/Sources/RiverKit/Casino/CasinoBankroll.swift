import Foundation

/// Which casino-floor game a record belongs to (§7). Poker keeps its own
/// richer pipeline; it appears here only for cross-game summaries.
public enum CasinoGameKind: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case blackjack
    case roulette
    case plinko

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .blackjack: return "Blackjack"
        case .roulette: return "Roulette"
        case .plinko: return "Plinko"
        }
    }

    public var tagline: String {
        switch self {
        case .blackjack: return "Fast decisions and basic-strategy training"
        case .roulette: return "Classic wheel and table betting"
        case .plinko: return "Physics-driven risk and reward"
        }
    }

    public var symbolName: String {
        switch self {
        case .blackjack: return "suit.club.fill"
        case .roulette: return "circle.circle.fill"
        case .plinko: return "circle.grid.3x3.fill"
        }
    }

    /// Whether skill affects results (§8). Roulette and Plinko outcomes
    /// cannot be improved through prediction - stated, not implied.
    public var isSkillGame: Bool {
        return self == .blackjack
    }
}

/// Bankroll modes (§2). All chips are fictional; recovery is always free.
public enum BankrollMode: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case practice
    case session
    case career

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .practice: return "Practice"
        case .session: return "Session"
        case .career: return "Career"
        }
    }

    public var summary: String {
        switch self {
        case .practice: return "Unlimited chips, no permanent losses. Statistics still count."
        case .session: return "A fixed stake for one sitting; resets when the session ends."
        case .career: return "One persistent fictional bankroll. Going broke offers a free rebuild: never a purchase."
        }
    }
}

/// One fictional bankroll (§2). Exact integer chips; practice mode reports
/// wagers as always affordable while still tracking net.
public struct CasinoBankrollState: Codable, Hashable, Sendable {
    public var mode: BankrollMode
    public var chips: Int
    /// Chips the current session started with (session/career display).
    public var sessionStart: Int
    /// Lifetime net across all completed rounds (all modes, incl. practice).
    public var lifetimeNet: Int

    public static let defaultStart = 1000
    /// Free career rebuild amount (§2): a fresh low-stakes stake, no waiting,
    /// no purchase, no ads.
    public static let rebuildAmount = 200

    public init(mode: BankrollMode = .career, chips: Int = CasinoBankrollState.defaultStart) {
        self.mode = mode
        self.chips = chips
        self.sessionStart = chips
        self.lifetimeNet = 0
    }

    public var isPractice: Bool { mode == .practice }

    public func canAfford(_ wager: Int) -> Bool {
        return isPractice || wager <= chips
    }

    /// Applies a completed round: stake out, payout in. Practice mode leaves
    /// chips untouched but still records the net.
    public mutating func settle(staked: Int, returned: Int) {
        lifetimeNet += returned - staked
        guard !isPractice else { return }
        chips = chips - staked + returned
    }

    public var sessionNet: Int {
        return isPractice ? 0 : chips - sessionStart
    }

    /// Starts a fresh session stake (session mode) or marks a new sitting.
    public mutating func beginSession(stake: Int = CasinoBankrollState.defaultStart) {
        if mode == .session { chips = stake }
        sessionStart = chips
    }

    /// Free recovery when a career bankroll hits zero (§2).
    public mutating func rebuildCareer() {
        guard mode == .career, chips <= 0 else { return }
        chips = CasinoBankrollState.rebuildAmount
        sessionStart = chips
    }
}

/// Optional local session safeguards (§11): plain limits the player set for
/// themselves. When one is reached the current round finishes safely and the
/// summary appears - no moralizing, no silent overrides.
public struct SessionSafeguards: Codable, Hashable, Sendable {
    /// Maximum rounds this sitting (nil = none).
    public var roundLimit: Int?
    /// Stop once fictional losses reach this (nil = none).
    public var lossLimit: Int?
    /// Stop once fictional profit reaches this (nil = none).
    public var profitTarget: Int?
    /// Minutes before a gentle time note (nil = none).
    public var timeReminderMinutes: Int?

    public init(roundLimit: Int? = nil, lossLimit: Int? = nil, profitTarget: Int? = nil, timeReminderMinutes: Int? = nil) {
        self.roundLimit = roundLimit
        self.lossLimit = lossLimit
        self.profitTarget = profitTarget
        self.timeReminderMinutes = timeReminderMinutes
    }

    public enum Trigger: String, Codable, Sendable {
        case roundLimit
        case lossLimit
        case profitTarget

        public var message: String {
            switch self {
            case .roundLimit: return "You reached your round limit for this session."
            case .lossLimit: return "You reached the loss limit you set for this session."
            case .profitTarget: return "You reached your profit target for this session."
            }
        }
    }

    /// Checked AFTER a round completes (§11): never interrupts mid-round.
    public func triggered(roundsPlayed: Int, sessionNet: Int) -> Trigger? {
        if let limit = roundLimit, roundsPlayed >= limit { return .roundLimit }
        if let limit = lossLimit, sessionNet <= -limit { return .lossLimit }
        if let target = profitTarget, sessionNet >= target { return .profitTarget }
        return nil
    }
}
