import Foundation

/// Basic strategy (§6), derived from the SAME rule configuration the table
/// uses. Charts are versioned data, not formulas scattered through code, and
/// they adapt to S17/H17, DAS and surrender availability — one universal
/// chart is never applied to incompatible rules.
public enum BlackjackStrategy {

    public static let chartVersion = 1

    /// What the strategy would do, with a fallback for when the preferred
    /// action is not currently legal (e.g. double with three cards).
    public struct Recommendation: Hashable, Sendable {
        public let action: BlackjackAction
        public let explanation: String
    }

    /// Dealer upcard index 2...11 (11 = ace).
    private static func upValue(_ card: BlackjackCard) -> Int {
        return card.pointValue == 1 ? 11 : card.pointValue
    }

    /// The recommendation for a hand versus the dealer upcard, restricted to
    /// the actions that are legal right now.
    public static func recommend(
        hand: BlackjackHand,
        dealerUpcard: BlackjackCard,
        rules: BlackjackRules,
        legalActions: [BlackjackAction]
    ) -> Recommendation {
        let up = upValue(dealerUpcard)
        let (total, isSoft) = BlackjackTotal.evaluate(hand.cards)
        let isPair = hand.cards.count == 2 && hand.cards[0].pointValue == hand.cards[1].pointValue
        let canDouble = legalActions.contains(.double)
        let canSplit = legalActions.contains(.split)
        let canSurrender = legalActions.contains(.surrender)

        // 1. Surrender comes first where the chart says so.
        if canSurrender, shouldSurrender(total: total, isSoft: isSoft, isPair: isPair, up: up, rules: rules) {
            return Recommendation(action: .surrender,
                                  explanation: "This total loses too often against \(upName(up)) — giving up half the bet saves chips long-term.")
        }

        // 2. Pairs.
        if isPair && canSplit, let split = pairDecision(pairValue: hand.cards[0].pointValue, up: up, rules: rules) {
            if split {
                return Recommendation(action: .split,
                                      explanation: pairExplanation(pairValue: hand.cards[0].pointValue, up: up))
            }
            // A "never split" pair falls through to the total-based line.
        }

        // 3. Soft totals.
        if isSoft {
            return softDecision(total: total, up: up, rules: rules, canDouble: canDouble)
        }

        // 4. Hard totals.
        return hardDecision(total: total, up: up, rules: rules, canDouble: canDouble)
    }

    private static func upName(_ up: Int) -> String {
        return up == 11 ? "an ace" : "a \(up)"
    }

    // MARK: - Surrender chart (late surrender, §6)

    private static func shouldSurrender(total: Int, isSoft: Bool, isPair: Bool, up: Int, rules: BlackjackRules) -> Bool {
        guard rules.surrenderAllowed, !isSoft else { return false }
        // 8,8 is split, not surrendered (except 8,8 vs A under H17).
        if isPair && total == 16 {
            return rules.dealerHitsSoft17 && up == 11
        }
        if total == 16 && (up == 9 || up == 10 || up == 11) { return true }
        if total == 15 && up == 10 { return true }
        if rules.dealerHitsSoft17 {
            if total == 15 && up == 11 { return true }
            if total == 17 && up == 11 { return true }
        }
        return false
    }

    // MARK: - Pair chart (§6). Returns nil when the pair line does not apply
    // (5,5 and 10,10 route to the total charts).

    private static func pairDecision(pairValue: Int, up: Int, rules: BlackjackRules) -> Bool? {
        let das = rules.doubleAfterSplitAllowed
        switch pairValue {
        case 1: return true                              // always split aces
        case 10: return false                            // never split tens
        case 9: return (2...9).contains(up) && up != 7   // stand vs 7, 10, A
        case 8: return true                              // always split eights
        case 7: return (2...7).contains(up)
        case 6: return das ? (2...6).contains(up) : (3...6).contains(up)
        case 5: return nil                               // play as hard 10
        case 4: return das && (up == 5 || up == 6)
        case 2, 3: return das ? (2...7).contains(up) : (4...7).contains(up)
        default: return nil
        }
    }

    private static func pairExplanation(pairValue: Int, up: Int) -> String {
        switch pairValue {
        case 1: return "Two aces are two chances at 21; one hand of 12 is nearly worthless."
        case 8: return "Sixteen is the worst total — two eights are far stronger apart."
        default: return "Splitting turns a mediocre total into two playable hands against \(upName(up))."
        }
    }

    // MARK: - Soft totals (§6)

