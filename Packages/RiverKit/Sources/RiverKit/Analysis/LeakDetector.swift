import Foundation

/// One structured leak definition (§28): thresholds, baselines, sample floors,
/// linked lessons. Detection is statistical, never single-hand.
public struct LeakDefinition: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let street: Street?
    public let minSample: Int
    /// Reference band: observed values inside it are fine.
    public let baselineLow: Double
    public let baselineHigh: Double
    /// Related lesson for targeted practice (§15).
    public let lessonID: String
    public let severityWeight: Double
}

/// A detected leak with honest confidence (§29).
public struct LeakReport: Identifiable, Sendable {
    public let definition: LeakDefinition
    public let observed: Double
    public let opportunities: Int
    public let confidence: AnalysisConfidence
    public let severity: Double

    public var id: String { definition.id }

    public var summary: String {
        let direction = observed > definition.baselineHigh ? "above" : "below"
        return "\(definition.title): \(Int(observed.rounded()))% over \(opportunities) opportunities: \(direction) the \(Int(definition.baselineLow.rounded()))-\(Int(definition.baselineHigh.rounded()))% reference band. Confidence: \(confidence.displayName)."
    }
}

/// Aggregated hero behaviour extracted in one pass over histories.
public struct HeroBehaviorStats: Sendable {
    public var hands = 0
    public var vpipCount = 0
    public var raiseFirstCount = 0
    public var openOpportunities = 0
    public var limpCount = 0
    public var bbDefendOpportunities = 0
    public var bbFolds = 0
    public var cbetOpportunities = 0
    public var cbets = 0
    public var foldToCbetOpportunities = 0
    public var foldToCbets = 0
    public var riverCallDecisions = 0
    public var riverCallMistakes = 0
    public var riverCheckMissedValue = 0
    public var riverValueOpportunities = 0
    public var turnBetDecisions = 0
    public var turnBetMistakes = 0
    public var shoveSpots = 0
    public var passedShoves = 0

    public var vpipPercent: Double { hands > 0 ? Double(vpipCount) / Double(hands) * 100 : 0 }
    public var limpPercent: Double { openOpportunities > 0 ? Double(limpCount) / Double(openOpportunities) * 100 : 0 }
    public var bbFoldPercent: Double { bbDefendOpportunities > 0 ? Double(bbFolds) / Double(bbDefendOpportunities) * 100 : 0 }
    public var cbetPercent: Double { cbetOpportunities > 0 ? Double(cbets) / Double(cbetOpportunities) * 100 : 0 }
    public var foldToCbetPercent: Double { foldToCbetOpportunities > 0 ? Double(foldToCbets) / Double(foldToCbetOpportunities) * 100 : 0 }
    public var riverCallMistakePercent: Double { riverCallDecisions > 0 ? Double(riverCallMistakes) / Double(riverCallDecisions) * 100 : 0 }
    public var missedValuePercent: Double { riverValueOpportunities > 0 ? Double(riverCheckMissedValue) / Double(riverValueOpportunities) * 100 : 0 }
    public var turnBetMistakePercent: Double { turnBetDecisions > 0 ? Double(turnBetMistakes) / Double(turnBetDecisions) * 100 : 0 }
    public var passedShovePercent: Double { shoveSpots > 0 ? Double(passedShoves) / Double(shoveSpots) * 100 : 0 }
}

public enum LeakDetector {

    public static let definitions: [LeakDefinition] = [
        LeakDefinition(id: "vpip.high", title: "Playing too many hands", detail: "Entering far more pots than a disciplined range supports costs money on every later street.", street: .preflop, minSample: 60, baselineLow: 18, baselineHigh: 30, lessonID: "p.opening", severityWeight: 1.0),
        LeakDefinition(id: "vpip.low", title: "Playing too few hands", detail: "Extreme tightness surrenders blinds and value; opponents fold whenever you finally bet.", street: .preflop, minSample: 60, baselineLow: 15, baselineHigh: 32, lessonID: "p.opening", severityWeight: 0.7),
        LeakDefinition(id: "limp", title: "Open limping", detail: "Limping wins nothing immediately and invites the blinds in cheaply. Open raise or fold.", street: .preflop, minSample: 25, baselineLow: 0, baselineHigh: 8, lessonID: "p.opening", severityWeight: 0.9),
        LeakDefinition(id: "bb.overfold", title: "Under-defending the big blind", detail: "With a discounted price, folding most defendable hands leaks a blind at a time.", street: .preflop, minSample: 30, baselineLow: 30, baselineHigh: 55, lessonID: "p.blinddef", severityWeight: 0.9),
        LeakDefinition(id: "cbet.high", title: "Continuation betting too often", detail: "Auto-c-betting every flop torches chips on boards that favour the caller.", street: .flop, minSample: 25, baselineLow: 45, baselineHigh: 75, lessonID: "fl.cbet", severityWeight: 0.7),
        LeakDefinition(id: "fold.cbet", title: "Overfolding to continuation bets", detail: "Folding most flops to a single bet makes you profitable to bet blind against.", street: .flop, minSample: 25, baselineLow: 35, baselineHigh: 60, lessonID: "fl.facingcbet", severityWeight: 0.8),
        LeakDefinition(id: "turn.spew", title: "Hopeless turn barrels", detail: "Second bullets without equity or fold prospects are the classic aggression leak.", street: .turn, minSample: 15, baselineLow: 0, baselineHigh: 25, lessonID: "t.barrels", severityWeight: 1.0),
        LeakDefinition(id: "river.overcall", title: "Calling rivers too loosely", detail: "Paying off value bets with weak bluff catchers is the most expensive leak in poker.", street: .river, minSample: 12, baselineLow: 0, baselineHigh: 25, lessonID: "r.bluffcatch", severityWeight: 1.2),
        LeakDefinition(id: "river.missedvalue", title: "Missing river value", detail: "Checking down clearly-best hands gives away the easiest chips available.", street: .river, minSample: 12, baselineLow: 0, baselineHigh: 25, lessonID: "r.value", severityWeight: 1.0),
        LeakDefinition(id: "pushfold.passive", title: "Passing profitable shoves", detail: "Folding shove-worthy hands short-stacked lets the blinds eat you alive.", street: .preflop, minSample: 8, baselineLow: 0, baselineHigh: 30, lessonID: "tn.pushfold", severityWeight: 1.0)
    ]

