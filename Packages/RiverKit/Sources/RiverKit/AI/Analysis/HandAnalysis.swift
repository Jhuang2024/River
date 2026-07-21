import Foundation

/// Strategic made-hand categories (§13) - richer than the formal rank.
public enum MadeHandClass: Int, Codable, Comparable, Sendable, CaseIterable {
    case air = 0
    case aceHigh = 1
    case underpair = 2
    case bottomPair = 3
    case middlePair = 4
    case topPairWeakKicker = 5
    case topPairStrongKicker = 6
    case overpair = 7
    case twoPair = 8
    case threeOfAKind = 9
    case straight = 10
    case flush = 11
    case fullHouse = 12
    case quads = 13
    case straightFlush = 14

    public static func < (lhs: MadeHandClass, rhs: MadeHandClass) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }

    public var name: String {
        switch self {
        case .air: return "air"
        case .aceHigh: return "ace high"
        case .underpair: return "underpair"
        case .bottomPair: return "bottom pair"
        case .middlePair: return "middle pair"
        case .topPairWeakKicker: return "top pair, weak kicker"
        case .topPairStrongKicker: return "top pair, strong kicker"
        case .overpair: return "overpair"
        case .twoPair: return "two pair"
        case .threeOfAKind: return "three of a kind"
        case .straight: return "straight"
        case .flush: return "flush"
        case .fullHouse: return "full house"
        case .quads: return "quads"
        case .straightFlush: return "straight flush"
        }
    }
}

/// Full strategic analysis of a made hand in context (§13).
public struct MadeHandAnalysis: Equatable, Sendable {
    public let handClass: MadeHandClass
    public let value: HandValue
    /// Fraction of all possible opponent combinations this hand beats right
    /// now (exact enumeration, dead cards removed). 1.0 = the current nuts.
    public let fractionBeaten: Double
    public let isNuts: Bool
    public let isNearNuts: Bool
    /// Strong now but likely to be outdrawn on later streets.
    public let isVulnerable: Bool
    /// Medium-strength hand mostly good against bluffs.
    public let isBluffCatcher: Bool
}

/// Exact "strength right now" against every possible opponent combination.
public enum RelativeStrength {

    /// Returns (fractionBeaten, fractionTied) versus all combos not blocked
    /// by dead cards. Exact enumeration - no simulation.
    public static func versusAllCombos(hole: [Card], board: [Card], extraDead: Set<Card> = []) -> (beaten: Double, tied: Double) {
        precondition(board.count >= 3, "relative strength needs a board")
        let heroValue = HandEvaluator.evaluate(hole: hole, board: board)
        var dead = Set(hole + board)
        dead.formUnion(extraDead)
        var beaten = 0.0
        var tied = 0.0
        var total = 0.0
        for combo in HoleCombo.all where !combo.contains(any: dead) {
            let value = HandEvaluator.evaluate(hole: combo.cards, board: board)
            total += 1
            if heroValue > value {
                beaten += 1
            } else if heroValue == value {
                tied += 1
            }
        }
        guard total > 0 else { return (0, 0) }
        return (beaten / total, tied / total)
    }

    /// Weighted strength versus a specific estimated range.
    public static func versusRange(hole: [Card], board: [Card], range: HandRange) -> (beaten: Double, tied: Double) {
        precondition(board.count >= 3)
        let heroValue = HandEvaluator.evaluate(hole: hole, board: board)
        let dead = Set(hole + board)
        var beaten = 0.0
        var tied = 0.0
        var total = 0.0
        for (combo, weight) in range.weights where !combo.contains(any: dead) {
            let value = HandEvaluator.evaluate(hole: combo.cards, board: board)
            total += weight
            if heroValue > value {
                beaten += weight
            } else if heroValue == value {
                tied += weight
            }
        }
        guard total > 0 else { return (0, 0) }
        return (beaten / total, tied / total)
    }
}

public enum MadeHandAnalyzer {

