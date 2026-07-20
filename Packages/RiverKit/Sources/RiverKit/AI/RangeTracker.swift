import Foundation

/// Probabilistic per-opponent range estimation (§14–15), built purely from
/// public events — the tracker is a deterministic function of the visible
/// history, so bot decisions using it stay reproducible and cheat-free.
///
/// Update model: posteriorWeight = priorWeight × actionLikelihood, with a
/// relative floor so no surviving combo collapses to zero, then relative
/// normalization. Inference is deliberately imperfect: unexpected hands are
/// down-weighted, never deleted.
public struct RangeTracker: Sendable {

    public private(set) var ranges: [Int: HandRange]
    /// Debug log of updates (event description → combos remaining).
    public private(set) var updateLog: [String]

    private static let relativeFloor = 0.03

    // MARK: - Construction from visible history

    /// Builds tracked ranges for every opponent of `viewpointSeat` by
    /// replaying the visible events. `viewpointCards` are the viewer's own
    /// hole cards (dead for everyone else's range).
    public static func build(
        events: [HandEvent],
        viewpointSeat: Int,
        viewpointCards: [Card],
        config: StrategyConfig = .baseline
    ) -> RangeTracker {
        var tracker = RangeTracker(ranges: [:], updateLog: [])

        // Extract the static hand facts.
        var buttonIndex = 0
        var seatCount = 0
        var participatingSeats: [Int] = []
        var bigBlind = 2
        for event in events {
            if case .handStarted(_, let button, _, let bb, _, let stacks) = event {
                buttonIndex = button
                bigBlind = bb
                seatCount = stacks.count
                participatingSeats = stacks.indices.filter { stacks[$0] > 0 }
                break
            }
        }
        guard seatCount > 0 else { return tracker }

        let dead = Set(viewpointCards)
        for seat in participatingSeats where seat != viewpointSeat {
            tracker.ranges[seat] = HandRange.uniform(excluding: dead)
        }

        var board: [Card] = []
        var preflopRaises = 0

        for event in events {
            switch event {
            case .dealtBoard(_, let cards):
                board.append(contentsOf: cards)
                // New public cards are dead for every tracked range.
                for seat in tracker.ranges.keys {
                    tracker.ranges[seat]?.removeCombos(containing: Set(cards))
                }
            case .action(let seat, let actionStreet, let kind, _, let toTotal, _):
                if kind == .raise || kind == .bet {
                    if actionStreet == .preflop { preflopRaises += 1 }
                }
                guard seat != viewpointSeat, tracker.ranges[seat] != nil else { continue }
                if kind == .fold {
                    tracker.ranges.removeValue(forKey: seat)
                    continue
                }
                if actionStreet == .preflop {
                    tracker.applyPreflopUpdate(
                        seat: seat, kind: kind, raisesBefore: kind == .raise ? preflopRaises - 1 : preflopRaises,
                        offsetFromButton: ((seat - buttonIndex) % seatCount + seatCount) % seatCount,
                        playerCount: participatingSeats.count,
                        toTotal: toTotal, bigBlind: bigBlind, config: config
                    )
                } else {
                    tracker.applyPostflopUpdate(seat: seat, kind: kind, board: board, street: actionStreet, dead: dead)
                }
            case .showedHand(let seat, let cards, _):
                // Revealed at showdown: collapse to the exact known combo.
                if seat != viewpointSeat && cards.count == 2 {
                    var exact = HandRange()
                    exact.set(HoleCombo(cards[0], cards[1]), weight: 1)
                    tracker.ranges[seat] = exact
                }
            default:
                break
            }
        }
        return tracker
    }

    // MARK: - Preflop update

    private mutating func applyPreflopUpdate(
        seat: Int, kind: ActionKind, raisesBefore: Int,
        offsetFromButton: Int, playerCount: Int,
        toTotal: Int, bigBlind: Int, config: StrategyConfig
    ) {
        guard var range = ranges[seat] else { return }
        let position = TablePosition.position(offsetFromButton: offsetFromButton, playerCount: max(2, min(6, playerCount)))

        func likelihood(forPercentile p: Double) -> Double {
            switch kind {
            case .raise, .bet:
                if raisesBefore == 0 {
                    // Opening raise: opening range for the position.
                    let open = config.openPercent[position] ?? 0.2
                    return p <= open ? 1.0 : 0.07
                }
                if raisesBefore == 1 {
                    let threeBet = config.threeBetPercent[position] ?? 0.05
                    return p <= threeBet ? 1.0 : (p <= threeBet * 2.5 ? 0.3 : 0.05)
                }
                let fourBet = config.fourBetPercent
                return p <= fourBet ? 1.0 : (p <= fourBet * 3 ? 0.25 : 0.03)
            case .call:
                if raisesBefore == 0 {
                    // Limp: middling hands mostly; premiums usually raise.
                    if p <= 0.05 { return 0.2 }
                    if p <= 0.55 { return 1.0 }
                    return 0.25
                }
                let callRange = position == .bigBlind ? config.bbDefendCallPercent
                    : (position == .smallBlind ? config.sbDefendCallPercent : (config.callVsOpenPercent[position] ?? 0.1))
                let raiseRange = config.threeBetPercent[position] ?? 0.05
                if p <= raiseRange { return 0.35 }        // premiums usually re-raise
                if p <= callRange + raiseRange { return 1.0 }
                return raisesBefore >= 2 ? 0.04 : 0.08
            case .check:
                // Big blind checking its option: premiums would usually raise.
                return p <= 0.06 ? 0.4 : 1.0
            case .fold:
                return 1.0
            }
        }

        for combo in range.weights.keys {
            range.scale(combo, by: likelihood(forPercentile: HandOrdering.percentile(of: combo)))
        }
        range.applyFloor(RangeTracker.relativeFloor)
        range.normalize()
        ranges[seat] = range
        updateLog.append("seat \(seat) preflop \(kind.rawValue): \(String(format: "%.0f", range.comboCount)) combos")
    }

