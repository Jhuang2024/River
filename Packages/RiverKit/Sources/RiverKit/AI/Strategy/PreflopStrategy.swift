import Foundation

/// The preflop situation, reconstructed from legally visible history (§6).
public struct PreflopContext: Equatable, Sendable {
    public let position: TablePosition
    public let playerCount: Int
    /// Number of raises so far this street (0 = unopened/limped pot).
    public let raiseCount: Int
    /// Voluntary callers before any raise (limpers).
    public let limpers: Int
    /// Callers since the last raise.
    public let callersSinceRaise: Int
    /// Seat of the last raiser, if any.
    public let lastRaiserSeat: Int?
    /// Whether the last aggressor is all-in.
    public let facingAllIn: Bool
    /// Whether the acting player is in position on the last raiser.
    public let inPositionVsRaiser: Bool
    public let effectiveStackBB: Double
    public let potBB: Double

    /// Builds the context for the acting seat from an observation.
    public static func build(from obs: BotObservation) -> PreflopContext {
        let participants = obs.opponents.count + 1
        let seatCount = max(obs.opponents.map { $0.seatIndex }.max() ?? 0, obs.seat, obs.buttonIndex) + 1
        func offset(_ seat: Int) -> Int {
            return ((seat - obs.buttonIndex) % seatCount + seatCount) % seatCount
        }
        let position = TablePosition.position(offsetFromButton: offset(obs.seat), playerCount: min(6, max(2, participants)))

        var raises = 0
        var limpers = 0
        var callersSinceRaise = 0
        var lastRaiser: Int? = nil
        var lastRaiserAllIn = false
        for event in obs.visibleEvents {
            if case .action(let seat, let street, let kind, _, _, let isAllIn) = event, street == .preflop {
                switch kind {
                case .raise, .bet:
                    raises += 1
                    lastRaiser = seat
                    lastRaiserAllIn = isAllIn
                    callersSinceRaise = 0
                case .call:
                    if raises == 0 { limpers += 1 } else { callersSinceRaise += 1 }
                default:
                    break
                }
            }
        }

        // Effective stack: my total vs the biggest live opponent total.
        let myTotal = obs.myStack + obs.myCommittedThisStreet
        let biggestOpponent = obs.opponents
            .filter { !$0.hasFolded }
            .map { $0.stack + $0.committedThisStreet }
            .max() ?? 0
        let bb = Double(max(1, obs.bigBlind))
        let effective = Double(min(myTotal, biggestOpponent)) / bb

        var inPosition = false
        if let raiser = lastRaiser {
            // Larger offset from the button = earlier position; smaller offset
            // acts later postflop (button offset 0 is best).
            inPosition = offset(obs.seat) < offset(raiser)
        }

        return PreflopContext(
            position: position,
            playerCount: participants,
            raiseCount: raises,
            limpers: limpers,
            callersSinceRaise: callersSinceRaise,
            lastRaiserSeat: lastRaiser,
            facingAllIn: lastRaiserAllIn,
            inPositionVsRaiser: inPosition,
            effectiveStackBB: effective,
            potBB: Double(obs.pot) / bb
        )
    }
}

/// Position- and stack-aware preflop decisions from configured ranges (§6–8).
public enum PreflopStrategy {

    public struct Decision: Sendable {
        public let action: PlayerAction
        public let note: String
    }

