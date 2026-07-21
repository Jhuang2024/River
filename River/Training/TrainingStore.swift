import Foundation
import SwiftUI
import RiverKit

/// Owns curriculum progress (§13): mastery per lesson, spaced review, daily
/// challenge results. Persists after every recorded answer so training is
/// never lost to an interruption.
@MainActor
final class TrainingStore: ObservableObject {
    static let fileName = "training"

    @Published var progress: TrainingProgress {
        didSet { save() }
    }

    let store: PersistenceStore

    init(store: PersistenceStore) {
        self.store = store
        self.progress = store.load(TrainingProgress.self, from: Self.fileName) ?? TrainingProgress()
    }

    private func save() {
        try? store.save(progress, as: Self.fileName)
    }

    // MARK: - Recording

    func recordAnswer(conceptTags: [String], correct: Bool) {
        progress.recordAnswer(conceptTags: conceptTags, correct: correct, now: Date())
    }

    func recordLessonResult(_ lesson: Lesson, score: Double) {
        progress.recordLessonResult(lesson.id, score: score, threshold: lesson.masteryThreshold, now: Date())
    }

    /// Only the first attempt of a day counts (§35).
    func recordDailyResult(dateKey: String, score: Double) {
        guard progress.dailyResults[dateKey] == nil else { return }
        progress.dailyResults[dateKey] = score
    }

    // MARK: - Derived state

    func masteredCount(in academy: AcademyID) -> Int {
        return Curriculum.lessons(in: academy).filter { progress.isMastered($0.id) }.count
    }

    func academyComplete(_ academy: AcademyID) -> Bool {
        let lessons = Curriculum.lessons(in: academy)
        return !lessons.isEmpty && masteredCount(in: academy) == lessons.count
    }

    var totalMastered: Int {
        return Curriculum.all.filter { progress.isMastered($0.id) }.count
    }

    /// The first unlocked, unmastered lesson in curriculum order.
    var nextLesson: Lesson? {
        return Curriculum.all.first { !progress.isMastered($0.id) && progress.isUnlocked($0) }
    }

    /// Consecutive days ending today (or yesterday) with a daily result (§35).
    var dailyStreak: Int {
        let calendar = Calendar.current
        var day = Date()
        var streak = 0
        // A streak survives until a full day is missed.
        if progress.dailyResults[DailyChallenge.dateKey(for: day, calendar: calendar)] == nil {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        while progress.dailyResults[DailyChallenge.dateKey(for: day, calendar: calendar)] != nil {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    var todayResult: Double? {
        return progress.dailyResults[DailyChallenge.dateKey(for: Date())]
    }
}
