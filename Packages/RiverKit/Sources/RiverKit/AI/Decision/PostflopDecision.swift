import Foundation

/// One strategically distinct candidate action (§20).
public struct ActionCandidate: Equatable, Sendable {
    public enum Purpose: String, Codable, Sendable {
        case fold
        case checkBack
        case call
        case value
        case thinValue
        case protection
        case semiBluff
        case bluff
        case allInLeverage
    }

    public let action: PlayerAction
    public let label: String
    public let purpose: Purpose
}

/// Inspectable score breakdown for one candidate (§21, §40). Never a black box.
public struct CandidateScore: Codable, Equatable, Sendable {
    public let label: String
    public let purposeTag: String
    /// Approximate EV in chips relative to folding now.
    public let baseEV: Double
    public let positionalAdjustment: Double
    public let drawAdjustment: Double
    public let blockerAdjustment: Double
    public let personalityAdjustment: Double
    public let noise: Double
    public var finalScore: Double {
        return baseEV + positionalAdjustment + drawAdjustment + blockerAdjustment + personalityAdjustment + noise
    }
}

/// Full postflop decision trace for debugging and analysis (§40).
public struct DecisionTrace: Codable, Equatable, Sendable {
    public let street: String
    public let equity: Double
    public let equityTrials: Int
    public let equityExact: Bool
    public let madeHandClass: String
    public let fractionBeaten: Double
    public let potOdds: Double
    public let sprText: String
    public let opponentCount: Int
    public let trackedComboCounts: [Int: Double]
    public let scores: [CandidateScore]
    public let chosenLabel: String
    public let seed: UInt64
}

/// Everything the postflop scorer needs, computed once per decision.
public struct PostflopContext: Sendable {
    public let obs: BotObservation
    public let madeHand: MadeHandAnalysis
    public let draws: DrawAnalysis
    public let features: BoardTexture.Features
    public let tracker: RangeTracker
    public let equity: EquityEngine.Result
    public let potOdds: PotMath.PotOdds
    public let spr: Double
    public let liveOpponentsToAct: [Int]
    public let inPosition: Bool
    /// Hero made the last aggressive action on the previous street.
    public let hasInitiative: Bool
    /// Precomputed weak-range fraction per live opponent (fold-equity input),
    /// computed once per decision rather than once per candidate.
    public let weakFractionBySeat: [Int: Double]

    /// Builds the full context. `iterations` bounds the equity budget (§17).
    public static func build(obs: BotObservation, config: StrategyConfig, iterations: Int, seed: UInt64) -> PostflopContext {
        let madeHand = MadeHandAnalyzer.analyze(hole: obs.holeCards, board: obs.board, opponents: obs.activeOpponentCount)
        let draws = DrawAnalyzer.analyze(hole: obs.holeCards, board: obs.board)
        let features = BoardTexture.features(for: obs.board)
        let tracker = RangeTracker.build(events: obs.visibleEvents, viewpointSeat: obs.seat, viewpointCards: obs.holeCards, config: config)

        let liveOpponents = obs.opponents.filter { !$0.hasFolded }
        let ranges = liveOpponents.compactMap { tracker.ranges[$0.seatIndex] }.filter { !$0.isEmpty }
        let equity: EquityEngine.Result
        if ranges.isEmpty {
            let uniform = HandRange.uniform(excluding: Set(obs.holeCards + obs.board))
            equity = EquityEngine.equity(hole: obs.holeCards, board: obs.board, vsRanges: [uniform], iterations: iterations, seed: seed)
        } else {
            equity = EquityEngine.equity(hole: obs.holeCards, board: obs.board, vsRanges: ranges, iterations: iterations, seed: seed)
        }

        let odds = PotMath.odds(amountToCall: obs.available.callCost, potBeforeCall: obs.pot)
        let spr = obs.pot > 0 ? Double(obs.myStack) / Double(obs.pot) : 10

        // Opponents still able to respond (live, not all-in).
        let toAct = liveOpponents.filter { !$0.isAllIn }.map { $0.seatIndex }

        // Postflop action order runs from the seat left of the button around
        // to the button, which acts last. Hero is in position when every live
        // non-all-in opponent acts earlier in that order.
        let seatCount = max(obs.opponents.map { $0.seatIndex }.max() ?? 0, obs.seat, obs.buttonIndex) + 1
        func orderIndex(_ seat: Int) -> Int {
            let offset = ((seat - obs.buttonIndex) % seatCount + seatCount) % seatCount
            return offset == 0 ? seatCount : offset
        }
        let heroOrder = orderIndex(obs.seat)
        let heroActsLast = toAct.allSatisfy { orderIndex($0) < heroOrder }

        // Initiative: the last bet/raise on any earlier street was hero's.
        var lastAggressor: Int? = nil
        for event in obs.visibleEvents {
            if case .action(let seat, let street, let kind, _, _, _) = event,
               street < obs.street, kind == .bet || kind == .raise {
                lastAggressor = seat
            }
        }

        var weakFractions: [Int: Double] = [:]
        for seat in toAct {
            weakFractions[seat] = tracker.weakFraction(seat: seat, board: obs.board)
        }

        return PostflopContext(
            obs: obs,
            madeHand: madeHand,
            draws: draws,
            features: features,
            tracker: tracker,
            equity: equity,
            potOdds: odds,
            spr: spr,
            liveOpponentsToAct: toAct,
            inPosition: heroActsLast,
            hasInitiative: lastAggressor == obs.seat,
            weakFractionBySeat: weakFractions
        )
    }
}

