import Foundation

/// Versioned, centralized strategy numbers (§3). All range values are
/// fractions of the 1,326 combinations (0...1), taken from the equity-ordered
/// hand list. Nothing strategy-related is hardcoded inside decision code.
public struct StrategyConfig: Sendable, Equatable {
    public static let version = 1

    // MARK: Preflop range sizes by position (fraction of all hands)

    public var openPercent: [TablePosition: Double]
    /// Cold-calling an open (in position; blinds have their own numbers).
    public var callVsOpenPercent: [TablePosition: Double]
    public var threeBetPercent: [TablePosition: Double]
    public var bbDefendCallPercent: Double
    public var bbDefendRaisePercent: Double
    public var sbDefendCallPercent: Double
    /// Facing a three-bet.
    public var fourBetPercent: Double
    public var callThreeBetPercent: Double
    /// Facing a four-bet.
    public var fiveBetAllInPercent: Double
    public var callFourBetPercent: Double
    /// Squeeze (3-bet over an open plus callers).
    public var squeezePercent: Double
    /// Short-stack (≤ pushFoldThresholdBB) shove range by position.
    public var shovePercent: [TablePosition: Double]
    public var callShovePercent: Double
    public var pushFoldThresholdBB: Double
    /// Voluntary limp-behind range (mostly for passive/beginner styles).
    public var limpPercent: Double

    // MARK: Preflop sizing (§7)

    public var openSizeBB: Double
    public var openSizePerLimperBB: Double
    public var threeBetFactorInPosition: Double
    public var threeBetFactorOutOfPosition: Double
    public var fourBetFactor: Double
    public var squeezeExtraPerCallerBB: Double

    // MARK: Postflop frequencies

    public var cbetFrequency: Double
    public var barrelFrequency: Double
    public var checkRaiseFrequency: Double
    public var riverBluffFrequency: Double
    /// Scales every bluffing score.
    public var bluffScale: Double
    /// Shifts value thresholds: negative bets thinner, positive tighter.
    public var valueThresholdShift: Double
    /// Scales calling scores (stickiness).
    public var callScale: Double
    /// Mixed-strategy band half-width in percentile around range edges.
    public var mixingBand: Double

    public init(
        openPercent: [TablePosition: Double],
        callVsOpenPercent: [TablePosition: Double],
        threeBetPercent: [TablePosition: Double],
        bbDefendCallPercent: Double,
        bbDefendRaisePercent: Double,
        sbDefendCallPercent: Double,
        fourBetPercent: Double,
        callThreeBetPercent: Double,
        fiveBetAllInPercent: Double,
        callFourBetPercent: Double,
        squeezePercent: Double,
        shovePercent: [TablePosition: Double],
        callShovePercent: Double,
        pushFoldThresholdBB: Double,
        limpPercent: Double,
        openSizeBB: Double,
        openSizePerLimperBB: Double,
        threeBetFactorInPosition: Double,
        threeBetFactorOutOfPosition: Double,
        fourBetFactor: Double,
        squeezeExtraPerCallerBB: Double,
        cbetFrequency: Double,
        barrelFrequency: Double,
        checkRaiseFrequency: Double,
        riverBluffFrequency: Double,
        bluffScale: Double,
        valueThresholdShift: Double,
        callScale: Double,
        mixingBand: Double
    ) {
        self.openPercent = openPercent
        self.callVsOpenPercent = callVsOpenPercent
        self.threeBetPercent = threeBetPercent
        self.bbDefendCallPercent = bbDefendCallPercent
        self.bbDefendRaisePercent = bbDefendRaisePercent
        self.sbDefendCallPercent = sbDefendCallPercent
        self.fourBetPercent = fourBetPercent
        self.callThreeBetPercent = callThreeBetPercent
        self.fiveBetAllInPercent = fiveBetAllInPercent
        self.callFourBetPercent = callFourBetPercent
        self.squeezePercent = squeezePercent
        self.shovePercent = shovePercent
        self.callShovePercent = callShovePercent
        self.pushFoldThresholdBB = pushFoldThresholdBB
        self.limpPercent = limpPercent
        self.openSizeBB = openSizeBB
        self.openSizePerLimperBB = openSizePerLimperBB
        self.threeBetFactorInPosition = threeBetFactorInPosition
        self.threeBetFactorOutOfPosition = threeBetFactorOutOfPosition
        self.fourBetFactor = fourBetFactor
        self.squeezeExtraPerCallerBB = squeezeExtraPerCallerBB
        self.cbetFrequency = cbetFrequency
        self.barrelFrequency = barrelFrequency
        self.checkRaiseFrequency = checkRaiseFrequency
        self.riverBluffFrequency = riverBluffFrequency
        self.bluffScale = bluffScale
        self.valueThresholdShift = valueThresholdShift
        self.callScale = callScale
        self.mixingBand = mixingBand
    }

