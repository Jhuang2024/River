import Foundation

/// One blind level (§20). Progression is hand-based, which suits an offline
/// game the player can pause at any moment.
public struct BlindLevel: Codable, Hashable, Sendable {
    public let smallBlind: Int
    public let bigBlind: Int
    public let ante: Int

    public init(_ smallBlind: Int, _ bigBlind: Int, ante: Int = 0) {
        self.smallBlind = smallBlind
        self.bigBlind = bigBlind
        self.ante = ante
    }
}

/// Configurable tournament structure (§19–20). Values live in configuration,
/// never in engine code.
public struct TournamentStructure: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let startingStack: Int
    public let handsPerLevel: Int
    public let levels: [BlindLevel]
    /// Prize fractions for 1st, 2nd, ... of the fictional prize pool.
    public let payoutFractions: [Double]

    public var summary: String {
        return "\(startingStack) chips · blinds rise every \(handsPerLevel) hands"
    }

    public static let standard = TournamentStructure(
        id: "standard", name: "Standard", startingStack: 1500, handsPerLevel: 8,
        levels: [
            BlindLevel(10, 20), BlindLevel(15, 30), BlindLevel(20, 40),
            BlindLevel(30, 60), BlindLevel(40, 80), BlindLevel(50, 100, ante: 10),
            BlindLevel(75, 150, ante: 15), BlindLevel(100, 200, ante: 25),
            BlindLevel(150, 300, ante: 25), BlindLevel(200, 400, ante: 50)
        ],
        payoutFractions: [0.65, 0.35]
    )

    public static let turbo = TournamentStructure(
        id: "turbo", name: "Turbo", startingStack: 1000, handsPerLevel: 6,
        levels: [
            BlindLevel(10, 20), BlindLevel(20, 40), BlindLevel(30, 60),
            BlindLevel(50, 100, ante: 10), BlindLevel(75, 150, ante: 15),
            BlindLevel(100, 200, ante: 25), BlindLevel(150, 300, ante: 25),
            BlindLevel(200, 400, ante: 50), BlindLevel(300, 600, ante: 75)
        ],
        payoutFractions: [0.65, 0.35]
    )

    public static let hyper = TournamentStructure(
        id: "hyper", name: "Hyper", startingStack: 500, handsPerLevel: 4,
        levels: [
            BlindLevel(10, 20), BlindLevel(15, 30), BlindLevel(25, 50, ante: 5),
            BlindLevel(50, 100, ante: 10), BlindLevel(75, 150, ante: 15),
            BlindLevel(100, 200, ante: 25), BlindLevel(150, 300, ante: 25)
        ],
        payoutFractions: [0.7, 0.3]
    )

    public static let all: [TournamentStructure] = [.standard, .turbo, .hyper]

    /// Structure sanity (§63): monotone blinds, valid payouts.
    public func validate() -> [String] {
        var problems: [String] = []
        if levels.isEmpty { problems.append("\(id): no levels") }
        if startingStack < 20 * (levels.first?.bigBlind ?? 1) {
            problems.append("\(id): starting stack under 20 BB")
        }
        for (index, level) in levels.enumerated() {
            if level.smallBlind <= 0 || level.bigBlind < level.smallBlind {
                problems.append("\(id) level \(index): bad blinds")
            }
            if index > 0 && level.bigBlind < levels[index - 1].bigBlind {
                problems.append("\(id) level \(index): blinds decreased")
            }
        }
        let payoutSum = payoutFractions.reduce(0, +)
        if abs(payoutSum - 1.0) > 0.001 { problems.append("\(id): payouts sum to \(payoutSum)") }
        if handsPerLevel < 1 { problems.append("\(id): handsPerLevel < 1") }
        return problems
    }
}

public struct TournamentConfig: Codable, Hashable, Sendable {
    public var structure: TournamentStructure
    public var seed: UInt64
    public var heroName: String
    public var bots: [BotProfile]
    /// Fictional prize pool (display only; §19: fictional prizes).
    public var prizePool: Int

    public init(structure: TournamentStructure, seed: UInt64, heroName: String = "You", bots: [BotProfile], prizePool: Int = 600) {
        self.structure = structure
        self.seed = seed
        self.heroName = heroName
        self.bots = bots
        self.prizePool = prizePool
    }
}

/// Serializable Sit-and-Go state between hands (§19): blind levels,
/// eliminations, heads-up completion, payouts, resume support.
public struct TournamentState: Codable, Hashable, Sendable {
    public var config: TournamentConfig
    public var stacks: [Int]
    public var buttonIndex: Int
    public var handsPlayed: Int
    /// Seats in elimination order (first eliminated first).
    public var eliminationOrder: [Int]
    public var isFinished: Bool
    public var startDate: Date

    public init(config: TournamentConfig, startDate: Date) {
        self.config = config
        self.stacks = Array(repeating: config.structure.startingStack, count: config.bots.count + 1)
        self.buttonIndex = 0
        self.handsPlayed = 0
        self.eliminationOrder = []
        self.isFinished = false
        self.startDate = startDate
    }

    public var playerNames: [String] {
        return [config.heroName] + config.bots.map { $0.name }
    }

    public var playersRemaining: Int {
        return stacks.filter { $0 > 0 }.count
    }

    public var currentLevelIndex: Int {
        // Blinds change between hands only (§20).
        return min(config.structure.levels.count - 1, handsPlayed / config.structure.handsPerLevel)
    }