    /// Chooses a preflop action for the observation using an
    /// archetype-adjusted configuration. Deterministic per RNG stream.
    public static func decide(
        obs: BotObservation,
        context: PreflopContext,
        config: StrategyConfig,
        rng: inout SeededRNG
    ) -> Decision {
        let combo = HoleCombo(obs.holeCards[0], obs.holeCards[1])
        let percentile = HandOrdering.percentile(of: combo)
        let label = combo.label
        let bb = max(1, obs.bigBlind)
        let available = obs.available

        func note(_ text: String) -> String {
            return "\(label) p\(Int(percentile * 100)) \(text)"
        }

        /// Mixed-strategy membership around a range edge (§8).
        func inRange(_ threshold: Double) -> Bool {
            let band = config.mixingBand
            if band <= 0 { return percentile <= threshold }
            if percentile <= threshold - band { return true }
            if percentile >= threshold + band { return false }
            let probability = (threshold + band - percentile) / (2 * band)
            return rng.double01() < probability
        }

        func fold() -> Decision {
            if available.canCheck {
                return Decision(action: .check, note: note("check (free)"))
            }
            return Decision(action: .fold, note: note("fold"))
        }

        func call() -> Decision {
            guard available.canCall else { return fold() }
            return Decision(action: .call, note: note("call"))
        }

        func raise(to target: Int, _ tag: String) -> Decision {
            guard let options = available.betRaise else { return call() }
            var amount = max(options.minTo, min(target, options.maxTo))
            if !options.isLegal(toAmount: amount) {
                amount = amount < options.minFullTo ? options.minTo : options.maxTo
            }
            return Decision(action: PlayerAction(kind: options.kind, toAmount: amount), note: note(tag))
        }

        func shove(_ tag: String) -> Decision {
            guard let options = available.betRaise else { return call() }
            return Decision(action: PlayerAction(kind: options.kind, toAmount: options.maxTo), note: note(tag))
        }

        // ---- Facing an all-in: pure price-aware calling decision (§6).
        if context.facingAllIn && available.callCost > 0 {
            let odds = PotMath.odds(amountToCall: available.callCost, potBeforeCall: obs.pot)
            // Better price widens the calling range; multiway all-ins tighten.
            var threshold = config.callShovePercent * (0.6 + (1 - odds.requiredEquity) * 1.2)
            if context.callersSinceRaise > 0 { threshold *= 0.7 }
            if context.raiseCount >= 2 { threshold *= 0.8 }
            return inRange(threshold) ? call() : fold()
        }

        // ---- Push/fold at short effective stacks (§26).
        if context.effectiveStackBB <= config.pushFoldThresholdBB {
            if context.raiseCount == 0 {
                let shoveThreshold = config.shovePercent[context.position] ?? 0.2
                if inRange(shoveThreshold) {
                    return shove("shove \(Int(context.effectiveStackBB))bb")
                }
                return fold()
            }
            let odds = PotMath.odds(amountToCall: available.callCost, potBeforeCall: obs.pot)
            let threshold = config.callShovePercent * (0.6 + (1 - odds.requiredEquity) * 1.2)
            if inRange(threshold * 0.8) {
                return shove("reshove")
            }
            if inRange(threshold) {
                return call()
            }
            return fold()
        }

        switch context.raiseCount {
        case 0:
            // ---- Unopened or limped pot.
            let openThreshold = config.openPercent[context.position] ?? 0.2
            if context.limpers > 0 {
                // Isolate limpers slightly tighter than a normal open.
                if inRange(openThreshold * 0.85) {
                    let size = (config.openSizeBB + Double(context.limpers) * config.openSizePerLimperBB) * Double(bb)
                    return raise(to: Int(size.rounded()), "isolate \(context.limpers) limper(s)")
                }
                // Limp behind with speculative hands when the style limps.
                if config.limpPercent > 0 && percentile < 0.5 && rng.double01() < config.limpPercent {
                    return call()
                }
                return fold()
            }
            if inRange(openThreshold) {
                // Passive styles sometimes limp instead of opening (§6 leak).
                if config.limpPercent > 0 && percentile > openThreshold * 0.35 && rng.double01() < config.limpPercent {
                    return available.canCheck ? Decision(action: .check, note: note("check option")) : call()
                }
                if available.canCheck && context.position == .bigBlind {
                    // BB option: raise strong hands, otherwise check.
                    if percentile <= openThreshold * 0.5 {
                        return raise(to: Int(config.openSizeBB * Double(bb)), "raise option")
                    }
                    return Decision(action: .check, note: note("check option"))
                }
                return raise(to: Int((config.openSizeBB * Double(bb)).rounded()), "open")
            }
            if config.limpPercent > 0 && percentile < 0.55 && rng.double01() < config.limpPercent && !available.canCheck {
                return call() // loose-passive limp leak
            }
            return fold()

        case 1:
            // ---- Facing a single open (possibly with callers = squeeze spot).
            let isSqueeze = context.callersSinceRaise > 0
            var threeBetThreshold: Double
            if isSqueeze {
                threeBetThreshold = config.squeezePercent
            } else if context.position == .bigBlind {
                threeBetThreshold = config.bbDefendRaisePercent
            } else {
                threeBetThreshold = config.threeBetPercent[context.position] ?? 0.05
            }
            if inRange(threeBetThreshold) {
                return raise(to: threeBetTarget(obs: obs, context: context, config: config, bb: bb), isSqueeze ? "squeeze" : "3-bet")
            }
            // Blocker-driven light three-bets for mixing styles (§23): suited
            // aces below premium strength.
            if config.mixingBand > 0 && combo.isSuited
                && combo.first.rank == .ace && combo.second.rank.rawValue <= 5
                && rng.double01() < config.bluffScale * 0.18 {
                return raise(to: threeBetTarget(obs: obs, context: context, config: config, bb: bb), "3-bet bluff (blocker)")
            }
            // Calling range depends on seat; big opens tighten it.
            var callThreshold: Double
            switch context.position {
            case .bigBlind: callThreshold = config.bbDefendCallPercent
            case .smallBlind: callThreshold = config.sbDefendCallPercent
            default: callThreshold = config.callVsOpenPercent[context.position] ?? 0.1
            }
            let openSizeBB = Double(obs.currentBet) / Double(bb)
            if openSizeBB > 3 {
                callThreshold *= max(0.5, 3.0 / openSizeBB)
            }
            if isSqueeze {
                callThreshold *= 1.15 // better multiway price
            }
            if inRange(callThreshold + threeBetThreshold) {
                return call()
            }
            return fold()

        case 2:
            // ---- Facing a three-bet.
            if inRange(config.fourBetPercent) {
                // Short-ish stacks convert four-bets into shoves.
                let target = Int(Double(obs.currentBet) * config.fourBetFactor)
                let myTotal = obs.myStack + obs.myCommittedThisStreet
                if Double(target) > 0.42 * Double(myTotal) {
                    return shove("4-bet shove")
                }
                return raise(to: target, "4-bet")
            }
            var callThreshold = config.callThreeBetPercent
            if context.inPositionVsRaiser { callThreshold *= 1.25 }
            if inRange(callThreshold + config.fourBetPercent) {
                return call()
            }
            return fold()

        default:
            // ---- Facing a four-bet or more.
            if inRange(config.fiveBetAllInPercent) {
                return shove("5-bet all-in")
            }
            if inRange(config.fiveBetAllInPercent + config.callFourBetPercent) {
                return call()
            }
            return fold()
        }
    }

    /// Contextual three-bet/squeeze sizing (§7): in position smaller, out of
    /// position larger, plus extra per caller.
    private static func threeBetTarget(obs: BotObservation, context: PreflopContext, config: StrategyConfig, bb: Int) -> Int {
        let factor = context.inPositionVsRaiser ? config.threeBetFactorInPosition : config.threeBetFactorOutOfPosition
        var target = Double(obs.currentBet) * factor
        target += Double(context.callersSinceRaise) * config.squeezeExtraPerCallerBB * Double(bb)
        return Int(target.rounded())
    }
}
