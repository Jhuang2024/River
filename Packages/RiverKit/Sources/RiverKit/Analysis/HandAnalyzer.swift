import Foundation

/// Result-independent post-hand analysis (§32-36).
///
/// The analyzer re-simulates the recorded hand from its seed and action
/// sequence (the engine is deterministic), pauses at every hero decision,
/// rebuilds the information legally visible at that moment - including
/// tracked opponent ranges - and evaluates the same candidate set the AI
/// uses, with personality and noise switched off. The output is a pure
/// function of the stored history, so re-running it later reproduces the
/// original grades (§47).
public enum HandAnalyzer {

    /// Neutral evaluation profile: no exploit personality, no noise.
    private static var analystProfile: BotProfile {
        return BotProfile(
            name: "Analyst",
            symbolName: "brain",
            archetype: .solidRegular,
            difficulty: .elite,
            looseness: 0.3,
            aggression: 0.5,
            bluffFrequency: 0.25,
            callStickiness: 0.5,
            sizingJitter: 0,
            positionAwareness: 1,
            note: ""
        )
    }

    /// Analyzes every hero decision. `iterations` is the equity budget per
    /// decision (§17: post-hand analysis may spend more than live play).
    public static func analyze(history: HandHistory, iterations: Int = 500) -> [DecisionAnalysis] {
        // Rebuild the hand. If the stored seed cannot reproduce the recorded
        // deal (e.g. debug-rigged decks), skip analysis rather than lie.
        let config = HandConfig(
            stacks: history.startingStacks,
            buttonIndex: history.buttonIndex,
            smallBlind: history.smallBlind,
            bigBlind: history.bigBlind,
            ante: history.ante,
            seed: history.seed,
            handNumber: history.handNumber
        )
        guard history.startingStacks.filter({ $0 > 0 }).count >= 2 else { return [] }
        let hand = PokerHand(config: config)

        // Verify the re-simulated deal matches the record.
        for event in history.events {
            if case .dealtHoleCards(let seat, let cards) = event {
                guard hand.seats.indices.contains(seat), hand.seats[seat].holeCards == cards else {
                    return []
                }
            }
        }

        // The recorded voluntary actions, in order.
        var actionsToApply: [(seat: Int, action: PlayerAction)] = []
        for event in history.events {
            if case .action(let seat, _, let kind, _, let toTotal, _) = event {
                actionsToApply.append((seat, PlayerAction(kind: kind, toAmount: toTotal)))
            }
        }

        var results: [DecisionAnalysis] = []
        var decisionIndex = 0
        let bb = Double(max(1, history.bigBlind))
        let baselineConfig = StrategyConfig.baseline

        for entry in actionsToApply {
            guard !hand.isComplete else { break }
            guard hand.actionOn == entry.seat else { break }

            if entry.seat == history.heroSeat, let obs = hand.observation(for: entry.seat) {
                if let analysis = analyzeDecision(
                    observation: obs,
                    chosen: entry.action,
                    decisionIndex: decisionIndex,
                    bigBlind: bb,
                    config: baselineConfig,
                    iterations: iterations,
                    handSeed: history.seed
                ) {
                    results.append(analysis)
                }
            }

            do {
                try hand.apply(entry.action, by: entry.seat)
            } catch {
                break
            }
            decisionIndex += 1
        }
        return results
    }

    // MARK: - Single decision

    /// Analyzes one decision from the information visible at that moment.
    /// Public so scenario tests can grade constructed situations directly.
    public static func analyzeDecision(
        observation obs: BotObservation,
        chosen: PlayerAction,
        decisionIndex: Int,
        bigBlind bb: Double,
        config: StrategyConfig = .baseline,
        iterations: Int = 500,
        handSeed: UInt64 = 0
    ) -> DecisionAnalysis? {
        if obs.street == .preflop {
            return analyzePreflop(obs: obs, chosen: chosen, decisionIndex: decisionIndex, bigBlind: bb, config: config)
        }
        return analyzePostflop(obs: obs, chosen: chosen, decisionIndex: decisionIndex, bigBlind: bb, config: config, iterations: iterations, handSeed: handSeed)
    }

