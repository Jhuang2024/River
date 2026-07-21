import Foundation

/// The nine academies (§3).
public enum AcademyID: String, Codable, CaseIterable, Sendable, Identifiable {
    case foundations
    case preflop
    case flop
    case turn
    case river
    case mathematics
    case exploitative
    case tournament
    case advancedRanges

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .foundations: return "Poker Foundations"
        case .preflop: return "Preflop Strategy"
        case .flop: return "Flop Strategy"
        case .turn: return "Turn Strategy"
        case .river: return "River Strategy"
        case .mathematics: return "Poker Mathematics"
        case .exploitative: return "Exploitative Play"
        case .tournament: return "Tournament Poker"
        case .advancedRanges: return "Advanced Range Strategy"
        }
    }

    public var symbolName: String {
        switch self {
        case .foundations: return "book.closed.fill"
        case .preflop: return "square.grid.3x3.fill"
        case .flop: return "3.square.fill"
        case .turn: return "4.square.fill"
        case .river: return "5.square.fill"
        case .mathematics: return "percent"
        case .exploitative: return "scope"
        case .tournament: return "trophy.fill"
        case .advancedRanges: return "chart.bar.doc.horizontal.fill"
        }
    }
}

/// One authored multiple-choice rules/concept question.
public struct QuizQuestion: Codable, Hashable, Sendable {
    public let prompt: String
    public let choices: [String]
    public let correctIndex: Int
    public let explanation: String

    public init(_ prompt: String, _ choices: [String], correct: Int, why explanation: String) {
        self.prompt = prompt
        self.choices = choices
        self.correctIndex = correct
        self.explanation = explanation
    }
}

/// Preflop drill scenario families (§16).
public enum PreflopScenarioKind: String, Codable, Sendable {
    case unopened
    case facingOpen
    case facingThreeBet
    case blindDefense
}

/// Generator configuration for a lesson's practice set (§16).
public enum DrillPlan: Codable, Hashable, Sendable {
    /// Identify your best five-card hand category.
    case handReading(count: Int)
    /// Decide who wins a shown showdown.
    case winnerPick(count: Int)
    /// Pot-odds / required-equity arithmetic.
    case potOdds(count: Int)
    /// Count clean outs for a draw.
    case outs(count: Int)
    /// Combination counting with blockers.
    case combos(count: Int)
    /// Live preflop decisions graded by the real analyzer.
    case preflop(count: Int, scenario: PreflopScenarioKind, stackBB: Int)
    /// Short-stack shove/fold decisions.
    case pushFold(count: Int, stackBB: Int)
    /// Live postflop decisions on a target street.
    case postflop(count: Int, street: Street)
    /// Authored concept questions.
    case quiz([QuizQuestion])

    public var questionCount: Int {
        switch self {
        case .handReading(let n), .winnerPick(let n), .potOdds(let n),
             .outs(let n), .combos(let n): return n
        case .preflop(let n, _, _), .pushFold(let n, _), .postflop(let n, _): return n
        case .quiz(let questions): return questions.count
        }
    }
}

/// A short demonstration block inside a lesson (§13).
public struct LessonSection: Codable, Hashable, Sendable {
    public let heading: String
    public let body: String

    public init(_ heading: String, _ body: String) {
        self.heading = heading
        self.body = body
    }
}

/// One lesson (§3): identity, prerequisites, teaching content, drill plan.
public struct Lesson: Identifiable, Hashable, Sendable {
    public static let contentVersion = 1

    public let id: String
    public let academy: AcademyID
    public let title: String
    /// 1 (introductory) ... 5 (advanced).
    public let difficulty: Int
    public let prerequisites: [String]
    public let objectives: [String]
    /// Kept under roughly 150 words (§13): decisions over reading.
    public let intro: String
    public let sections: [LessonSection]
    public let drill: DrillPlan
    /// Fraction of full drill credit required for mastery.
    public let masteryThreshold: Double
    /// Concept tags: drive spaced review and leak linkage (§14, §28).
    public let conceptTags: [String]
    public let estimatedMinutes: Int

    public init(id: String, academy: AcademyID, title: String, difficulty: Int,
                prerequisites: [String] = [], objectives: [String],
                intro: String, sections: [LessonSection] = [],
                drill: DrillPlan, masteryThreshold: Double = 0.8,
                conceptTags: [String], estimatedMinutes: Int = 5) {
        self.id = id
        self.academy = academy
        self.title = title
        self.difficulty = difficulty
        self.prerequisites = prerequisites
        self.objectives = objectives
        self.intro = intro
        self.sections = sections
        self.drill = drill
        self.masteryThreshold = masteryThreshold
        self.conceptTags = conceptTags
        self.estimatedMinutes = estimatedMinutes
    }
}

/// Per-lesson mastery record (§13).
public struct MasteryState: Codable, Hashable, Sendable {
    public var attempts: Int = 0
    public var bestScore: Double = 0
    public var lastScore: Double = 0
    public var mastered: Bool = false
    public var lastAttemptDate: Date? = nil

    public init() {}
}

/// Per-concept spaced-review record (§14).
public struct ReviewState: Codable, Hashable, Sendable {
    public var timesSeen: Int = 0
    public var timesCorrect: Int = 0
    /// Exponentially weighted recent accuracy 0...1.
    public var recentAccuracy: Double = 0.5
    public var intervalDays: Double = 1
    public var dueDate: Date = Date(timeIntervalSince1970: 0)
    public var lapses: Int = 0