    /// Classifies the strategic category of hole + board (§13).
    public static func classify(hole: [Card], board: [Card]) -> MadeHandClass {
        precondition(hole.count == 2 && board.count >= 3)
        let value = HandEvaluator.evaluate(hole: hole, board: board)
        switch value.category {
        case .straightFlush: return .straightFlush
        case .fourOfAKind: return .quads
        case .fullHouse: return .fullHouse
        case .flush: return .flush
        case .straight: return .straight
        case .threeOfAKind: return .threeOfAKind
        case .twoPair: return .twoPair
        case .pair:
            let pairRank = value.tiebreakers[0]
            let boardRanks = board.map { $0.rank.rawValue }
            let topBoard = boardRanks.max() ?? 0
            let holeRanks = hole.map { $0.rank.rawValue }
            let isPocketPair = hole[0].rank == hole[1].rank
            if isPocketPair {
                if pairRank > topBoard { return .overpair }
                return .underpair
            }
            // Paired a board card with a hole card?
            if holeRanks.contains(pairRank) && boardRanks.contains(pairRank) {
                if pairRank == topBoard {
                    let kicker = holeRanks.first { $0 != pairRank } ?? 0
                    return kicker >= Rank.queen.rawValue ? .topPairStrongKicker : .topPairWeakKicker
                }
                let sortedBoard = Set(boardRanks).sorted(by: >)
                if sortedBoard.count >= 2 && pairRank == sortedBoard[1] { return .middlePair }
                return .bottomPair
            }
            // The board itself is paired; hero plays high cards.
            return holeRanks.contains(Rank.ace.rawValue) ? .aceHigh : .air
        case .highCard:
            return hole.contains { $0.rank == .ace } ? .aceHigh : .air
        }
    }

    /// Full contextual analysis including nut distance and vulnerability.
    public static func analyze(hole: [Card], board: [Card], opponents: Int) -> MadeHandAnalysis {
        let handClass = classify(hole: hole, board: board)
        let value = HandEvaluator.evaluate(hole: hole, board: board)
        let strength = RelativeStrength.versusAllCombos(hole: hole, board: board)
        let unbeatenFraction = 1 - strength.beaten - strength.tied
        let isNuts = unbeatenFraction <= 0.0001
        let isNearNuts = unbeatenFraction <= 0.02
        let features = BoardTexture.features(for: board)
        // Vulnerable: strong-but-not-huge hands on boards with live draws
        // before the river, or one-pair hands against several opponents.
        var vulnerable = false
        if board.count < 5 {
            if handClass >= .middlePair && handClass <= .twoPair && features.wetness > 0.45 {
                vulnerable = true
            }
            if handClass >= .topPairWeakKicker && handClass <= .overpair && opponents >= 2 {
                vulnerable = true
            }
        }
        // Bluff catcher: medium showdown value that mostly beats bluffs.
        let isBluffCatcher = strength.beaten > 0.35 && strength.beaten < 0.72 && handClass <= .topPairStrongKicker
        return MadeHandAnalysis(
            handClass: handClass,
            value: value,
            fractionBeaten: strength.beaten,
            isNuts: isNuts,
            isNearNuts: isNearNuts,
            isVulnerable: vulnerable,
            isBluffCatcher: isBluffCatcher
        )
    }
}

/// Extended draw detection (§12).
public struct DrawAnalysis: Equatable, Sendable {
    public let flushDraw: Bool
    public let nutFlushDraw: Bool
    public let backdoorFlushDraw: Bool
    public let openEndedStraightDraw: Bool
    public let gutshot: Bool
    public let doubleGutshot: Bool
    public let backdoorStraightDraw: Bool
    public let overcards: Int
    public let comboDraw: Bool

    /// Outs discounted for board danger (paired boards dirty flush/straight
    /// outs, overcard outs are always partial).
    public let estimatedCleanOuts: Double

    public var isStrongDraw: Bool {
        return comboDraw || flushDraw || openEndedStraightDraw || doubleGutshot
    }

    public var isWeakDraw: Bool {
        return !isStrongDraw && (gutshot || overcards >= 2)
    }

    public var isBackdoorOnly: Bool {
        return !isStrongDraw && !gutshot && (backdoorFlushDraw || backdoorStraightDraw)
    }
}

