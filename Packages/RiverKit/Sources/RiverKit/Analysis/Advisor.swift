import Foundation

/// Basic rule-based recommendations for the human player (Phase 1 advisor).
///
/// Uses the same honest information a player has: own cards, board, pot and
/// price. Explanations always show the reasoning, not just the verdict. The
/// data model is deliberately simple so a stronger analysis engine can replace
/// it later without changing stored hand histories.
public struct Advice: Equatable, Sendable {
    public let kind: ActionKind
    /// Suggested "to" amount for bet/raise recommendations.
    public let toAmount: Int?
    public let equity: Double
    public let potOdds: Double
    public let explanation: String
}

public enum Advisor {

    /// Computes a recommendation for the acting seat. Deterministic for a
    /// given hand seed. Runs a few hundred Monte Carlo samples; call it off
    /// the main thread.
    public static func advise(hand: PokerHand, seat: Int) -> Advice? {
        guard let obs = hand.observation(for: seat) else { return nil }
        var rng = SeededRNG.derive(seed: hand.config.seed, stream: 0xADD1CE &+ UInt64(hand.decisions.count))
        return advise(observation: obs, rng: &rng)
    }

    public static func advise(observation obs: BotObservation, rng: inout SeededRNG) -> Advice {
        let opponents = max(1, obs.activeOpponentCount)
        let equity: Double
        if obs.street == .preflop {
            equity = EquityEstimator.equityVsRandom(hole: obs.holeCards, board: [], opponents: opponents, iterations: 250, rng: &rng).equity
        } else {
            equity = EquityEstimator.equityVsRandom(hole: obs.holeCards, board: obs.board, opponents: opponents, iterations: 300, rng: &rng).equity
        }
        let toCall = obs.available.callCost
        let potOdds = toCall > 0 ? Double(toCall) / Double(obs.pot + toCall) : 0
        let equityPct = Int((equity * 100).rounded())
        let oddsPct = Int((potOdds * 100).rounded())

        if obs.available.canCheck {
            if let options = obs.available.betRaise, equity >= 0.55 + 0.04 * Double(opponents - 1) {
                let target = obs.myCommittedThisStreet + max(obs.bigBlind, Int((Double(obs.pot) * 0.6).rounded()))
                let clamped = max(options.minTo, min(target, options.maxTo))
                return Advice(
                    kind: options.kind,
                    toAmount: clamped,
                    equity: equity,
                    potOdds: 0,
                    explanation: "Your hand wins about \(equityPct)% of the time against \(opponents) random hand\(opponents == 1 ? "" : "s"). That is strong enough to bet for value — around 60% of the pot is a solid size."
                )
            }
            return Advice(
                kind: .check,
                toAmount: nil,
                equity: equity,
                potOdds: 0,
                explanation: "Checking is free. Your hand wins about \(equityPct)% of the time against \(opponents) unknown hand\(opponents == 1 ? "" : "s"), which is not strong enough to build the pot right now."
            )
        }

        // Facing a bet.
        let priceLine = "You must pay \(toCall) into a pot that will be \(obs.pot + toCall), so you need about \(oddsPct)% equity to break even."
        if equity >= 0.72 && obs.available.betRaise != nil {
            let options = obs.available.betRaise!
            let target = max(options.minTo, min(Int(Double(obs.currentBet) * 2.7), options.maxTo))
            return Advice(
                kind: .raise,
                toAmount: target,
                equity: equity,
                potOdds: potOdds,
                explanation: "\(priceLine) Your estimated equity is about \(equityPct)% — a clear favorite. Raising builds the pot while ahead."
            )
        }
        if equity >= potOdds + 0.03 {
            return Advice(
                kind: .call,
                toAmount: nil,
                equity: equity,
                potOdds: potOdds,
                explanation: "\(priceLine) Your estimated equity is about \(equityPct)%, comfortably above the price, so calling is profitable."
            )
        }
        if equity >= potOdds - 0.03 {
            return Advice(
                kind: .call,
                toAmount: nil,
                equity: equity,
                potOdds: potOdds,
                explanation: "\(priceLine) Your estimated equity is about \(equityPct)% — right at the break-even price. This is a close decision; either call or fold is reasonable."
            )
        }
        return Advice(
            kind: .fold,
            toAmount: nil,
            equity: equity,
            potOdds: potOdds,
            explanation: "\(priceLine) Your estimated equity is only about \(equityPct)%, below the price you are being asked to pay. Folding saves chips."
        )
    }
}
