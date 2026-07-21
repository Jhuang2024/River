import Foundation

/// Decision-quality rating (§26-27): computed from stored analyses, never
/// from chips won. Confidence grows with sample; single hands barely move it.
public struct RatingReport: Codable, Hashable, Sendable {
    public struct StreetRating: Codable, Hashable, Sendable {
        public let rating: Int
        public let samples: Int
    }

    public let overall: Int
    public let samples: Int
    public let confidence: AnalysisConfidence
    public let byStreet: [Street: StreetRating]
    /// Rating over the most recent window minus the older window.
    public let recentTrend: Int
    /// Honest reason line ("42 strong decisions, 3 inaccuracies…").
    public let changeSummary: String
}

public enum RatingEngine {

    /// Per-decision quality in 0...1, weighted by analysis confidence so an
    /// uncertain model moves the rating less (§27).
    static func decisionQuality(_ analysis: DecisionAnalysis) -> (quality: Double, weight: Double) {
        let quality = max(0, 1.0 - min(1.0, analysis.evLossBB / 3.0))
        let weight: Double
        switch analysis.confidence {
        case .high: weight = 1.0
        case .moderate: weight = 0.7
        case .low: weight = 0.35
        }
        return (quality, weight)
    }

    /// Computes the full report from hand histories (most recent last).
    public static func compute(histories: [HandHistory]) -> RatingReport {
        var analyses: [DecisionAnalysis] = []
        for history in histories {
            analyses.append(contentsOf: history.analyses)
        }
        // Bound the window: ratings reflect recent play, not ancient history.
        let window = Array(analyses.suffix(600))

        func rating(for subset: [DecisionAnalysis]) -> (rating: Int, samples: Int) {
            guard !subset.isEmpty else { return (1000, 0) }
            var totalQuality = 0.0
            var totalWeight = 0.0
            for analysis in subset {
                let (quality, weight) = decisionQuality(analysis)
                totalQuality += quality * weight
                totalWeight += weight
            }
            guard totalWeight > 0 else { return (1000, 0) }
            let average = totalQuality / totalWeight
            // 800 (constant severe errors) ... 1500 (near-flawless).
            return (Int((800 + average * 700).rounded()), subset.count)
        }

        let overallResult = rating(for: window)
        var streets: [Street: RatingReport.StreetRating] = [:]
        for street in Street.allCases {
            let subset = window.filter { $0.street == street }
            let result = rating(for: subset)
            streets[street] = RatingReport.StreetRating(rating: result.rating, samples: result.samples)
        }

        let confidence: AnalysisConfidence
        if window.count < 40 { confidence = .low }
        else if window.count < 200 { confidence = .moderate }
        else { confidence = .high }

        // Trend: last 100 vs the 100 before.
        var trend = 0
        if window.count >= 80 {
            let recent = Array(window.suffix(100))
            let older = Array(window.dropLast(100).suffix(100))
            if !older.isEmpty {
                trend = rating(for: recent).rating - rating(for: older).rating
            }
        }

        // Honest change summary (§27).
        let recent = window.suffix(60)
        let strong = recent.filter { $0.grade == .strong || $0.grade == .excellent }.count
        let inaccuracies = recent.filter { $0.grade == .inaccuracy }.count
        let severe = recent.filter { $0.grade == .significantMistake || $0.grade == .blunder }.count
        var summary = "Last \(recent.count) analysed decisions: \(strong) strong or better"
        if inaccuracies > 0 { summary += ", \(inaccuracies) inaccuracies" }
        summary += severe > 0 ? ", \(severe) serious mistakes." : ", no serious mistakes."

        return RatingReport(
            overall: overallResult.rating,
            samples: overallResult.samples,
            confidence: confidence,
            byStreet: streets,
            recentTrend: trend,
            changeSummary: summary
        )
    }
}

/// Achievements (§41): meaningful skill and variety, no pure-luck trophies.
public struct AchievementDefinition: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let symbolName: String
}

public struct AchievementEvidence: Sendable {
    public let histories: [HandHistory]
    public let training: TrainingProgress
    public let campaign: CampaignProgress
    public let tournamentsFinished: Int
    public let tournamentWins: Int

    public init(histories: [HandHistory], training: TrainingProgress, campaign: CampaignProgress, tournamentsFinished: Int, tournamentWins: Int) {
        self.histories = histories
        self.training = training
        self.campaign = campaign
        self.tournamentsFinished = tournamentsFinished
        self.tournamentWins = tournamentWins
    }
}

public enum AchievementLibrary {