/// Candidate generation and interpretable scoring (§20-§25).
public enum PostflopDecision {

    // MARK: - Candidate generation

    public static func candidates(for context: PostflopContext) -> [ActionCandidate] {
        let obs = context.obs
        let available = obs.available
        var result: [ActionCandidate] = []

        if available.canCheck {
            result.append(ActionCandidate(action: .check, label: "check", purpose: .checkBack))
        } else {
            result.append(ActionCandidate(action: .fold, label: "fold", purpose: .fold))
            if available.canCall {
                result.append(ActionCandidate(action: .call, label: "call \(available.callCost)", purpose: .call))
            }
        }

        guard let options = available.betRaise else { return result }

        // Street-specific pot-fraction families (§20).
        let fractions: [Double]
        switch obs.street {
        case .flop: fractions = [0.33, 0.5, 0.75]
        case .turn: fractions = [0.5, 0.75, 1.0]
        case .river: fractions = [0.33, 0.66, 1.0, 1.5]
        case .preflop: fractions = [1.0]
        }

        var seenAmounts = Set<Int>()
        func addBet(_ target: Int, _ label: String, _ purpose: ActionCandidate.Purpose) {
            var amount = max(options.minTo, min(target, options.maxTo))
            if !options.isLegal(toAmount: amount) {
                amount = amount < options.minFullTo ? options.minTo : options.maxTo
            }
            guard seenAmounts.insert(amount).inserted else { return }
            let verb = options.kind == .bet ? "bet" : "raise to"
            result.append(ActionCandidate(action: PlayerAction(kind: options.kind, toAmount: amount), label: "\(verb) \(amount)", purpose: purpose))
        }

        let potAfterCall = obs.pot + available.callCost
        for fraction in fractions {
            let target = obs.myCommittedThisStreet + available.callCost + Int((Double(potAfterCall) * fraction).rounded())
            // Purpose is refined during scoring; use a neutral default here.
            let purpose: ActionCandidate.Purpose = fraction >= 1.25 ? .allInLeverage : .value
            addBet(target, "\(Int(fraction * 100))%", purpose)
        }
        // Raising over a bet: include a min-raise and a standard raise.
        if !available.canCheck {
            addBet(options.minTo, "min-raise", .value)
            addBet(Int(Double(obs.currentBet) * 2.6), "raise", .value)
        }
        // All-in when the stack-to-pot ratio makes it a real lever (§22).
        if context.spr < 2.5 || context.madeHand.isNearNuts {
            addBet(options.maxTo, "all-in", .allInLeverage)
        }
        return result
    }

    // MARK: - Scoring

    public struct Outcome: Sendable {
        public let action: PlayerAction
        public let trace: DecisionTrace
    }