    /// A disciplined six-max baseline. Archetype and difficulty modifiers are
    /// applied on top (§9, §10); this itself is roughly a "solid regular".
    public static let baseline = StrategyConfig(
        openPercent: [
            .underTheGun: 0.15, .hijack: 0.19, .cutoff: 0.26,
            .button: 0.42, .smallBlind: 0.34, .bigBlind: 0.15
        ],
        callVsOpenPercent: [
            .underTheGun: 0.07, .hijack: 0.09, .cutoff: 0.11,
            .button: 0.14, .smallBlind: 0.09, .bigBlind: 0.30
        ],
        threeBetPercent: [
            .underTheGun: 0.035, .hijack: 0.045, .cutoff: 0.055,
            .button: 0.07, .smallBlind: 0.06, .bigBlind: 0.08
        ],
        bbDefendCallPercent: 0.32,
        bbDefendRaisePercent: 0.08,
        sbDefendCallPercent: 0.12,
        fourBetPercent: 0.022,
        callThreeBetPercent: 0.075,
        fiveBetAllInPercent: 0.013,
        callFourBetPercent: 0.035,
        squeezePercent: 0.05,
        shovePercent: [
            .underTheGun: 0.13, .hijack: 0.17, .cutoff: 0.22,
            .button: 0.32, .smallBlind: 0.42, .bigBlind: 0.20
        ],
        callShovePercent: 0.14,
        pushFoldThresholdBB: 12,
        limpPercent: 0.0,
        openSizeBB: 2.3,
        openSizePerLimperBB: 1.0,
        threeBetFactorInPosition: 3.0,
        threeBetFactorOutOfPosition: 3.9,
        fourBetFactor: 2.3,
        squeezeExtraPerCallerBB: 1.5,
        cbetFrequency: 0.62,
        barrelFrequency: 0.45,
        checkRaiseFrequency: 0.09,
        riverBluffFrequency: 0.22,
        bluffScale: 1.0,
        valueThresholdShift: 0,
        callScale: 1.0,
        mixingBand: 0.03
    )

    // MARK: - Archetype and difficulty modifiers (§9, §10)

    /// Applies bounded personality modifications to the baseline. Personality
    /// shifts frequencies; it never invents illegal or absurd strategy.
    public func applying(profile: BotProfile) -> StrategyConfig {
        var config = self

        func clamp(_ value: Double, _ lo: Double, _ hi: Double) -> Double {
            return min(hi, max(lo, value))
        }

        // Personality scales derived from the profile's core parameters.
        let rangeScale = clamp(0.45 + profile.looseness * 1.7, 0.45, 2.1)
        let raiseScale = clamp(0.45 + profile.aggression * 1.1, 0.4, 2.4)
        let callWiden = clamp(0.6 + profile.callStickiness * 1.1, 0.6, 1.9)

        func scaleRanges(_ table: [TablePosition: Double], by factor: Double, cap: Double) -> [TablePosition: Double] {
            var result = table
            for key in result.keys {
                result[key] = clamp(result[key]! * factor, 0.01, cap)
            }
            return result
        }

        config.openPercent = scaleRanges(openPercent, by: rangeScale, cap: 0.75)
        config.callVsOpenPercent = scaleRanges(callVsOpenPercent, by: rangeScale * callWiden, cap: 0.6)
        config.threeBetPercent = scaleRanges(threeBetPercent, by: raiseScale, cap: 0.25)
        config.shovePercent = scaleRanges(shovePercent, by: clamp(rangeScale, 0.6, 1.5), cap: 0.7)
        config.bbDefendCallPercent = clamp(bbDefendCallPercent * callWiden, 0.12, 0.65)
        config.bbDefendRaisePercent = clamp(bbDefendRaisePercent * raiseScale, 0.02, 0.25)
        config.sbDefendCallPercent = clamp(sbDefendCallPercent * callWiden, 0.04, 0.4)
        config.fourBetPercent = clamp(fourBetPercent * raiseScale, 0.008, 0.08)
        config.callThreeBetPercent = clamp(callThreeBetPercent * callWiden, 0.03, 0.25)
        config.callFourBetPercent = clamp(callFourBetPercent * callWiden, 0.015, 0.12)
        config.callShovePercent = clamp(callShovePercent * callWiden, 0.06, 0.35)
        config.squeezePercent = clamp(squeezePercent * raiseScale, 0.015, 0.15)

        // Passive, sticky players limp; aggressive ones essentially never do.
        if profile.aggression < 0.3 {
            config.limpPercent = clamp(profile.looseness * 0.6, 0, 0.45)
        }

        config.cbetFrequency = clamp(cbetFrequency * (0.55 + profile.aggression * 0.85), 0.2, 0.95)
        config.barrelFrequency = clamp(barrelFrequency * (0.45 + profile.aggression), 0.1, 0.9)
        config.checkRaiseFrequency = clamp(checkRaiseFrequency * (0.5 + profile.aggression), 0.02, 0.3)
        config.riverBluffFrequency = clamp(riverBluffFrequency * (0.3 + profile.bluffFrequency * 2.0), 0.02, 0.6)
        config.bluffScale = clamp(0.4 + profile.bluffFrequency * 2.0, 0.25, 2.2)
        config.callScale = clamp(0.65 + profile.callStickiness * 0.9, 0.65, 1.7)
        // Sticky stations value showdown; nits fold: shift value thresholds.
        config.valueThresholdShift = clamp((0.5 - profile.callStickiness) * 0.1, -0.08, 0.08)

        // Difficulty: beginners flatten positional awareness and never mix;
        // stronger bots mix around range edges (§8, §10).
        switch profile.difficulty {
        case .beginner:
            config.openPercent = flattenPositions(config.openPercent, toward: 0.6)
            config.callVsOpenPercent = flattenPositions(config.callVsOpenPercent, toward: 0.6)
            config.mixingBand = 0
            config.limpPercent = max(config.limpPercent, 0.18)
        case .intermediate:
            config.mixingBand = 0
        case .advanced:
            config.mixingBand = 0.03
        case .elite:
            config.mixingBand = 0.045
        }
        return config
    }