    // MARK: - Postflop update

    private mutating func applyPostflopUpdate(seat: Int, kind: ActionKind, board: [Card], street: Street, dead: Set<Card>) {
        guard var range = ranges[seat], board.count >= 3 else { return }

        for (combo, _) in range.weights {
            let strength = quickStrengthBucket(combo: combo, board: board)
            let factor: Double
            switch kind {
            case .bet, .raise:
                switch strength {
                case .strong: factor = 1.0
                case .good: factor = 0.8
                case .draw: factor = 0.6
                case .medium: factor = 0.35
                case .weak: factor = street == .river ? 0.28 : 0.2
                }
            case .call:
                switch strength {
                case .strong: factor = 0.7   // some raise instead
                case .good: factor = 1.0
                case .draw: factor = street == .river ? 0.2 : 0.9
                case .medium: factor = 0.75
                case .weak: factor = 0.3
                }
            case .check:
                switch strength {
                case .strong: factor = 0.45  // slow-plays exist but are rarer
                case .good: factor = 0.7
                case .draw: factor = 0.9
                case .medium: factor = 1.0
                case .weak: factor = 1.0
                }
            case .fold:
                factor = 1.0
            }
            range.scale(combo, by: factor)
        }
        range.applyFloor(RangeTracker.relativeFloor)
        range.normalize()
        ranges[seat] = range
        updateLog.append("seat \(seat) \(street.name.lowercased()) \(kind.rawValue): \(String(format: "%.0f", range.comboCount)) combos")
    }

    private enum StrengthBucket {
        case strong   // two pair or better / near nuts
        case good     // top pair or overpair
        case draw     // strong draw
        case medium   // middle pair, decent showdown value
        case weak     // air, weak pairs
    }

    /// Cheap per-combo classification for likelihood updates.
    private func quickStrengthBucket(combo: HoleCombo, board: [Card]) -> StrengthBucket {
        let handClass = MadeHandAnalyzer.classify(hole: combo.cards, board: board)
        if handClass >= .twoPair { return .strong }
        if handClass >= .topPairWeakKicker { return .good }
        // Draw check (only before the river).
        if board.count < 5 {
            if hasStrongDrawFast(combo: combo, board: board) { return .draw }
        }
        if handClass >= .bottomPair { return .medium }
        return .weak
    }

    /// Fast flush/open-ender detection without full analysis.
    private func hasStrongDrawFast(combo: HoleCombo, board: [Card]) -> Bool {
        // Flush draw.
        for suit in Suit.allCases {
            let boardCount = board.filter { $0.suit == suit }.count
            let mine = combo.cards.filter { $0.suit == suit }.count
            if mine >= 1 && boardCount + mine == 4 {
                return true
            }
        }
        // Straight draw: at least two completing ranks.
        var mask = 0
        for card in combo.cards + board {
            mask |= 1 << card.rank.rawValue
            if card.rank == .ace { mask |= 1 << 1 }
        }
        func straight(_ m: Int) -> Bool {
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
        if straight(mask) { return false } // made, not a draw
        var completions = 0
        for candidate in 2...14 where mask & (1 << candidate) == 0 {
            var m = mask | (1 << candidate)
            if candidate == 14 { m |= 1 << 1 }
            if straight(m) {
                completions += 1
                if completions >= 2 { return true }
            }
        }
        return false
    }

    // MARK: - Queries

    /// Fraction of a seat's range that currently rates as weak versus the
    /// board (drives fold-equity estimates).
    public func weakFraction(seat: Int, board: [Card]) -> Double {
        guard let range = ranges[seat], board.count >= 3, !range.isEmpty else { return 0.45 }
        var weakTotal = 0.0
        var total = 0.0
        for (combo, weight) in range.weights {
            total += weight
            switch quickStrengthBucket(combo: combo, board: board) {
            case .weak: weakTotal += weight
            case .medium: weakTotal += weight * 0.45
            case .draw: weakTotal += weight * 0.3
            case .strong, .good: break
            }
        }
        return total > 0 ? weakTotal / total : 0.45
    }
}