    /// Scores candidates and picks one with bounded, seeded mixing (§21).
    public static func choose(
        context: PostflopContext,
        profile: BotProfile,
        config: StrategyConfig,
        rng: inout SeededRNG,
        seed: UInt64
    ) -> Outcome {
        let candidates = self.candidates(for: context)
        var scores: [CandidateScore] = []
        var best: (score: Double, index: Int) = (-Double.infinity, 0)

        for (index, candidate) in candidates.enumerated() {
            let score = self.score(candidate: candidate, context: context, profile: profile, config: config, rng: &rng)
            scores.append(score)
            if score.finalScore > best.score {
                best = (score.finalScore, index)
            }
        }

        // Controlled mixing: pick among candidates within a small window of
        // the best, weighted by closeness (§8, §21). Window scales with pot.
        let window = Double(context.obs.pot) * 0.055 + 1
        var eligible: [(index: Int, weight: Double)] = []
        for (index, score) in scores.enumerated() {
            let gap = best.score - score.finalScore
            if gap <= window {
                eligible.append((index, max(0.05, 1 - gap / window)))
            }
        }
        var chosenIndex = best.index
        if eligible.count > 1 && config.mixingBand > 0 {
            let total = eligible.reduce(0.0) { $0 + $1.weight }
            var target = rng.double01() * total
            for entry in eligible {
                target -= entry.weight
                if target <= 0 {
                    chosenIndex = entry.index
                    break
                }
            }
        }

        let chosen = candidates[chosenIndex]
        var comboCounts: [Int: Double] = [:]
        for (seat, range) in context.tracker.ranges {
            comboCounts[seat] = (range.comboCount * 100).rounded() / 100
        }
        let trace = DecisionTrace(
            street: context.obs.street.name,
            equity: context.equity.share,
            equityTrials: context.equity.trials,
            equityExact: context.equity.isExact,
            madeHandClass: context.madeHand.handClass.name,
            fractionBeaten: context.madeHand.fractionBeaten,
            potOdds: context.potOdds.requiredEquity,
            sprText: String(format: "%.1f", context.spr),
            opponentCount: context.obs.activeOpponentCount,
            trackedComboCounts: comboCounts,
            scores: scores,
            chosenLabel: chosen.label,
            seed: seed
        )
        return Outcome(action: chosen.action, trace: trace)
    }