    /// Blends positional values toward their average (weak positional play).
    private func flattenPositions(_ table: [TablePosition: Double], toward blend: Double) -> [TablePosition: Double] {
        let average = table.values.reduce(0, +) / Double(max(1, table.count))
        var result = table
        for key in result.keys {
            result[key] = result[key]! * (1 - blend) + average * blend
        }
        return result
    }

    // MARK: - Validation (§3)

    /// Returns human-readable problems; empty means valid. Exercised by tests
    /// and debug assertions, never shipped as runtime behaviour.
    public func validate() -> [String] {
        var problems: [String] = []
        func checkFraction(_ value: Double, _ name: String) {
            if !(value >= 0 && value <= 1) {
                problems.append("\(name) out of range: \(value)")
            }
        }
        for (position, value) in openPercent { checkFraction(value, "openPercent[\(position.shortName)]") }
        for (position, value) in callVsOpenPercent { checkFraction(value, "callVsOpen[\(position.shortName)]") }
        for (position, value) in threeBetPercent { checkFraction(value, "threeBet[\(position.shortName)]") }
        for (position, value) in shovePercent { checkFraction(value, "shove[\(position.shortName)]") }
        checkFraction(bbDefendCallPercent, "bbDefendCall")
        checkFraction(bbDefendRaisePercent, "bbDefendRaise")
        checkFraction(sbDefendCallPercent, "sbDefendCall")
        checkFraction(fourBetPercent, "fourBet")
        checkFraction(callThreeBetPercent, "callThreeBet")
        checkFraction(fiveBetAllInPercent, "fiveBetAllIn")
        checkFraction(callFourBetPercent, "callFourBet")
        checkFraction(squeezePercent, "squeeze")
        checkFraction(callShovePercent, "callShove")
        checkFraction(limpPercent, "limp")
        checkFraction(cbetFrequency, "cbet")
        checkFraction(barrelFrequency, "barrel")
        checkFraction(checkRaiseFrequency, "checkRaise")
        checkFraction(riverBluffFrequency, "riverBluff")
        if openSizeBB < 2 || openSizeBB > 5 { problems.append("openSizeBB unreasonable: \(openSizeBB)") }
        if threeBetFactorInPosition < 2 || threeBetFactorOutOfPosition < threeBetFactorInPosition - 0.5 {
            problems.append("three-bet factors inconsistent")
        }
        if pushFoldThresholdBB < 4 || pushFoldThresholdBB > 25 { problems.append("pushFoldThresholdBB unreasonable") }
        for position in [TablePosition.underTheGun, .hijack, .cutoff, .button, .smallBlind, .bigBlind] {
            if openPercent[position] == nil { problems.append("missing openPercent[\(position.shortName)]") }
            if shovePercent[position] == nil { problems.append("missing shovePercent[\(position.shortName)]") }
        }
        return problems
    }
}