    public init() {}

    /// Adapted spaced repetition: right answers stretch the interval, wrong
    /// answers reset it. No punishment for skipped days (§18).
    public mutating func record(correct: Bool, now: Date) {
        timesSeen += 1
        if correct { timesCorrect += 1 }
        recentAccuracy = recentAccuracy * 0.7 + (correct ? 1.0 : 0.0) * 0.3
        if correct {
            intervalDays = min(30, max(1, intervalDays * 2))
        } else {
            lapses += 1
            intervalDays = 1
        }
        dueDate = now.addingTimeInterval(intervalDays * 86_400)
    }
}

/// The player's whole local training record, persisted as one payload (§52).
public struct TrainingProgress: Codable, Hashable, Sendable {
    public var mastery: [String: MasteryState] = [:]
    public var review: [String: ReviewState] = [:]
    public var totalQuestionsAnswered: Int = 0
    public var totalCorrect: Int = 0
    public var bestStreak: Int = 0
    public var dailyResults: [String: Double] = [:] // "YYYY-MM-DD" -> first-attempt score

    public init() {}

    public func isMastered(_ lessonID: String) -> Bool {
        return mastery[lessonID]?.mastered ?? false
    }

    /// A lesson is unlocked when every prerequisite is mastered.
    public func isUnlocked(_ lesson: Lesson) -> Bool {
        return lesson.prerequisites.allSatisfy { isMastered($0) }
    }

    /// Concepts due for review, weakest first (§14).
    public func dueConcepts(now: Date, limit: Int = 6) -> [String] {
        return review
            .filter { $0.value.dueDate <= now && $0.value.timesSeen > 0 }
            .sorted { lhs, rhs in
                if lhs.value.recentAccuracy != rhs.value.recentAccuracy {
                    return lhs.value.recentAccuracy < rhs.value.recentAccuracy
                }
                return lhs.value.dueDate < rhs.value.dueDate
            }
            .prefix(limit)
            .map { $0.key }
    }

    public mutating func recordAnswer(conceptTags: [String], correct: Bool, now: Date) {
        totalQuestionsAnswered += 1
        if correct { totalCorrect += 1 }
        for tag in conceptTags {
            var state = review[tag] ?? ReviewState()
            state.record(correct: correct, now: now)
            review[tag] = state
        }
    }

    public mutating func recordLessonResult(_ lessonID: String, score: Double, threshold: Double, now: Date) {
        var state = mastery[lessonID] ?? MasteryState()
        state.attempts += 1
        state.lastScore = score
        state.bestScore = max(state.bestScore, score)
        state.lastAttemptDate = now
        if score >= threshold {
            state.mastered = true
        }
        mastery[lessonID] = state
    }
}

/// Registry + validation for all curriculum content (§3, §58).
public enum Curriculum {

    public static var all: [Lesson] {
        return CurriculumContent.lessons
    }

    public static func lessons(in academy: AcademyID) -> [Lesson] {
        return all.filter { $0.academy == academy }
    }

    public static func lesson(id: String) -> Lesson? {
        return all.first { $0.id == id }
    }

    /// Returns human-readable content problems; empty means valid (§58).
    public static func validate() -> [String] {
        var problems: [String] = []
        var seen = Set<String>()
        let ids = Set(all.map { $0.id })
        for lesson in all {
            if !seen.insert(lesson.id).inserted {
                problems.append("duplicate lesson id \(lesson.id)")
            }
            if lesson.intro.split(separator: " ").count > 170 {
                problems.append("\(lesson.id): intro exceeds word budget")
            }
            if lesson.masteryThreshold < 0.5 || lesson.masteryThreshold > 1 {
                problems.append("\(lesson.id): unreasonable mastery threshold")
            }
            if lesson.conceptTags.isEmpty {
                problems.append("\(lesson.id): no concept tags")
            }
            if lesson.drill.questionCount == 0 {
                problems.append("\(lesson.id): empty drill plan")
            }
            for prerequisite in lesson.prerequisites where !ids.contains(prerequisite) {
                problems.append("\(lesson.id): missing prerequisite \(prerequisite)")
            }
            if case .quiz(let questions) = lesson.drill {
                for (index, question) in questions.enumerated() {
                    if question.choices.count < 2 || !question.choices.indices.contains(question.correctIndex) {
                        problems.append("\(lesson.id) quiz[\(index)]: bad choices")
                    }
                    if question.explanation.isEmpty {
                        problems.append("\(lesson.id) quiz[\(index)]: missing explanation")
                    }
                }
            }
        }
        // Prerequisite graph must be acyclic (§58).
        var visiting = Set<String>()
        var done = Set<String>()
        func hasCycle(_ id: String) -> Bool {
            if done.contains(id) { return false }
            if visiting.contains(id) { return true }
            visiting.insert(id)
            defer { visiting.remove(id); done.insert(id) }
            guard let lesson = lesson(id: id) else { return false }
            for prerequisite in lesson.prerequisites {
                if hasCycle(prerequisite) { return true }
            }
            return false
        }
        for lesson in all where hasCycle(lesson.id) {
            problems.append("curriculum cycle involving \(lesson.id)")
        }
        return problems
    }
}