    /// One-pass extraction of hero behaviour from histories + analyses.
    public static func stats(histories: [HandHistory]) -> HeroBehaviorStats {
        var stats = HeroBehaviorStats()
        for history in histories {
            let hero = history.heroSeat
            stats.hands += 1
            var voluntary = false
            var raisesBefore = 0
            var heroWasOpener = false
            var heroSawUnopened = false
            var heroLimped = false
            var flopCBetter: Int? = nil
            var preflopAggressor: Int? = nil
            var heroFoldedToOpen = false
            var heroIsBB = false

            // Determine the hero's blind status from the events.
            for event in history.events {
                if case .postedBigBlind(let seat, _) = event, seat == hero { heroIsBB = true }
            }

            for event in history.events {
                guard case .action(let seat, let street, let kind, _, _, _) = event else { continue }
                if street == .preflop {
                    if seat == hero {
                        if raisesBefore == 0 { heroSawUnopened = true }
                        switch kind {
                        case .call:
                            voluntary = true
                            if raisesBefore == 0 { heroLimped = true }
                        case .bet, .raise:
                            voluntary = true
                            if raisesBefore == 0 { heroWasOpener = true }
                        case .fold:
                            if raisesBefore == 1 && heroIsBB { heroFoldedToOpen = true }
                        default: break
                        }
                    }
                    if kind == .bet || kind == .raise {
                        raisesBefore += 1
                        preflopAggressor = seat
                    }
                } else if street == .flop {
                    if kind == .bet && seat == preflopAggressor {
                        flopCBetter = seat
                        if seat == hero { stats.cbets += 1 }
                    }
                    if let cbetter = flopCBetter, seat == hero, cbetter != hero {
                        stats.foldToCbetOpportunities += 1
                        if kind == .fold { stats.foldToCbets += 1 }
                        flopCBetter = nil // count once
                    }
                }
            }
            if voluntary { stats.vpipCount += 1 }
            if heroSawUnopened {
                stats.openOpportunities += 1
                if heroLimped { stats.limpCount += 1 }
                if heroWasOpener { stats.raiseFirstCount += 1 }
            }
            if heroIsBB && raisesBefore >= 1 {
                stats.bbDefendOpportunities += 1
                if heroFoldedToOpen { stats.bbFolds += 1 }
            }
            if preflopAggressor == hero {
                // Hero reached the flop as the aggressor?
                let sawFlop = history.events.contains { if case .dealtBoard(let street, _) = $0 { return street == .flop } else { return false } }
                let heroLiveAtFlop = !history.events.contains { event in
                    if case .action(let seat, let street, let kind, _, _, _) = event {
                        return seat == hero && street == .preflop && kind == .fold
                    }
                    return false
                }
                if sawFlop && heroLiveAtFlop { stats.cbetOpportunities += 1 }
            }

            // Decision-quality leaks from stored analyses (§28).
            for analysis in history.analyses {
                let severe = analysis.grade == .significantMistake || analysis.grade == .blunder || analysis.grade == .inaccuracy
                switch analysis.street {
                case .river:
                    if analysis.toCall > 0 && analysis.chosenLabel.hasPrefix("call") {
                        stats.riverCallDecisions += 1
                        if severe { stats.riverCallMistakes += 1 }
                    }
                    if analysis.toCall == 0 {
                        stats.riverValueOpportunities += 1
                        if analysis.chosenLabel == "check" && analysis.recommendedLabel.hasPrefix("bet") && analysis.evLossBB > 0.5 {
                            stats.riverCheckMissedValue += 1
                        }
                    }
                case .turn:
                    if analysis.chosenLabel.hasPrefix("bet") || analysis.chosenLabel.hasPrefix("raise") {
                        stats.turnBetDecisions += 1
                        if severe { stats.turnBetMistakes += 1 }
                    }
                case .preflop:
                    // Push-fold spots: analyzer recommended a shove-sized raise.
                    if analysis.recommendedLabel.hasPrefix("raise") || analysis.recommendedLabel.hasPrefix("all") {
                        if history.bigBlind > 0, history.startingStacks[history.heroSeat] / history.bigBlind <= 12 {
                            stats.shoveSpots += 1
                            if analysis.chosenLabel == "fold" && analysis.evLossBB > 0.5 {
                                stats.passedShoves += 1
                            }
                        }
                    }
                default:
                    break
                }
            }
        }
        return stats
    }

