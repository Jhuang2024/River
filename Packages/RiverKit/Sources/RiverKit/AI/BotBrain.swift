import Foundation

/// Layered bot decision pipeline (§1): profile → configured preflop ranges /
/// postflop range-based candidate scoring → seeded controlled mixing.
///
/// The brain only ever reads a `BotObservation`, which structurally cannot
/// contain hidden information. Given the same observation, profile and RNG
/// stream, decisions are fully deterministic (§43).
public enum BotBrain {

    /// Backwards-compatible entry point.
    public static func decide(observation obs: BotObservation, profile: BotProfile, rng: inout SeededRNG) -> (action: PlayerAction, annotation: DecisionAnnotation) {
        let full = decideWithTrace(observation: obs, profile: profile, rng: &rng)
        return (full.action, full.annotation)
    }

    public struct FullDecision: Sendable {
        public let action: PlayerAction
        public let annotation: DecisionAnnotation
        /// Postflop decisions carry a full inspectable trace (§40).
        public let trace: DecisionTrace?
    }

    public static func decideWithTrace(observation obs: BotObservation, profile: BotProfile, rng: inout SeededRNG) -> FullDecision {
        var config = StrategyConfig.baseline.applying(profile: profile)
        applyAdaptation(&config, obs: obs, profile: profile)

        if obs.street == .preflop {
            let context = PreflopContext.build(from: obs)
            let decision = PreflopStrategy.decide(obs: obs, context: context, config: config, rng: &rng)
            let combo = HoleCombo(obs.holeCards[0], obs.holeCards[1])
            let annotation = DecisionAnnotation(
                strengthEstimate: 1 - HandOrdering.percentile(of: combo),
                advisorKind: nil,
                note: decision.note
            )
            return FullDecision(action: decision.action, annotation: annotation, trace: nil)
        }

        let equitySeed = rng.nextUInt64()
        let context = PostflopContext.build(
            obs: obs,
            config: config,
            iterations: profile.difficulty.equityIterations,
            seed: equitySeed
        )
        let outcome = PostflopDecision.choose(context: context, profile: profile, config: config, rng: &rng, seed: equitySeed)
        let annotation = DecisionAnnotation(
            strengthEstimate: context.equity.share,
            advisorKind: nil,
            note: "\(context.madeHand.handClass.name), eq \(Int((context.equity.share * 100).rounded()))% vs \(context.obs.activeOpponentCount)"
        )
        return FullDecision(action: outcome.action, annotation: annotation, trace: outcome.trace)
    }

    /// Bounded exploitative adjustments for Advanced/Elite bots with enough
    /// evidence (§30). Never instantaneous, never unbounded.
    private static func applyAdaptation(_ config: inout StrategyConfig, obs: BotObservation, profile: BotProfile) {
        guard profile.difficulty == .advanced || profile.difficulty == .elite else { return }
        let live = obs.opponents.filter { !$0.hasFolded }.map { $0.seatIndex }
        let observed = live.compactMap { obs.observedTendencies[$0] }.filter { $0.sufficientForAdaptation }
        guard !observed.isEmpty else { return }

        let averageVPIP = observed.map { $0.vpipPercent }.reduce(0, +) / Double(observed.count)
        let cbetSamples = observed.filter { $0.cbetOpportunities >= 12 }
        if !cbetSamples.isEmpty {
            let averageFoldToCBet = cbetSamples.map { $0.foldToCBetPercent }.reduce(0, +) / Double(cbetSamples.count)
            // Opponents who fold to continuation bets get barrelled more;
            // opponents who never fold get bluffed less and valued thinner.
            if averageFoldToCBet > 55 {
                config.cbetFrequency = min(0.95, config.cbetFrequency * 1.2)
                config.bluffScale = min(2.2, config.bluffScale * 1.15)
            } else if averageFoldToCBet < 30 {
                config.bluffScale = max(0.25, config.bluffScale * 0.8)
                config.valueThresholdShift = max(-0.08, config.valueThresholdShift - 0.03)
            }
        }
        // Wide openers get three-bet more (§30).
        if averageVPIP > 38 {
            for key in config.threeBetPercent.keys {
                config.threeBetPercent[key] = min(0.25, config.threeBetPercent[key]! * 1.25)
            }
        }
    }
}

/// Session-facing entry point: derives the per-decision RNG stream from the
/// hand seed so every decision is reproducible (§43).
public enum BotDecider {

    public static func decide(hand: PokerHand, seat: Int, profile: BotProfile) -> (action: PlayerAction, annotation: DecisionAnnotation)? {
        guard let full = decideWithTrace(hand: hand, seat: seat, profile: profile, tendencies: [:]) else { return nil }
        return (full.action, full.annotation)
    }

    /// Full decision with trace and optional observed tendencies.
    public static func decideWithTrace(
        hand: PokerHand,
        seat: Int,
        profile: BotProfile,
        tendencies: [Int: SeatTendencies],
        tournament: TournamentContext? = nil
    ) -> BotBrain.FullDecision? {
        guard let baseObs = hand.observation(for: seat) else { return nil }
        var obs = tendencies.isEmpty ? baseObs : baseObs.with(tendencies: tendencies)
        if let tournament {
            obs = obs.with(tournament: tournament)
        }
        let stream = UInt64(hand.decisions.count) &* 64 &+ UInt64(seat) &+ 7
        var rng = SeededRNG.derive(seed: hand.config.seed, stream: stream)
        return BotBrain.decideWithTrace(observation: obs, profile: profile, rng: &rng)
    }
}