    private static func analyzePostflop(
        obs: BotObservation,
        chosen: PlayerAction,
        decisionIndex: Int,
        bigBlind bb: Double,
        config: StrategyConfig,
        iterations: Int,
        handSeed: UInt64
    ) -> DecisionAnalysis? {
        var seedRng = SeededRNG.derive(seed: handSeed, stream: 0xA11A &+ UInt64(decisionIndex))
        let seed = seedRng.nextUInt64()
        let context = PostflopContext.build(obs: obs, config: config, iterations: iterations, seed: seed)

        // Candidate set plus the exact chosen action.
        var candidates = PostflopDecision.candidates(for: context)
        let chosenLabel = label(for: chosen, obs: obs)
        if !candidates.contains(where: { sameAction($0.action, chosen) }) {
            candidates.append(ActionCandidate(action: chosen, label: chosenLabel, purpose: .call))
        }

        var evaluations: [CandidateEvaluation] = []
        var best: (ev: Double, label: String) = (-Double.infinity, "fold")
        var chosenEV = 0.0
        var noiseRng = SeededRNG(seed: seed) // unused at noiseScale 0, but required
        for candidate in candidates {
            let score = PostflopDecision.score(
                candidate: candidate, context: context,
                profile: analystProfile, config: config,
                rng: &noiseRng, noiseScale: 0
            )
            let evBB = round2(score.finalScore / bb)
            evaluations.append(CandidateEvaluation(
                label: candidate.label,
                kind: candidate.action.kind,
                toAmount: candidate.action.toAmount,
                evBB: evBB
            ))
            if score.finalScore > best.ev {
                best = (score.finalScore, candidate.label)
            }
            if sameAction(candidate.action, chosen) {
                chosenEV = score.finalScore
            }
        }

        var evLossBB = max(0, (best.ev - chosenEV) / bb)
        // "Missed value" softening: when the chosen line was itself clearly
        // +EV with a strong hand and the best line merely extracts more, the
        // gap is dominated by fold-equity model uncertainty. Treat it as a
        // sizing/line inaccuracy, never a blunder (§19, §34: don't fabricate
        // certainty the model doesn't have).
        let missedValueOnly = chosenEV > 0 && best.ev > 0 && context.equity.share >= 0.6
        if missedValueOnly {
            evLossBB *= 0.4
        }
        let sortedEVs = evaluations.map { $0.evBB }.sorted(by: >)
        let topGap = sortedEVs.count >= 2 ? sortedEVs[0] - sortedEVs[1] : 10
        let chosenIsTopTwo = evaluations.sorted { $0.evBB > $1.evBB }.prefix(2).contains { $0.label == chosenLabel }
        let isClose = topGap <= GradingThresholds.mixedBand && chosenIsTopTwo

        let confidence = postflopConfidence(context: context, topGap: topGap)
        var grade = GradingThresholds.grade(evLossBB: evLossBB, isCloseDecision: isClose, confidence: confidence)
        if missedValueOnly && (grade == .blunder || grade == .significantMistake) {
            grade = .inaccuracy
        }

        var tags: [String] = ["equity"]
        if obs.available.callCost > 0 { tags.append("pot odds") }
        if context.equity.share < 0.4 { tags.append("bluff catcher") }
        if context.madeHand.fractionBeaten > 0.6 { tags.append("value") }
        if context.features.wetness > 0.5 { tags.append("board texture") }
        if context.obs.activeOpponentCount >= 2 { tags.append("multiway adjustment") }
        if context.draws.isStrongDraw { tags.append("implied odds") }
        if context.spr < 2 { tags.append("stack-to-pot ratio") }
        if context.inPosition { tags.append("position") }

        let explanation = ExplanationBuilder.postflop(
            obs: obs,
            context: context,
            recommended: best.label,
            chosen: chosenLabel,
            evLossBB: evLossBB,
            isClose: isClose,
            confidence: confidence
        )

        return DecisionAnalysis(
            decisionIndex: decisionIndex,
            street: obs.street,
            potBefore: obs.pot,
            toCall: obs.available.callCost,
            equity: round2(context.equity.share),
            requiredEquity: round2(context.potOdds.requiredEquity),
            candidates: evaluations,
            recommendedLabel: best.label,
            chosenLabel: chosenLabel,
            evLossBB: round2(evLossBB),
            grade: grade,
            confidence: confidence,
            explanation: explanation,
            tags: tags,
            strategyVersion: StrategyConfig.version,
            analysisVersion: DecisionAnalysis.analysisVersion
        )
    }

