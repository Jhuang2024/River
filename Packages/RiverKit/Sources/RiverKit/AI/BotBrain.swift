import Foundation

/// Layered bot decision logic: personality profile → preflop hand quality /
/// postflop equity estimate → candidate action choice with seeded mixing.
///
/// The brain only ever reads a `BotObservation`, which structurally cannot
/// contain hidden information. Given the same observation, profile and RNG
/// stream, decisions are fully deterministic.
public enum BotBrain {

    public static func decide(observation obs: BotObservation, profile: BotProfile, rng: inout SeededRNG) -> (action: PlayerAction, annotation: DecisionAnnotation) {
        if obs.street == .preflop {
            return decidePreflop(obs: obs, profile: profile, rng: &rng)
        }
        return decidePostflop(obs: obs, profile: profile, rng: &rng)
    }

    // MARK: - Shared helpers

    /// 1.0 on the button, approaching 0 in the earliest seat.
    private static func positionFactor(_ obs: BotObservation) -> Double {
        let n = obs.opponents.count + 1
        guard n > 1 else { return 1 }
        let total = max(obs.opponents.map { $0.seatIndex }.max() ?? 0, obs.seat, obs.buttonIndex) + 1
        let distance = ((obs.buttonIndex - obs.seat) % total + total) % total
        return 1 - Double(distance) / Double(total - 1)
    }

    /// Builds a legal bet/raise action, clamping the target into range.
    private static func betRaiseAction(target: Int, options: BetRaiseOptions) -> PlayerAction {
        var amount = max(options.minTo, min(target, options.maxTo))
        if !options.isLegal(toAmount: amount) {
            amount = options.minTo
        }
        return PlayerAction(kind: options.kind, toAmount: amount)
    }

    private static func chance(_ probability: Double, _ rng: inout SeededRNG) -> Bool {
        return rng.double01() < max(0, min(1, probability))
    }

    // MARK: - Preflop

    private static func decidePreflop(obs: BotObservation, profile: BotProfile, rng: inout SeededRNG) -> (action: PlayerAction, annotation: DecisionAnnotation) {
        let chen = PreflopHands.chenScore(for: obs.holeCards)
        let label = PreflopHands.label(for: obs.holeCards)
        let pos = positionFactor(obs)
        let bb = obs.bigBlind
        let toCall = obs.available.callCost
        let unraised = obs.currentBet <= bb

        let annotation = DecisionAnnotation(
            strengthEstimate: PreflopHands.strengthPercentile(for: obs.holeCards),
            advisorKind: nil,
            note: "\(label), Chen \(String(format: "%.1f", chen))"
        )

        // Base opening threshold, tightened in early position (scaled by how
        // position-aware this personality is) and shifted by looseness.
        let positionTerm = (1 - pos) * 3.0 * profile.positionAwareness
        var openThreshold = 6.0 + positionTerm
        openThreshold -= (profile.looseness - 0.25) * 8.0

        if unraised {
            if obs.available.canCheck {
                // Big blind option after limps.
                if chen >= openThreshold + 1 && chance(profile.aggression, &rng), let options = obs.available.betRaise {
                    let limpers = obs.opponents.filter { !$0.hasFolded && $0.committedThisStreet >= bb }.count
                    let target = sized(bbMultiple: 3.0 + Double(limpers), bb: bb, profile: profile, rng: &rng)
                    return (betRaiseAction(target: target, options: options), annotation)
                }
                return (.check, annotation)
            }
            // Facing just the blinds.
            if chen >= openThreshold {
                if let options = obs.available.betRaise, chance(0.35 + profile.aggression * 0.6, &rng) {
                    let limpers = obs.opponents.filter { !$0.hasFolded && $0.committedThisStreet >= bb }.count
                    let target = sized(bbMultiple: 3.0 + Double(limpers), bb: bb, profile: profile, rng: &rng)
                    return (betRaiseAction(target: target, options: options), annotation)
                }
                return (.call, annotation)
            }
            // Loose players limp along with speculative hands.
            let limpThreshold = openThreshold - 3.5
            if chen >= limpThreshold && chance(profile.looseness, &rng) {
                return (.call, annotation)
            }
            return (.fold, annotation)
        }

        // Facing a raise.
        let potOdds = toCall > 0 ? Double(toCall) / Double(obs.pot + toCall) : 0
        let bigDecision = toCall >= obs.myStack / 2

        var threeBetThreshold = 13.0 - profile.aggression * 2.5
        var callThreshold = 8.5 - profile.looseness * 4.0 - pos * profile.positionAwareness
        callThreshold -= profile.callStickiness * 2.0
        if bigDecision {
            // Calling for half the stack or more needs a premium hand.
            callThreshold = max(callThreshold, 11.5 - profile.callStickiness * 2.0)
            threeBetThreshold = max(threeBetThreshold, 12.0)
        }

        if chen >= threeBetThreshold, let options = obs.available.betRaise, chance(0.4 + profile.aggression * 0.5, &rng) {
            let target = min(obs.currentBet * 3, options.maxTo)
            return (betRaiseAction(target: target, options: options), annotation)
        }
        // Occasional light three-bet bluff from aggressive profiles.
        if !bigDecision, chen >= 7, let options = obs.available.betRaise, chance(profile.bluffFrequency * 0.25, &rng) {
            let target = min(obs.currentBet * 3, options.maxTo)
            return (betRaiseAction(target: target, options: options), annotation)
        }
        if chen >= callThreshold && obs.available.canCall {
            return (.call, annotation)
        }
        // Sticky players peel with a decent price.
        if obs.available.canCall && potOdds < 0.25 && chance(profile.callStickiness * 0.5, &rng) {
            return (.call, annotation)
        }
        if obs.available.canCheck {
            return (.check, annotation)
        }
        return (.fold, annotation)
    }