    /// Detected leaks, most severe first. Sub-sample definitions are omitted
    /// entirely - no confident claims from ten hands (§29).
    public static func detect(histories: [HandHistory]) -> [LeakReport] {
        let stats = stats(histories: histories)
        var reports: [LeakReport] = []

        func consider(_ id: String, observed: Double, opportunities: Int, invertLow: Bool = false) {
            guard let definition = definitions.first(where: { $0.id == id }) else { return }
            guard opportunities >= definition.minSample else { return }
            let outsideHigh = observed > definition.baselineHigh
            let outsideLow = invertLow && observed < definition.baselineLow
            guard outsideHigh || outsideLow else { return }
            let distance = outsideHigh
                ? (observed - definition.baselineHigh) / max(1, definition.baselineHigh)
                : (definition.baselineLow - observed) / max(1, definition.baselineLow)
            let confidence: AnalysisConfidence
            if opportunities >= definition.minSample * 3 && distance > 0.25 { confidence = .high }
            else if opportunities >= definition.minSample * 2 || distance > 0.4 { confidence = .moderate }
            else { confidence = .low }
            reports.append(LeakReport(
                definition: definition,
                observed: observed,
                opportunities: opportunities,
                confidence: confidence,
                severity: distance * definition.severityWeight
            ))
        }

        consider("vpip.high", observed: stats.vpipPercent, opportunities: stats.hands)
        consider("vpip.low", observed: stats.vpipPercent, opportunities: stats.hands, invertLow: true)
        consider("limp", observed: stats.limpPercent, opportunities: stats.openOpportunities)
        consider("bb.overfold", observed: stats.bbFoldPercent, opportunities: stats.bbDefendOpportunities)
        consider("cbet.high", observed: stats.cbetPercent, opportunities: stats.cbetOpportunities)
        consider("fold.cbet", observed: stats.foldToCbetPercent, opportunities: stats.foldToCbetOpportunities)
        consider("turn.spew", observed: stats.turnBetMistakePercent, opportunities: stats.turnBetDecisions)
        consider("river.overcall", observed: stats.riverCallMistakePercent, opportunities: stats.riverCallDecisions)
        consider("river.missedvalue", observed: stats.missedValuePercent, opportunities: stats.riverValueOpportunities)
        consider("pushfold.passive", observed: stats.passedShovePercent, opportunities: stats.shoveSpots)

        return reports.sorted { $0.severity > $1.severity }
    }
}

/// One primary training focus at a time (§15): leak-driven when the evidence
/// exists, review-driven otherwise, curriculum-driven for new players.
public struct TrainingRecommendation: Sendable {
    public enum Kind: Sendable {
        case leak(LeakReport)
        case review(concepts: [String])
        case lesson(Lesson)
    }
    public let kind: Kind
    public let headline: String
    public let reason: String
    public let lessonID: String?
    public let estimatedMinutes: Int
}

public enum RecommendationEngine {

    public static func recommend(histories: [HandHistory], training: TrainingProgress, now: Date) -> TrainingRecommendation? {
        // 1. A confident leak beats everything.
        let leaks = LeakDetector.detect(histories: histories)
        if let top = leaks.first(where: { $0.confidence != .low }) {
            return TrainingRecommendation(
                kind: .leak(top),
                headline: top.definition.title,
                reason: top.summary + " " + top.definition.detail,
                lessonID: top.definition.lessonID,
                estimatedMinutes: Curriculum.lesson(id: top.definition.lessonID)?.estimatedMinutes ?? 6
            )
        }
        // 2. Concepts due for spaced review (§14).
        let due = training.dueConcepts(now: now)
        if !due.isEmpty {
            return TrainingRecommendation(
                kind: .review(concepts: due),
                headline: "Review time",
                reason: "Concepts due for review: \(due.prefix(3).joined(separator: ", ")). Short reviews keep skills from decaying.",
                lessonID: nil,
                estimatedMinutes: 4
            )
        }
        // 3. Otherwise: the next unlocked, unmastered lesson.
        if let next = Curriculum.all.first(where: { !training.isMastered($0.id) && training.isUnlocked($0) }) {
            return TrainingRecommendation(
                kind: .lesson(next),
                headline: "Next lesson: \(next.title)",
                reason: "Continue the \(next.academy.title) academy.",
                lessonID: next.id,
                estimatedMinutes: next.estimatedMinutes
            )
        }
        return nil
    }
}