    /// Interpretable per-candidate scoring (§19, §21-§25). EV units: chips.
    /// `noiseScale` 0 gives the deterministic, personality-noise-free scores
    /// used by post-hand analysis.
    public static func score(
        candidate: ActionCandidate,
        context: PostflopContext,
        profile: BotProfile,
        config: StrategyConfig,
        rng: inout SeededRNG,
        noiseScale: Double = 1
    ) -> CandidateScore {
        let obs = context.obs
        let equity = context.equity.share
        let pot = Double(obs.pot)
        let toCall = Double(obs.available.callCost)
        let opponents = max(1, context.liveOpponentsToAct.count + obs.opponents.filter { $0.isAllIn && !$0.hasFolded }.count)
        let streetsLeft = 3 - min(3, obs.street.rawValue)

        var baseEV = 0.0
        var positional = 0.0
        var drawAdj = 0.0
        var blockerAdj = 0.0
        var personality = 0.0

        switch candidate.action.kind {
        case .fold:
            baseEV = 0

        case .check:
            // Realized equity discounts out-of-position, wet-board checks.
            var realization = context.inPosition ? 1.0 : 0.86
            if context.features.wetness > 0.5 && streetsLeft > 0 { realization -= 0.08 }
            baseEV = equity * pot * realization
            // Trappers deliberately check strong hands (§9).
            if profile.archetype == .trapper && context.madeHand.fractionBeaten > 0.85 && streetsLeft > 0 {
                personality += pot * 0.18
            }
            // Vulnerable hands dislike free cards (§13, §22 protection).
            if context.madeHand.isVulnerable && streetsLeft > 0 {
                personality -= pot * 0.12
            }

        case .call:
            baseEV = PotMath.callEV(equity: equity, amountToCall: obs.available.callCost, potBeforeCall: obs.pot)
            // Implied odds for strong draws with money behind (§18, §27).
            if streetsLeft > 0 && context.draws.isStrongDraw {
                let behind = Double(obs.myStack) - toCall
                drawAdj += min(pot * 0.25, behind * 0.03)
            }
            // Reverse-implied warning: weak made hands facing more streets.
            if streetsLeft > 0 && context.madeHand.handClass <= .middlePair && context.features.wetness > 0.45 {
                drawAdj -= pot * 0.05
            }
            // Sticky players overvalue calling; nits undervalue it (bounded).
            personality += (config.callScale - 1.0) * pot * 0.12

        case .bet, .raise:
            let target = candidate.action.toAmount
            let myAddition = Double(target - obs.myCommittedThisStreet)
            let potAfterCall = pot + toCall

            // Fold-equity model from tracked range weakness (§21).
            let sizeRatio = myAddition / max(1, potAfterCall)
            var allFold = 1.0
            var totalWeak = 0.0
            for seat in context.liveOpponentsToAct {
                let weakness = context.weakFractionBySeat[seat] ?? 0.45
                totalWeak += weakness
                let pressure = min(0.92, weakness * (0.55 + min(1.4, sizeRatio) * 0.65))
                allFold *= pressure
            }
            if context.liveOpponentsToAct.isEmpty { allFold = 0 }
            let averageWeak = context.liveOpponentsToAct.isEmpty ? 0 : totalWeak / Double(context.liveOpponentsToAct.count)

            // Equity when called: callers hold the stronger part of the range.
            let equityWhenCalled = max(0, equity - 0.12 * averageWeak - 0.03 * Double(opponents - 1))
            let calledPot = potAfterCall + myAddition * 2 // one caller model
            baseEV = allFold * pot + (1 - allFold) * (equityWhenCalled * calledPot - myAddition)

            // Semi-bluff leverage: strong draws add barrels and outs (§23).
            if streetsLeft > 0 {
                drawAdj += context.draws.estimatedCleanOuts * pot * 0.008
            }
            // Blockers: bluffing with the nut-flush-suit ace is more credible.
            if equity < 0.42 && context.draws.nutFlushDraw {
                blockerAdj += pot * 0.05
            }
            if equity < 0.42 && context.features.flushLevel == 2 {
                let flushSuits = obs.board.map { $0.suit }
                if let suit = mostCommonSuit(flushSuits), obs.holeCards.contains(Card(.ace, suit)) {
                    blockerAdj += pot * 0.07
                }
            }
            // Protection value for vulnerable made hands (§22).
            if context.madeHand.isVulnerable && context.madeHand.fractionBeaten > 0.6 && streetsLeft > 0 {
                positional += pot * 0.08
            }
            // In-position aggression realizes better (§21).
            positional += context.inPosition ? pot * 0.03 : -pot * 0.02
            // Continuation/barrel tendencies apply with initiative (§3).
            if context.hasInitiative && obs.available.canCheck {
                let knob = obs.street == .flop ? config.cbetFrequency : config.barrelFrequency
                personality += (knob - 0.5) * pot * 0.16
            }
            // Multiway: bluffs shrink, value tightens (§25).
            if opponents >= 2 && equity < 0.5 {
                positional -= pot * 0.10 * Double(opponents - 1)
            }
            // Personality: aggression, bluffiness, trapper's reluctance (§9).
            let isBluffish = equity < 0.40
            if isBluffish {
                personality += (config.bluffScale - 1.0) * pot * 0.15
                // River bluff discipline knob.
                if obs.street == .river {
                    personality += (config.riverBluffFrequency - 0.22) * pot * 0.5
                }
            } else {
                personality += (profile.aggression - 0.5) * pot * 0.08
                // Thin-value shift: negative bets thinner (§24).
                if context.madeHand.fractionBeaten > 0.55 && context.madeHand.fractionBeaten < 0.75 {
                    personality -= config.valueThresholdShift * pot * 1.2
                }
            }
            if profile.archetype == .trapper && context.madeHand.fractionBeaten > 0.85 && streetsLeft > 0 {
                personality -= pot * 0.10
            }
            // SPR: with a tiny SPR and a real hand, all-in simplification (§22).
            if candidate.action.toAmount == obs.available.betRaise?.maxTo
                && context.spr < 1.5 && context.madeHand.fractionBeaten > 0.7 {
                positional += pot * 0.07
            }
        }

        // Difficulty noise: weaker bots misjudge (§10). Seeded, bounded.
        let noise = (rng.double01() - 0.5) * profile.difficulty.decisionNoise * (pot * 0.3 + 2) * noiseScale

        return CandidateScore(
            label: candidate.label,
            purposeTag: candidate.purpose.rawValue,
            baseEV: round2(baseEV),
            positionalAdjustment: round2(positional),
            drawAdjustment: round2(drawAdj),
            blockerAdjustment: round2(blockerAdj),
            personalityAdjustment: round2(personality),
            noise: round2(noise)
        )
    }

    private static func round2(_ value: Double) -> Double {
        return (value * 100).rounded() / 100
    }

    private static func mostCommonSuit(_ suits: [Suit]) -> Suit? {
        var counts: [Suit: Int] = [:]
        for suit in suits {
            counts[suit, default: 0] += 1
        }
        return counts.max { $0.value < $1.value }?.key
    }
}