    private static func sized(bbMultiple: Double, bb: Int, profile: BotProfile, rng: inout SeededRNG) -> Int {
        let jitter = 1.0 + (rng.double01() - 0.5) * profile.sizingJitter
        return max(bb * 2, Int((bbMultiple * Double(bb) * jitter).rounded()))
    }

    // MARK: - Postflop

    private static func decidePostflop(obs: BotObservation, profile: BotProfile, rng: inout SeededRNG) -> (action: PlayerAction, annotation: DecisionAnnotation) {
        let iterations = profile.difficulty == .beginner ? 90 : 170
        let estimate = EquityEstimator.equityVsRandom(
            hole: obs.holeCards,
            board: obs.board,
            opponents: max(1, obs.activeOpponentCount),
            iterations: iterations,
            rng: &rng
        )
        let equity = estimate.equity
        let draws = EquityEstimator.detectDraws(hole: obs.holeCards, board: obs.board)
        let toCall = obs.available.callCost
        let potOdds = toCall > 0 ? Double(toCall) / Double(obs.pot + toCall) : 0

        let annotation = DecisionAnnotation(
            strengthEstimate: equity,
            advisorKind: nil,
            note: "equity ≈ \(Int((equity * 100).rounded()))% vs \(obs.activeOpponentCount) (\(estimate.samples) samples)"
        )

        // Beginner bots misjudge: blur their equity estimate.
        var perceived = equity
        if profile.difficulty == .beginner {
            perceived += (rng.double01() - 0.5) * 0.12
            perceived = max(0, min(1, perceived))
        }

        let opponentsIn = max(1, obs.activeOpponentCount)
        // Threshold for betting for value scales with number of opponents.
        let valueThreshold = 0.48 + 0.05 * Double(opponentsIn - 1) + (0.5 - profile.aggression) * 0.08
        let strongThreshold = 0.70 - profile.aggression * 0.06

        if obs.available.canCheck {
            if let options = obs.available.betRaise {
                // Value bet.
                if perceived >= valueThreshold && chance(0.35 + profile.aggression * 0.55, &rng) {
                    let fraction = perceived >= strongThreshold ? 0.75 : 0.55
                    return (betRaiseAction(target: potFractionTarget(fraction, obs: obs, profile: profile, rng: &rng), options: options), annotation)
                }
                // Semi-bluff with a real draw.
                if obs.street != .river && draws.estimatedOuts >= 4 && chance(profile.bluffFrequency + profile.aggression * 0.25, &rng) {
                    return (betRaiseAction(target: potFractionTarget(0.6, obs: obs, profile: profile, rng: &rng), options: options), annotation)
                }
                // Occasional stab at the pot.
                if chance(profile.bluffFrequency * 0.4, &rng) {
                    return (betRaiseAction(target: potFractionTarget(0.5, obs: obs, profile: profile, rng: &rng), options: options), annotation)
                }
            }
            return (.check, annotation)
        }

        // Facing a bet.
        let stickiness = profile.callStickiness * 0.12
        let raiseThreshold = strongThreshold + 0.05

        if perceived >= raiseThreshold, let options = obs.available.betRaise, chance(profile.aggression * 0.8, &rng) {
            let target = max(options.minTo, Int(Double(obs.currentBet) * 2.6))
            return (betRaiseAction(target: target, options: options), annotation)
        }
        // Semi-bluff raise.
        if obs.street != .river && draws.estimatedOuts >= 8, let options = obs.available.betRaise, chance(profile.bluffFrequency * 0.35, &rng) {
            return (betRaiseAction(target: options.minTo, options: options), annotation)
        }
        if obs.available.canCall {
            // Core pot-odds call, softened by stickiness and draw potential.
            let drawBonus = obs.street != .river ? Double(draws.estimatedOuts) * 0.004 : 0
            if perceived + stickiness + drawBonus >= potOdds {
                return (.call, annotation)
            }
            // All-in calls get extra scrutiny even from sticky players.
            if obs.available.isCallAllIn || toCall >= obs.myStack {
                if perceived >= potOdds * 0.9 && chance(profile.callStickiness * 0.4, &rng) {
                    return (.call, annotation)
                }
                return (.fold, annotation)
            }
            if chance(profile.callStickiness * 0.35, &rng) {
                return (.call, annotation)
            }
        }
        return (.fold, annotation)
    }

    /// Target "to" amount for a pot-fraction bet with personality jitter.
    private static func potFractionTarget(_ fraction: Double, obs: BotObservation, profile: BotProfile, rng: inout SeededRNG) -> Int {
        let jitter = 1.0 + (rng.double01() - 0.5) * profile.sizingJitter * 0.6
        let raw = Double(obs.pot) * fraction * jitter
        return obs.myCommittedThisStreet + max(obs.bigBlind, Int(raw.rounded()))
    }
}

/// Convenience used by the session runner and tests: derive the per-decision
/// RNG stream from the hand seed so every decision is reproducible.
public enum BotDecider {
    public static func decide(hand: PokerHand, seat: Int, profile: BotProfile) -> (action: PlayerAction, annotation: DecisionAnnotation)? {
        guard let obs = hand.observation(for: seat) else { return nil }
        let stream = UInt64(hand.decisions.count) &* 64 &+ UInt64(seat) &+ 7
        var rng = SeededRNG.derive(seed: hand.config.seed, stream: stream)
        return BotBrain.decide(observation: obs, profile: profile, rng: &rng)
    }
}