public enum DrawAnalyzer {

    public static func analyze(hole: [Card], board: [Card]) -> DrawAnalysis {
        guard board.count >= 3 && board.count < 5 else {
            return DrawAnalysis(flushDraw: false, nutFlushDraw: false, backdoorFlushDraw: false,
                                openEndedStraightDraw: false, gutshot: false, doubleGutshot: false,
                                backdoorStraightDraw: false, overcards: 0, comboDraw: false,
                                estimatedCleanOuts: 0)
        }
        let all = hole + board

        // Flush draws.
        var flushDraw = false
        var nutFlushDraw = false
        var backdoorFlush = false
        for suit in Suit.allCases {
            let total = all.filter { $0.suit == suit }.count
            let mine = hole.filter { $0.suit == suit }.count
            guard mine >= 1 else { continue }
            if total == 4 {
                flushDraw = true
                if hole.contains(Card(.ace, suit)) {
                    nutFlushDraw = true
                }
            } else if total == 3 && board.count == 3 && mine == 2 {
                backdoorFlush = true
            }
        }

        // Straight draws via completion counting.
        var mask = 0
        for card in all {
            mask |= 1 << card.rank.rawValue
            if card.rank == .ace { mask |= 1 << 1 }
        }
        func hasStraight(_ m: Int) -> Bool {
            var run = 0
            for r in 1...14 {
                if m & (1 << r) != 0 {
                    run += 1
                    if run >= 5 { return true }
                } else {
                    run = 0
                }
            }
            return false
        }
        let alreadyStraight = hasStraight(mask)
        var completions: [Int] = []
        if !alreadyStraight {
            for candidate in 2...14 where mask & (1 << candidate) == 0 {
                var m = mask | (1 << candidate)
                if candidate == 14 { m |= 1 << 1 }
                if hasStraight(m) {
                    completions.append(candidate)
                }
            }
        }
        let openEnded = isOpenEnder(completions)
        let doubleGut = completions.count >= 2 && !openEnded
        let gutshot = completions.count == 1
        // Backdoor straight: flop only, no direct draw, but three ranks within
        // a five-card window using at least one hole card.
        var backdoorStraight = false
        if board.count == 3 && completions.isEmpty && !alreadyStraight {
            let holeRanks = Set(hole.map { $0.rank.rawValue })
            let allRanks = Set(all.map { $0.rank.rawValue })
            let sorted = allRanks.sorted()
            if sorted.count >= 3 {
                for i in 0...(sorted.count - 3) {
                    if sorted[i + 2] - sorted[i] <= 4 && !holeRanks.isDisjoint(with: [sorted[i], sorted[i + 1], sorted[i + 2]]) {
                        backdoorStraight = true
                        break
                    }
                }
            }
        }

        // Overcards to the board.
        let topBoard = board.map { $0.rank.rawValue }.max() ?? 0
        let overcards = hole.filter { $0.rank.rawValue > topBoard }.count

        let features = BoardTexture.features(for: board)
        let dirty = features.paired ? 0.75 : 1.0

        var outs = 0.0
        if flushDraw { outs += 9 * dirty }
        if openEnded || doubleGut { outs += (flushDraw ? 6 : 8) * dirty }
        else if gutshot { outs += (flushDraw ? 3 : 4) * dirty }
        outs += Double(overcards) * 1.5 * (features.wetness > 0.5 ? 0.6 : 1.0)

        let combo = flushDraw && (openEnded || doubleGut || gutshot)
        return DrawAnalysis(
            flushDraw: flushDraw,
            nutFlushDraw: nutFlushDraw,
            backdoorFlushDraw: backdoorFlush,
            openEndedStraightDraw: openEnded,
            gutshot: gutshot,
            doubleGutshot: doubleGut,
            backdoorStraightDraw: backdoorStraight,
            overcards: overcards,
            comboDraw: combo,
            estimatedCleanOuts: outs
        )
    }