    /// Preflop grading is range-based: severity scales with how far the hand
    /// sits from the configured threshold for the recommended action.
    private static func analyzePreflop(
        obs: BotObservation,
        chosen: PlayerAction,
        decisionIndex: Int,
        bigBlind bb: Double,
        config: StrategyConfig
    ) -> DecisionAnalysis? {
        let context = PreflopContext.build(from: obs)
        var pureConfig = config
        pureConfig.mixingBand = 0
        var rng = SeededRNG(seed: 1)
        let recommendation = PreflopStrategy.decide(obs: obs, context: context, config: pureConfig, rng: &rng)
        let combo = HoleCombo(obs.holeCards[0], obs.holeCards[1])
        let percentile = HandOrdering.percentile(of: combo)
        let chosenLabel = label(for: chosen, obs: obs)
        let recommendedLabel = label(for: recommendation.action, obs: obs)

        // Severity: distance from the relevant range boundary, in "range
        // percentage" points, converted to an approximate BB scale.
        let matches = chosen.kind == recommendation.action.kind
        var evLossBB = 0.0
        if !matches {
            let boundary = relevantBoundary(context: context, config: pureConfig)
            let distance = abs(percentile - boundary)
            // Folding a premium or playing trash: worst case a few BB pre.
            evLossBB = min(6, distance * 12)
            // Overfolding when checking was free is pure loss.
            if chosen.kind == .fold && obs.available.canCheck {
                evLossBB = max(evLossBB, 1.0)
            }
            // Aggression vs call disagreement matters less than fold errors.
            let bothVoluntary = chosen.kind != .fold && recommendation.action.kind != .fold
            if bothVoluntary {
                evLossBB *= 0.45
            }
        }
        let boundary = relevantBoundary(context: context, config: pureConfig)
        let isClose = abs(percentile - boundary) < 0.05
        if isClose { evLossBB = min(evLossBB, 0.5) }
        let confidence: AnalysisConfidence = isClose ? .low : .moderate
        let grade = GradingThresholds.grade(evLossBB: evLossBB, isCloseDecision: isClose, confidence: confidence)

        let explanation = ExplanationBuilder.preflop(
            obs: obs,
            context: context,
            comboLabel: combo.label,
            percentile: percentile,
            recommended: recommendedLabel,
            chosen: chosenLabel,
            matches: matches,
            isClose: isClose
        )

        var tags = ["preflop range", "position"]
        if context.effectiveStackBB <= 15 { tags.append("stack-to-pot ratio") }
        if context.raiseCount >= 1 { tags.append("pot odds") }

        return DecisionAnalysis(
            decisionIndex: decisionIndex,
            street: .preflop,
            potBefore: obs.pot,
            toCall: obs.available.callCost,
            equity: round2(1 - percentile),
            requiredEquity: round2(PotMath.odds(amountToCall: obs.available.callCost, potBeforeCall: obs.pot).requiredEquity),
            candidates: [],
            recommendedLabel: recommendedLabel,
            chosenLabel: chosenLabel,
            evLossBB: round2(evLossBB),
            grade: grade,
            confidence: confidence,
            explanation: explanation,
            tags: tags,
            strategyVersion: StrategyConfig.version,
            analysisVersion: DecisionAnalysis.analysisVersion
        )
    }

    private static func relevantBoundary(context: PreflopContext, config: StrategyConfig) -> Double {
        if context.effectiveStackBB <= config.pushFoldThresholdBB {
            return config.shovePercent[context.position] ?? 0.2
        }
        switch context.raiseCount {
        case 0:
            return config.openPercent[context.position] ?? 0.2
        case 1:
            switch context.position {
            case .bigBlind: return config.bbDefendCallPercent
            case .smallBlind: return config.sbDefendCallPercent
            default: return (config.callVsOpenPercent[context.position] ?? 0.1) + (config.threeBetPercent[context.position] ?? 0.05)
            }
        case 2:
            return config.callThreeBetPercent + config.fourBetPercent
        default:
            return config.callFourBetPercent + config.fiveBetAllInPercent
        }
    }

