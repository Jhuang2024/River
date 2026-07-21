import Foundation

/// Live recommendation for the human player (§38). Uses the same range-based
/// candidate machinery as the bots and the post-hand analyzer, with a
/// fast budget and no personality or noise. Explanations show the reasoning.
public struct Advice: Equatable, Sendable {
    public let kind: ActionKind
    /// Suggested "to" amount for bet/raise recommendations.
    public let toAmount: Int?
    public let equity: Double
    public let potOdds: Double
    public let explanation: String
}

public enum Advisor {

    private static var advisorProfile: BotProfile {
        return BotProfile(
            name: "Advisor",
            symbolName: "lightbulb",
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

    /// Computes a recommendation for the acting seat. Deterministic for a
    /// given hand seed. Runs bounded simulation; call it off the main thread.
    public static func advise(hand: PokerHand, seat: Int) -> Advice? {
        guard let obs = hand.observation(for: seat) else { return nil }
        var rng = SeededRNG.derive(seed: hand.config.seed, stream: 0xADD1CE &+ UInt64(hand.decisions.count))
        return advise(observation: obs, rng: &rng)
    }

    public static func advise(observation obs: BotObservation, rng: inout SeededRNG) -> Advice {
        if obs.street == .preflop {
            return advisePreflop(obs: obs, rng: &rng)
        }
        return advisePostflop(obs: obs, rng: &rng)
    }

    // MARK: - Preflop

    private static func advisePreflop(obs: BotObservation, rng: inout SeededRNG) -> Advice {
        var config = StrategyConfig.baseline
        config.mixingBand = 0
        let context = PreflopContext.build(from: obs)
        var pureRng = SeededRNG(seed: 1)
        let decision = PreflopStrategy.decide(obs: obs, context: context, config: config, rng: &pureRng)

        // Honest equity number: quick simulation versus unknown hands.
        let estimate = EquityEstimator.equityVsRandom(
            hole: obs.holeCards,
            board: [],
            opponents: max(1, obs.activeOpponentCount),
            iterations: 250,
            rng: &rng
        )
        let combo = HoleCombo(obs.holeCards[0], obs.holeCards[1])
        let percentile = HandOrdering.percentile(of: combo)
        let toCall = obs.available.callCost
        let odds = PotMath.odds(amountToCall: toCall, potBeforeCall: obs.pot)

        var reason = "\(combo.label) is roughly a top-\(max(1, Int((percentile * 100).rounded())))% starting hand. "
        reason += "From \(context.position.shortName)"
        if context.raiseCount > 0 {
            reason += " facing \(context.raiseCount == 1 ? "an open" : "a re-raise")"
        }
        reason += " at \(Int(context.effectiveStackBB)) big blinds, "
        switch decision.action.kind {
        case .fold:
            reason += "this hand sits outside a disciplined range: folding keeps your chips for better spots."
        case .check:
            reason += "checking keeps the pot small with a free option."
        case .call:
            if toCall > 0 {
                reason += "the price of \(toCall) into \(odds.finalPot) makes calling reasonable with this hand."
            } else {
                reason += "calling is reasonable with this hand."
            }
        case .bet, .raise:
            reason += "this hand is comfortably inside the raising range: take the initiative."
        }

        return Advice(
            kind: decision.action.kind,
            toAmount: decision.action.kind == .bet || decision.action.kind == .raise ? decision.action.toAmount : nil,
            equity: estimate.equity,
            potOdds: odds.requiredEquity,
            explanation: reason
        )
    }

    // MARK: - Postflop

    private static func advisePostflop(obs: BotObservation, rng: inout SeededRNG) -> Advice {
        let config = StrategyConfig.baseline
        let seed = rng.nextUInt64()
        let context = PostflopContext.build(obs: obs, config: config, iterations: 300, seed: seed)

        var candidates = PostflopDecision.candidates(for: context)
        if candidates.isEmpty {
            candidates = [ActionCandidate(action: .check, label: "check", purpose: .checkBack)]
        }
        var best: (score: Double, candidate: ActionCandidate) = (-Double.infinity, candidates[0])
        var second = -Double.infinity
        var noiseRng = SeededRNG(seed: seed)
        for candidate in candidates {
            let score = PostflopDecision.score(
                candidate: candidate, context: context,
                profile: advisorProfile, config: config,
                rng: &noiseRng, noiseScale: 0
            )
            if score.finalScore > best.score {
                second = best.score
                best = (score.finalScore, candidate)
            } else if score.finalScore > second {
                second = score.finalScore
            }
        }

        let equityPct = Int((context.equity.share * 100).rounded())
        let odds = context.potOdds
        let bb = Double(max(1, obs.bigBlind))
        let gapBB = (best.score - second) / bb
        let opponents = obs.activeOpponentCount

        var reason = ""
        if obs.available.callCost > 0 {
            reason += "You must pay \(odds.amountToCall) into a final pot of \(odds.finalPot), needing about \(Int((odds.requiredEquity * 100).rounded()))% equity. "
        }
        reason += "Your \(context.madeHand.handClass.name) has roughly \(equityPct)% equity against \(opponents) estimated range\(opponents == 1 ? "" : "s"). "
        switch best.candidate.action.kind {
        case .fold:
            reason += "That falls short of the price: folding saves chips."
        case .check:
            reason += context.madeHand.fractionBeaten > 0.6
                ? "Checking controls the pot and invites bluffs."
                : "Checking keeps the pot small with a modest hand."
        case .call:
            reason += "That clears the price, so calling is profitable."
        case .bet, .raise:
            if context.equity.share >= 0.55 {
                reason += "Betting builds the pot while you rate to be ahead."
            } else if context.draws.isStrongDraw {
                reason += "A semi-bluff applies pressure while your draw keeps real outs."
            } else {
                reason += "Aggression here leans on the opponent's weak range."
            }
        }
        if gapBB < 0.3 {
            reason += " The alternatives are close: this is not a clear-cut spot."
        }

        return Advice(
            kind: best.candidate.action.kind,
            toAmount: best.candidate.action.kind == .bet || best.candidate.action.kind == .raise ? best.candidate.action.toAmount : nil,
            equity: context.equity.share,
            potOdds: obs.available.callCost > 0 ? odds.requiredEquity : 0,
            explanation: reason
        )
    }
}