    private static func softDecision(total: Int, up: Int, rules: BlackjackRules, canDouble: Bool) -> Recommendation {
        let h17 = rules.dealerHitsSoft17
        switch total {
        case ...12:
            // Soft 12 (a pair of aces that could not be split): just draw.
            return Recommendation(action: .hit,
                                  explanation: "A soft 12 can't bust with one card and is too weak to stand.")
        case 13...17:
            let doubleRange: ClosedRange<Int>
            switch total {
            case 13, 14: doubleRange = 5...6
            case 15, 16: doubleRange = 4...6
            default: doubleRange = 3...6   // soft 17
            }
            if canDouble && doubleRange.contains(up) {
                return Recommendation(action: .double,
                                      explanation: "The ace makes this bust-proof and \(upName(up)) busts often — get more chips in.")
            }
            return Recommendation(action: .hit,
                                  explanation: "A soft \(total) can't bust with one card and is too weak to stand.")
        case 18:
            let doubleVs: ClosedRange<Int> = h17 ? 2...6 : 3...6
            if canDouble && doubleVs.contains(up) {
                return Recommendation(action: .double,
                                      explanation: "Soft 18 against a weak upcard is a favourite — doubling maximises it.")
            }
            if up >= 9 {
                return Recommendation(action: .hit,
                                      explanation: "Eighteen loses to the strong totals \(upName(up)) makes; drawing risk-free beats standing.")
            }
            return Recommendation(action: .stand,
                                  explanation: "Soft 18 is good enough against \(upName(up)).")
        case 19:
            if h17 && up == 6 && canDouble {
                return Recommendation(action: .double,
                                      explanation: "Against a 6 with the dealer hitting soft 17, soft 19 earns more doubled.")
            }
            return Recommendation(action: .stand, explanation: "Nineteen wins as it stands.")
        default:
            return Recommendation(action: .stand, explanation: "Stand on 20 and 21 — always.")
        }
    }

    // MARK: - Hard totals (§6)

    private static func hardDecision(total: Int, up: Int, rules: BlackjackRules, canDouble: Bool) -> Recommendation {
        switch total {
        case ...8:
            return Recommendation(action: .hit, explanation: "Totals of 8 or less can never bust — always draw.")
        case 9:
            if canDouble && (3...6).contains(up) {
                return Recommendation(action: .double,
                                      explanation: "Nine against a weak upcard: the dealer busts often, so put in more.")
            }
            return Recommendation(action: .hit, explanation: "Nine wants one more card.")
        case 10:
            if canDouble && (2...9).contains(up) {
                return Recommendation(action: .double,
                                      explanation: "Ten beats the dealer's likely total — double while ahead.")
            }
            return Recommendation(action: .hit, explanation: "Draw toward 20; the dealer's upcard is too strong to double.")
        case 11:
            let doubleVsAce = rules.dealerHitsSoft17
            if canDouble && (up <= 10 || doubleVsAce) {
                return Recommendation(action: .double,
                                      explanation: "Eleven is the best doubling total — one card often makes 21.")
            }
            return Recommendation(action: .hit, explanation: "Eleven always takes a card.")
        case 12:
            if (4...6).contains(up) {
                return Recommendation(action: .stand,
                                      explanation: "Only four ten-value ranks bust you, and \(upName(up)) busts often — let the dealer take the risk.")
            }
            return Recommendation(action: .hit, explanation: "Twelve is too weak to stand against \(upName(up)).")
        case 13...16:
            if (2...6).contains(up) {
                return Recommendation(action: .stand,
                                      explanation: "Stiff totals stand against weak upcards: make the dealer draw and bust.")
            }
            return Recommendation(action: .hit,
                                  explanation: "Against \(upName(up)) the dealer usually makes 17+; standing on \(total) loses more.")
        default:
            return Recommendation(action: .stand, explanation: "Seventeen and up stands — the bust risk outweighs any gain.")
        }
    }

    // MARK: - Decision grading (§6 statistics)

    /// Whether a taken action matched basic strategy at that moment.
    public static func evaluate(
        taken: BlackjackAction,
        hand: BlackjackHand,
        dealerUpcard: BlackjackCard,
        rules: BlackjackRules,
        legalActions: [BlackjackAction]
    ) -> (correct: Bool, recommended: BlackjackAction) {
        let recommendation = recommend(hand: hand, dealerUpcard: dealerUpcard, rules: rules, legalActions: legalActions)
        return (taken == recommendation.action, recommendation.action)
    }
}