    private static func postflopConfidence(context: PostflopContext, topGap: Double) -> AnalysisConfidence {
        if context.obs.activeOpponentCount >= 3 { return .low }
        if topGap <= GradingThresholds.mixedBand { return .low }
        if context.equity.isExact && context.obs.activeOpponentCount == 1 { return .high }
        if context.equity.trials >= 300 && topGap > 1.0 { return .high }
        return .moderate
    }

    private static func sameAction(_ a: PlayerAction, _ b: PlayerAction) -> Bool {
        if a.kind != b.kind { return false }
        if a.kind == .bet || a.kind == .raise {
            return a.toAmount == b.toAmount
        }
        return true
    }

    private static func label(for action: PlayerAction, obs: BotObservation) -> String {
        switch action.kind {
        case .fold: return "fold"
        case .check: return "check"
        case .call: return "call \(obs.available.callCost)"
        case .bet: return "bet \(action.toAmount)"
        case .raise: return "raise to \(action.toAmount)"
        }
    }

    private static func round2(_ value: Double) -> Double {
        return (value * 100).rounded() / 100
    }
}

/// Deterministic local explanation templates (§36) - situation, mathematics,
/// range context, recommendation, reason, honesty about closeness. No
/// language model, no external service.
enum ExplanationBuilder {

    static func postflop(
        obs: BotObservation,
        context: PostflopContext,
        recommended: String,
        chosen: String,
        evLossBB: Double,
        isClose: Bool,
        confidence: AnalysisConfidence
    ) -> String {
        var parts: [String] = []
        let equityPct = Int((context.equity.share * 100).rounded())
        let opponents = obs.activeOpponentCount

        // 1. Situation + 2. Mathematical requirement.
        if obs.available.callCost > 0 {
            let odds = context.potOdds
            parts.append("You faced \(odds.amountToCall) into a pot of \(odds.potBeforeCall); calling makes the pot \(odds.finalPot), so you needed about \(Int((odds.requiredEquity * 100).rounded()))% equity.")
        } else {
            parts.append("Checking was free with a pot of \(obs.pot).")
        }
        // 3. Range / strategic context.
        parts.append("Against the estimated range\(opponents == 1 ? "" : "s") of \(opponents) opponent\(opponents == 1 ? "" : "s"), your \(context.madeHand.handClass.name) had roughly \(equityPct)% equity\(context.equity.isExact ? "" : " (simulated)").")
        if context.draws.isStrongDraw {
            parts.append("You also held a strong draw (~\(Int(context.draws.estimatedCleanOuts.rounded())) outs).")
        } else if context.madeHand.isVulnerable {
            parts.append("The hand was strong but vulnerable on this board.")
        }
        // 4-5. Recommendation and reason.
        if isClose {
            parts.append("The best options were very close: \(recommended) rates marginally best, but \(chosen) is defensible.")
        } else if evLossBB < GradingThresholds.strong {
            parts.append("Your \(chosen) matches the best line (\(recommended)).")
        } else {
            parts.append("\(recommended.prefix(1).capitalized)\(recommended.dropFirst()) was preferable; \(chosen) gives up an estimated \(String(format: "%.1f", evLossBB)) big blinds.")
        }
        if confidence == .low {
            parts.append("Confidence is low: the range model for this spot is uncertain.")
        }
        parts.append("Estimates are approximate, judged on the information available at the time.")
        return parts.joined(separator: " ")
    }

    static func preflop(
        obs: BotObservation,
        context: PreflopContext,
        comboLabel: String,
        percentile: Double,
        recommended: String,
        chosen: String,
        matches: Bool,
        isClose: Bool
    ) -> String {
        var parts: [String] = []
        let pct = Int((percentile * 100).rounded())
        parts.append("\(comboLabel) is roughly a top-\(max(1, pct))% hand.")
        parts.append("From \(context.position.shortName) at \(Int(context.effectiveStackBB)) big blinds\(context.raiseCount > 0 ? ", facing \(context.raiseCount == 1 ? "an open" : "a re-raise")" : ""), a disciplined baseline would \(recommended).")
        if matches {
            parts.append("Your \(chosen) lines up with that range.")
        } else if isClose {
            parts.append("Your \(chosen) differs, but the hand sits right at the edge of the range: both lines are defensible.")
        } else {
            parts.append("Your \(chosen) strays from the range for this position and stack depth.")
        }
        return parts.joined(separator: " ")
    }
}