    public var currentLevel: BlindLevel {
        return config.structure.levels[currentLevelIndex]
    }

    /// Hands until the next level, nil at the final level.
    public var handsUntilNextLevel: Int? {
        guard currentLevelIndex < config.structure.levels.count - 1 else { return nil }
        return config.structure.handsPerLevel - (handsPlayed % config.structure.handsPerLevel)
    }

    public var heroEliminated: Bool {
        return stacks[heroSeatIndex] <= 0
    }

    /// Payout amounts by place (1st, 2nd, ...).
    public var payoutsByPlace: [Int] {
        return config.structure.payoutFractions.map { Int((Double(config.prizePool) * $0).rounded()) }
    }

    /// Whether the money bubble is active: one elimination from the payouts.
    public var onBubble: Bool {
        return playersRemaining == config.structure.payoutFractions.count + 1
    }

    /// Finishing place for a seat (1 = winner), nil while still playing.
    public func place(of seat: Int) -> Int? {
        if isFinished && stacks[seat] > 0 && playersRemaining == 1 {
            return 1
        }
        if let index = eliminationOrder.firstIndex(of: seat) {
            let totalPlayers = stacks.count
            return totalPlayers - index
        }
        return nil
    }

    /// Prize for a seat once its place is known (0 outside the payouts).
    public func prize(of seat: Int) -> Int {
        guard let place = place(of: seat) else { return 0 }
        let payouts = payoutsByPlace
        return place <= payouts.count ? payouts[place - 1] : 0
    }

    public var canContinue: Bool {
        return !isFinished && playersRemaining >= 2 && !heroEliminated
    }

    /// Hero's exact current ICM prize equity (§21).
    public var heroPrizeEquity: Double {
        let payouts = payoutsByPlace.map { Double($0) }
        return ICM.equities(stacks: stacks, payouts: payouts)[heroSeatIndex]
    }

    public func seedForNextHand() -> UInt64 {
        var rng = SeededRNG.derive(seed: config.seed, stream: 40_000 &+ UInt64(handsPlayed + 1))
        return rng.nextUInt64()
    }

    /// Configuration for the next hand, or nil when the tournament is over.
    public func nextHandConfig() -> HandConfig? {
        guard playersRemaining >= 2, !isFinished else { return nil }
        let level = currentLevel
        return HandConfig(
            stacks: stacks,
            buttonIndex: buttonIndex,
            smallBlind: level.smallBlind,
            bigBlind: level.bigBlind,
            ante: level.ante,
            seed: seedForNextHand(),
            handNumber: handsPlayed + 1
        )
    }

    /// Records a completed hand: stacks, eliminations, level advance, button.
    public mutating func complete(hand: PokerHand) {
        precondition(hand.isComplete)
        let previousStacks = stacks
        stacks = hand.seats.map { $0.stack }
        handsPlayed += 1

        // Eliminations this hand, ordered so that the seat that STARTED the
        // hand with fewer chips finishes lower (standard tie handling).
        let busted = stacks.indices
            .filter { previousStacks[$0] > 0 && stacks[$0] <= 0 }
            .sorted { previousStacks[$0] < previousStacks[$1] }
        eliminationOrder.append(contentsOf: busted)

        if playersRemaining <= 1 || heroEliminated {
            isFinished = playersRemaining <= 1
            if heroEliminated && playersRemaining > 1 {
                // Hero busted: the tournament result for the hero is fixed;
                // remaining bots don't need to be simulated for the summary.
                isFinished = true
            }
        }

        // Button moves to the next surviving seat (simplified moving button).
        var next = buttonIndex
        for _ in 0..<stacks.count {
            next = (next + 1) % stacks.count
            if stacks[next] > 0 { break }
        }
        buttonIndex = next
    }

    /// The tournament context handed to bots and analysis (§26 of the AI spec).
    public func tournamentContext() -> TournamentContext {
        return TournamentContext(
            playersRemaining: playersRemaining,
            payouts: payoutsByPlace,
            stacks: stacks,
            onBubble: onBubble,
            levelIndex: currentLevelIndex
        )
    }
}

/// Public tournament information available to every player at the table.
public struct TournamentContext: Codable, Hashable, Sendable {
    public let playersRemaining: Int
    public let payouts: [Int]
    public let stacks: [Int]
    public let onBubble: Bool
    public let levelIndex: Int

    public init(playersRemaining: Int, payouts: [Int], stacks: [Int], onBubble: Bool, levelIndex: Int) {
        self.playersRemaining = playersRemaining
        self.payouts = payouts
        self.stacks = stacks
        self.onBubble = onBubble
        self.levelIndex = levelIndex
    }

    /// ICM risk premium for a seat considering an all-in of `amount` versus
    /// the biggest covering opponent (bounded approximation for live play).
    public func riskPremium(for seat: Int, amount: Int) -> Double {
        guard stacks.indices.contains(seat), amount > 0 else { return 0 }
        // Villain: the largest other live stack (worst case for elimination).
        var villain = -1
        for index in stacks.indices where index != seat && stacks[index] > 0 {
            if villain < 0 || stacks[index] > stacks[villain] { villain = index }
        }
        guard villain >= 0 else { return 0 }
        return ICM.riskPremium(
            stacks: stacks,
            payouts: payouts.map { Double($0) },
            heroIndex: seat,
            villainIndex: villain,
            amountAtRisk: amount
        )
    }
}
