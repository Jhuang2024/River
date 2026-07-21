import XCTest
@testable import RiverKit

/// Curriculum content integrity (§18, §63) and drill generation (§16–17).
final class CurriculumTests: XCTestCase {

    func testShippedCurriculumPassesValidation() {
        let problems = Curriculum.validate()
        XCTAssertEqual(problems, [], "curriculum problems: \(problems.joined(separator: "; "))")
    }

    func testEveryAcademyHasLessonsAndAReachableStart() {
        for academy in AcademyID.allCases {
            let lessons = Curriculum.lessons(in: academy)
            XCTAssertFalse(lessons.isEmpty, "\(academy.rawValue) has no lessons")
        }
        // A fresh player must have at least one unlocked lesson to begin with.
        let fresh = TrainingProgress()
        XCTAssertTrue(Curriculum.all.contains { fresh.isUnlocked($0) })
    }

    func testQuizPlansAreInternallyConsistent() {
        for lesson in Curriculum.all {
            if case .quiz(let questions) = lesson.drill {
                for question in questions {
                    XCTAssertGreaterThanOrEqual(question.choices.count, 2, "\(lesson.id): quiz needs 2+ choices")
                    XCTAssertTrue(question.choices.indices.contains(question.correctIndex),
                                  "\(lesson.id): correct index out of range")
                    XCTAssertFalse(question.explanation.isEmpty, "\(lesson.id): missing explanation")
                }
            }
        }
    }

    func testKnowledgeDrillsGenerateValidatedQuestions() {
        let plans: [DrillPlan] = [
            .handReading(count: 6), .winnerPick(count: 4), .potOdds(count: 6),
            .outs(count: 4), .combos(count: 4)
        ]
        for plan in plans {
            let questions = DrillEngine.questions(for: plan, seed: 7, conceptTag: "test")
            XCTAssertEqual(questions.count, plan.questionCount)
            for question in questions {
                XCTAssertTrue(DrillEngine.validate(question), "invalid question: \(question.prompt)")
                XCTAssertTrue(question.choices.contains { $0.grade == .correct },
                              "no correct choice in: \(question.prompt)")
            }
        }
    }

    func testLiveDecisionDrillsAreGradedByTheRealAnalyzer() {
        // One of each scripted live-spot family; graded answers must include a
        // correct action and per-choice explanations.
        let plans: [DrillPlan] = [
            .preflop(count: 2, scenario: .facingOpen, stackBB: 100),
            .pushFold(count: 2, stackBB: 8),
            .postflop(count: 2, street: .river)
        ]
        for plan in plans {
            let questions = DrillEngine.questions(for: plan, seed: 11, conceptTag: "live")
            XCTAssertFalse(questions.isEmpty, "no questions for \(plan)")
            for question in questions {
                XCTAssertNotNil(question.scenario, "live drills must carry a table scenario")
                XCTAssertTrue(question.choices.contains { $0.grade == .correct })
                XCTAssertTrue(question.choices.allSatisfy { !$0.explanation.isEmpty })
            }
        }
    }

    func testDrillGenerationIsDeterministicPerSeed() {
        let plan = DrillPlan.potOdds(count: 5)
        let first = DrillEngine.questions(for: plan, seed: 123, conceptTag: "x")
        let second = DrillEngine.questions(for: plan, seed: 123, conceptTag: "x")
        XCTAssertEqual(first, second)
        let different = DrillEngine.questions(for: plan, seed: 124, conceptTag: "x")
        XCTAssertNotEqual(first.map { $0.prompt }, different.map { $0.prompt })
    }

    func testSpacedReviewDoublesOnSuccessAndResetsOnFailure() {
        var review = ReviewState()
        let now = Date(timeIntervalSince1970: 1_000_000)
        review.record(correct: true, now: now)
        let firstInterval = review.intervalDays
        review.record(correct: true, now: now)
        XCTAssertGreaterThan(review.intervalDays, firstInterval, "success must lengthen the interval")
        review.record(correct: false, now: now)
        XCTAssertEqual(review.intervalDays, 1, accuracy: 0.001, "a lapse restarts the schedule")
        XCTAssertEqual(review.lapses, 1)
    }

    func testMasteryRequiresTheThresholdAndPrerequisitesGateUnlocks() {
        guard let first = Curriculum.all.first,
              let dependent = Curriculum.all.first(where: { $0.prerequisites.contains(first.id) }) else {
            return XCTFail("expected a lesson chain")
        }
        var progress = TrainingProgress()
        XCTAssertFalse(progress.isUnlocked(dependent))

        let now = Date(timeIntervalSince1970: 2_000_000)
        progress.recordLessonResult(first.id, score: first.masteryThreshold - 0.05,
                                    threshold: first.masteryThreshold, now: now)
        XCTAssertFalse(progress.isMastered(first.id), "below-threshold score must not master")
        XCTAssertFalse(progress.isUnlocked(dependent))

        progress.recordLessonResult(first.id, score: first.masteryThreshold + 0.05,
                                    threshold: first.masteryThreshold, now: now)
        XCTAssertTrue(progress.isMastered(first.id))
        XCTAssertTrue(progress.isUnlocked(dependent))
    }

    func testDailyChallengeIsDeterministicPerDayAndVariesAcrossDays() {
        let calendar = Calendar(identifier: .gregorian)
        let monday = Date(timeIntervalSince1970: 1_900_000_000)
        let tuesday = monday.addingTimeInterval(86_400)
        let first = DailyChallenge.build(for: monday, calendar: calendar)
        let again = DailyChallenge.build(for: monday, calendar: calendar)
        XCTAssertEqual(first.dateKey, again.dateKey)
        XCTAssertEqual(first.questions.map { $0.prompt }, again.questions.map { $0.prompt })
        XCTAssertFalse(first.questions.isEmpty)

        let other = DailyChallenge.build(for: tuesday, calendar: calendar)
        XCTAssertNotEqual(first.dateKey, other.dateKey)
        XCTAssertNotEqual(first.seed, other.seed)
    }

    func testEndlessTrainerProducesEveryFilter() {
        for filter in EndlessTrainer.Filter.allCases {
            let batch = EndlessTrainer.batch(filter: filter, seed: 5, count: 3)
            XCTAssertFalse(batch.isEmpty, "filter \(filter.rawValue) produced nothing")
        }
    }
}