    public static let all: [AchievementDefinition] = [
        AchievementDefinition(id: "rules.master", title: "Knows the Rules", detail: "Master the Poker Foundations academy.", symbolName: "book.closed.fill"),
        AchievementDefinition(id: "hands.100", title: "First Hundred", detail: "Play 100 hands.", symbolName: "1.circle.fill"),
        AchievementDefinition(id: "hands.1000", title: "Volume Player", detail: "Play 1,000 hands.", symbolName: "repeat.circle.fill"),
        AchievementDefinition(id: "strong.river.25", title: "River Judge", detail: "Make 25 strong or excellent river decisions.", symbolName: "5.square.fill"),
        AchievementDefinition(id: "clean.session", title: "Clean Sheet", detail: "Complete a 20-hand session with no serious mistakes.", symbolName: "checkmark.seal.fill"),
        AchievementDefinition(id: "preflop.master", title: "Preflop Graduate", detail: "Master the Preflop Strategy academy.", symbolName: "square.grid.3x3.fill"),
        AchievementDefinition(id: "math.master", title: "Mathematician", detail: "Master the Poker Mathematics academy.", symbolName: "percent"),
        AchievementDefinition(id: "tourney.first", title: "Tournament Player", detail: "Finish a Sit-and-Go.", symbolName: "trophy.fill"),
        AchievementDefinition(id: "tourney.win", title: "Champion", detail: "Win a Sit-and-Go.", symbolName: "crown.fill"),
        AchievementDefinition(id: "tier.3", title: "Local Legend", detail: "Complete Stakes Ladder tier 3.", symbolName: "building.2.fill"),
        AchievementDefinition(id: "tier.7", title: "Final Table", detail: "Complete every Stakes Ladder tier.", symbolName: "flag.checkered"),
        AchievementDefinition(id: "drills.200", title: "Grinder", detail: "Answer 200 training questions.", symbolName: "dumbbell.fill"),
        AchievementDefinition(id: "streak.10", title: "Locked In", detail: "Reach a 10-question correct streak.", symbolName: "flame.fill"),
        AchievementDefinition(id: "review.20", title: "Student of the Game", detail: "Keep 20 concepts in active review.", symbolName: "arrow.triangle.2.circlepath"),
        AchievementDefinition(id: "allin.win", title: "Held Up", detail: "Win an all-in at showdown.", symbolName: "bolt.circle.fill"),
        AchievementDefinition(id: "bigpot", title: "Big Pot", detail: "Win a pot of 100 big blinds or more.", symbolName: "circle.hexagongrid.fill"),
        AchievementDefinition(id: "curriculum.half", title: "Halfway Scholar", detail: "Master half of all lessons.", symbolName: "graduationcap.fill"),
        AchievementDefinition(id: "curriculum.full", title: "The Complete Player", detail: "Master every lesson in every academy.", symbolName: "star.circle.fill"),
        AchievementDefinition(id: "daily.5", title: "Regular", detail: "Complete 5 daily challenges.", symbolName: "calendar"),
        AchievementDefinition(id: "hu.session", title: "Duelist", detail: "Complete a heads-up session.", symbolName: "person.2.fill")
    ]

    /// Which achievements the evidence unlocks. Pure function; no storage.
    public static func unlocked(evidence: AchievementEvidence) -> Set<String> {
        var result = Set<String>()
        let histories = evidence.histories
        let training = evidence.training

        func academyMastered(_ academy: AcademyID) -> Bool {
            let lessons = Curriculum.lessons(in: academy)
            return !lessons.isEmpty && lessons.allSatisfy { training.isMastered($0.id) }
        }

        if academyMastered(.foundations) { result.insert("rules.master") }
        if academyMastered(.preflop) { result.insert("preflop.master") }
        if academyMastered(.mathematics) { result.insert("math.master") }
        if histories.count >= 100 { result.insert("hands.100") }
        if histories.count >= 1000 { result.insert("hands.1000") }

        let allAnalyses = histories.flatMap { $0.analyses }
        let strongRivers = allAnalyses.filter { $0.street == .river && ($0.grade == .strong || $0.grade == .excellent) }.count
        if strongRivers >= 25 { result.insert("strong.river.25") }

        if evidence.tournamentsFinished >= 1 { result.insert("tourney.first") }
        if evidence.tournamentWins >= 1 { result.insert("tourney.win") }
        if evidence.campaign.progress(for: 3).completed { result.insert("tier.3") }
        if CampaignLibrary.tiers.allSatisfy({ evidence.campaign.progress(for: $0.id).completed }) { result.insert("tier.7") }
        if training.totalQuestionsAnswered >= 200 { result.insert("drills.200") }
        if training.bestStreak >= 10 { result.insert("streak.10") }
        if training.review.count >= 20 { result.insert("review.20") }
        if training.dailyResults.count >= 5 { result.insert("daily.5") }

        let mastered = Curriculum.all.filter { training.isMastered($0.id) }.count
        if mastered * 2 >= Curriculum.all.count && !Curriculum.all.isEmpty { result.insert("curriculum.half") }
        if mastered == Curriculum.all.count && !Curriculum.all.isEmpty { result.insert("curriculum.full") }

        for history in histories {
            let heroAllIn = history.events.contains { event in
                if case .action(let seat, _, _, _, _, let isAllIn) = event { return seat == history.heroSeat && isAllIn }
                return false
            }
            if heroAllIn && history.wentToShowdown && history.heroNet > 0 { result.insert("allin.win") }
            if history.heroNet >= history.bigBlind * 100 { result.insert("bigpot") }
            if history.playerNames.count == 2 { result.insert("hu.session") }
        }

        // Clean session: any run of 20 consecutive hands with analyses and no
        // severe mistakes.
        var consecutive = 0
        for history in histories {
            let severe = history.analyses.contains { $0.grade == .blunder || $0.grade == .significantMistake }
            if severe {
                consecutive = 0
            } else {
                consecutive += 1
                if consecutive >= 20 { result.insert("clean.session") }
            }
        }
        return result
    }
}