    /// An open-ender's two completing ranks bracket a four-card run, so they
    /// sit exactly 5 apart (e.g. 5678 completes with 4 or 9). Two completions
    /// at any other spacing indicate a double gutshot.
    private static func isOpenEnder(_ completions: [Int]) -> Bool {
        guard completions.count == 2 else { return false }
        return abs(completions[0] - completions[1]) == 5
    }
}

extension BoardTexture {

    /// Numeric board features (§11) - labels are summaries, these drive AI.
    public struct Features: Equatable, Sendable {
        /// 0 = unpaired, 1 = one pair, 2 = double-paired/trips+.
        public let pairedness: Int
        /// 0 rainbow, 1 two-tone, 2 monotone-or-4+ of a suit.
        public let flushLevel: Int
        /// Cards of the most common suit on the board.
        public let maxSuitCount: Int
        /// 0...1: how many straight-completing ranks exist relative to 8.
        public let straightness: Double
        /// Fraction of board cards that are T+.
        public let broadwayDensity: Double
        /// Fraction of board cards that are 8 or lower.
        public let lowDensity: Double
        /// Aggregate 0...1 "wetness": draws available now.
        public let wetness: Double
        /// 0...1: how much future cards can change the nuts (0 on the river).
        public let dynamism: Double
        public let paired: Bool
    }

    public static func features(for board: [Card]) -> Features {
        guard board.count >= 3 else {
            return Features(pairedness: 0, flushLevel: 0, maxSuitCount: 0, straightness: 0,
                            broadwayDensity: 0, lowDensity: 0, wetness: 0, dynamism: 1, paired: false)
        }
        var rankCounts: [Int: Int] = [:]
        var suitCounts: [Int: Int] = [:]
        for card in board {
            rankCounts[card.rank.rawValue, default: 0] += 1
            suitCounts[card.suit.rawValue, default: 0] += 1
        }
        let pairCount = rankCounts.values.filter { $0 >= 2 }.count
        let hasTripsPlus = rankCounts.values.contains { $0 >= 3 }
        let pairedness = hasTripsPlus || pairCount >= 2 ? 2 : (pairCount == 1 ? 1 : 0)
        let maxSuit = suitCounts.values.max() ?? 0
        let flushLevel = maxSuit >= 3 ? 2 : (maxSuit == 2 ? 1 : 0)

        // How many single ranks would complete a straight using board cards.
        var mask = 0
        for card in board {
            mask |= 1 << card.rank.rawValue
            if card.rank == .ace { mask |= 1 << 1 }
        }
        var completions = 0
        for candidate in 2...14 where mask & (1 << candidate) == 0 {
            var m = mask | (1 << candidate)
            if candidate == 14 { m |= 1 << 1 }
            // A straight needs only 3 board cards + 2 hole cards: check for
            // any window of 5 containing >= 4 set bits (candidate + 3 board).
            var best = 0
            for low in 1...10 {
                var bits = 0
                for r in low..<(low + 5) where m & (1 << r) != 0 {
                    bits += 1
                }
                best = max(best, bits)
            }
            if best >= 4 {
                completions += 1
            }
        }
        let straightness = min(1, Double(completions) / 8.0)

        let broadway = board.filter { $0.rank.rawValue >= 10 }.count
        let low = board.filter { $0.rank.rawValue <= 8 }.count
        let broadwayDensity = Double(broadway) / Double(board.count)
        let lowDensity = Double(low) / Double(board.count)

        var wetness = 0.0
        wetness += flushLevel == 2 ? 0.4 : (flushLevel == 1 ? 0.18 : 0)
        wetness += straightness * 0.45
        wetness += pairedness == 0 ? 0.05 : 0
        wetness = min(1, wetness)

        let cardsToCome = 5 - board.count
        let dynamism = min(1, Double(cardsToCome) * (0.25 + wetness * 0.4))

        return Features(
            pairedness: pairedness,
            flushLevel: flushLevel,
            maxSuitCount: maxSuit,
            straightness: straightness,
            broadwayDensity: broadwayDensity,
            lowDensity: lowDensity,
            wetness: wetness,
            dynamism: dynamism,
            paired: pairedness > 0
        )
    }
}
