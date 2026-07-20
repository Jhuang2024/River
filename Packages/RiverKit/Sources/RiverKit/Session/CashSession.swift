import Foundation

/// Configuration chosen on the session setup screen.
public struct SessionConfig: Codable, Equatable, Sendable {
    public var smallBlind: Int
    public var bigBlind: Int
    public var startingStack: Int
    /// Number of hands in the session; 0 means unlimited.
    public var handsTarget: Int
    public var seed: UInt64
    public var heroName: String
    /// The five AI opponents, seated 1...5 (hero is always seat 0).
    public var bots: [BotProfile]
    /// Casual reload: any seat that busts is topped back up between hands.
    public var autoReload: Bool

    public init(smallBlind: Int = 1, bigBlind: Int = 2, startingStack: Int = 200, handsTarget: Int = 20, seed: UInt64, heroName: String = "You", bots: [BotProfile], autoReload: Bool = true) {
        self.smallBlind = smallBlind
        self.bigBlind = bigBlind
        self.startingStack = startingStack
        self.handsTarget = handsTarget
        self.seed = seed
        self.heroName = heroName
        self.bots = bots
        self.autoReload = autoReload
    }

    public var playerNames: [String] {
        return [heroName] + bots.map { $0.name }
    }

    public var seatCount: Int {
        return bots.count + 1
    }
}

/// Hero seat is fixed at 0 (bottom of the table); the button rotates.
public let heroSeatIndex = 0

/// Serializable state of a cash session between hands. The session only
/// snapshots at hand boundaries, so resuming never resurrects a half-played
/// hand with known cards.
public struct CashSessionState: Codable, Equatable, Sendable {
    public var config: SessionConfig
    public var stacks: [Int]
    public var buttonIndex: Int
    public var handsPlayed: Int
    /// Hero net result per completed hand, for the results graph.
    public var heroNetByHand: [Int]
    /// Seats that were reloaded before the next hand (for UI messaging).
    public var lastReloadedSeats: [Int]
    public var startDate: Date
    public var isFinished: Bool

    public init(config: SessionConfig, startDate: Date) {
        self.config = config
        self.stacks = Array(repeating: config.startingStack, count: config.seatCount)
        self.buttonIndex = 0
        self.handsPlayed = 0
        self.heroNetByHand = []
        self.lastReloadedSeats = []
        self.startDate = startDate
        self.isFinished = false
    }

    public var heroStack: Int {
        return stacks[heroSeatIndex]
    }

    public var heroNetTotal: Int {
        return heroNetByHand.reduce(0, +)
    }

    /// Whether another hand can be dealt.
    public var canContinue: Bool {
        if isFinished { return false }
        if config.handsTarget > 0 && handsPlayed >= config.handsTarget { return false }
        if stacks[heroSeatIndex] <= 0 && !config.autoReload { return false }
        let funded = stacks.filter { $0 > 0 }.count
        return funded >= 2 || config.autoReload
    }

    /// Deterministic per-hand seed derived from the session seed.
    public func seedForNextHand() -> UInt64 {
        var rng = SeededRNG.derive(seed: config.seed, stream: UInt64(handsPlayed + 1))
        return rng.nextUInt64()
    }

    /// Applies casual reloads and builds the config for the next hand.
    /// Mutates stacks (reloads) and records which seats were reloaded.
    public mutating func nextHandConfig() -> HandConfig {
        lastReloadedSeats = []
        if config.autoReload {
            for i in stacks.indices where stacks[i] <= 0 {
                stacks[i] = config.startingStack
                lastReloadedSeats.append(i)
            }
        }
        // Also top up any seat too short to post the big blind meaningfully.
        if config.autoReload {
            for i in stacks.indices where stacks[i] > 0 && stacks[i] < config.bigBlind {
                stacks[i] = config.startingStack
                if !lastReloadedSeats.contains(i) {
                    lastReloadedSeats.append(i)
                }
            }
        }
        return HandConfig(
            stacks: stacks,
            buttonIndex: buttonIndex,
            smallBlind: config.smallBlind,
            bigBlind: config.bigBlind,
            ante: 0,
            seed: seedForNextHand(),
            handNumber: handsPlayed + 1
        )
    }

    /// Records a completed hand: updates stacks, results and moves the button.
    public mutating func complete(hand: PokerHand) {
        precondition(hand.isComplete, "cannot complete an unfinished hand")
        stacks = hand.seats.map { $0.stack }
        handsPlayed += 1
        heroNetByHand.append(hand.seats[heroSeatIndex].stack - hand.seats[heroSeatIndex].startingStack)
        advanceButton()
        if config.handsTarget > 0 && handsPlayed >= config.handsTarget {
            isFinished = true
        }
        if stacks[heroSeatIndex] <= 0 && !config.autoReload {
            isFinished = true
        }
    }

    /// Button moves to the next seat that has chips (or will after reload).
    private mutating func advanceButton() {
        let n = stacks.count
        var i = buttonIndex
        for _ in 0..<n {
            i = (i + 1) % n
            if stacks[i] > 0 || config.autoReload {
                buttonIndex = i
                return
            }
        }
    }

    /// Names indexed by seat.
    public var playerNames: [String] {
        return config.playerNames
    }

    /// Profile for a seat, nil for the hero.
    public func botProfile(forSeat seat: Int) -> BotProfile? {
        guard seat != heroSeatIndex else { return nil }
        let index = seat - 1
        guard config.bots.indices.contains(index) else { return nil }
        return config.bots[index]
    }
}
