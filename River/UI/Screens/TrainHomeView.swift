import SwiftUI
import RiverKit

/// Train tab (§11): today's recommendation, the daily challenge, nine
/// academies with real progress, review queue and endless practice.
struct TrainHomeView: View {
    @EnvironmentObject var training: TrainingStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var game: GameViewModel

    @State private var activeDrill: DrillActivity?
    @State private var recommendation: TrainingRecommendation?

    private var accent: Color { settingsStore.accent }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                        recommendationCard
                        glossaryCard
                        dailyCard
                        reviewCard
                        academyList
                        endlessCard
                    }
                    .padding(Theme.Spacing.xl)
                }
            }
            .navigationTitle("Train")
            .navigationDestination(for: AcademyID.self) { academy in
                AcademyView(academy: academy)
            }
            .navigationDestination(for: Lesson.self) { lesson in
                LessonView(lesson: lesson)
            }
            .navigationDestination(for: String.self) { destination in
                if destination == "glossary" {
                    GlossaryView()
                }
            }
        }
        .tint(accent)
        .fullScreenCover(item: $activeDrill) { drill in
            DrillSessionView(activity: drill)
                .environmentObject(training)
                .environmentObject(settingsStore)
        }
        .task {
            let histories = game.store.loadHistories()
            let progress = training.progress
            recommendation = await Task.detached(priority: .utility) {
                return RecommendationEngine.recommend(histories: histories, training: progress, now: Date())
            }.value
        }
    }

    // MARK: - Recommendation (§34)

    @ViewBuilder
    private var recommendationCard: some View {
        if let recommendation {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("RECOMMENDED FOR YOU").sectionHeader()
                Text(recommendation.headline)
                    .font(Theme.Fonts.body.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(recommendation.reason)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let lessonID = recommendation.lessonID, let lesson = Curriculum.lesson(id: lessonID) {
                    NavigationLink(value: lesson) {
                        Text("Open lesson · ≈\(recommendation.estimatedMinutes) min")
                            .font(Theme.Fonts.secondaryAction)
                            .foregroundStyle(accent)
                    }
                }
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.backgroundElevated))
        }
    }

    /// Plain-words lookup for every term in the app.
    private var glossaryCard: some View {
        NavigationLink(value: "glossary") {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "book.closed")
                    .font(.system(size: 17))
                    .foregroundStyle(accent)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Glossary")
                        .font(Theme.Fonts.secondaryAction)
                        .foregroundStyle(Theme.textPrimary)
                    Text("What's a pot? What does BTN mean? Every term, explained simply.")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(Theme.Spacing.m)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.backgroundElevated))
        }
    }

    // MARK: - Daily challenge (§35)

    private var dailyCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                Text("DAILY CHALLENGE").sectionHeader()
                Spacer()
                if training.dailyStreak > 0 {
                    Label("\(training.dailyStreak)-day streak", systemImage: "flame.fill")
                        .font(Theme.Fonts.caption.weight(.bold))
                        .foregroundStyle(Theme.caution)
                }
            }
            if let result = training.todayResult {
                Text("Done for today: \(Int((result * 100).rounded()))%. Same puzzles for everyone; new set at midnight.")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text("Five mixed questions. Everyone gets the same set; only your first attempt counts.")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            ActionButton(
                title: training.todayResult == nil ? "Play today's challenge" : "Practice again (unscored)",
                role: training.todayResult == nil ? .primary : .secondary,
                accent: accent, identifier: "train.daily"
            ) {
                startDaily()
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.backgroundElevated))
    }

    private func startDaily() {
        let challenge = DailyChallenge.build(for: Date())
        guard !challenge.questions.isEmpty else { return }
        activeDrill = DrillActivity(
            title: challenge.title,
            questions: challenge.questions,
            conceptTagsFallback: ["daily"],
            onFinish: { score in
                training.recordDailyResult(dateKey: challenge.dateKey, score: score)
            }
        )
    }

    // MARK: - Spaced review (§15)

    @ViewBuilder
    private var reviewCard: some View {
        let due = training.progress.dueConcepts(now: Date())
        if !due.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("REVIEW DUE").sectionHeader()
                Text("\(due.count) concept\(due.count == 1 ? "" : "s") fading: a short mixed drill keeps them sharp.")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textSecondary)
                ActionButton(title: "Review now", role: .secondary, accent: accent, identifier: "train.review") {
                    startReview(concepts: due)
                }
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.backgroundElevated))
        }
    }

    private func startReview(concepts: [String]) {
        let seed = DailyChallenge.seed(forDateKey: "review#\(training.progress.totalQuestionsAnswered)")
        let questions = EndlessTrainer.batch(filter: .fullMix, seed: seed, count: 6, weakConcepts: concepts)
        guard !questions.isEmpty else { return }
        activeDrill = DrillActivity(
            title: "Review",
            questions: questions,
            conceptTagsFallback: concepts,
            onFinish: { _ in }
        )
    }

    // MARK: - Academies (§11)

    private var academyList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                Text("ACADEMIES").sectionHeader()
                Spacer()
                Text("\(training.totalMastered)/\(Curriculum.all.count) lessons")
                    .font(Theme.Fonts.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(AcademyID.allCases) { academy in
                NavigationLink(value: academy) {
                    academyRow(academy)
                }
            }
        }
    }

    private func academyRow(_ academy: AcademyID) -> some View {
        let lessons = Curriculum.lessons(in: academy)
        let mastered = training.masteredCount(in: academy)
        let complete = !lessons.isEmpty && mastered == lessons.count
        return HStack(spacing: Theme.Spacing.m) {
            Image(systemName: academy.symbolName)
                .font(.system(size: 17))
                .foregroundStyle(complete ? Theme.positive : accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(academy.title)
                    .font(Theme.Fonts.secondaryAction)
                    .foregroundStyle(Theme.textPrimary)
                ProgressView(value: lessons.isEmpty ? 0 : Double(mastered) / Double(lessons.count))
                    .tint(complete ? Theme.positive : accent)
            }
            Spacer()
            Text("\(mastered)/\(lessons.count)")
                .font(Theme.Fonts.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(Theme.Spacing.m)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.backgroundElevated))
    }

    // MARK: - Endless training (§36)

    private var endlessCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("ENDLESS PRACTICE").sectionHeader()
            Text("Unlimited generated spots. Pick a focus:")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textSecondary)
            ForEach(EndlessTrainer.Filter.allCases, id: \.self) { filter in
                Button {
                    startEndless(filter: filter)
                } label: {
                    HStack {
                        Text(filter.displayName)
                            .font(Theme.Fonts.secondaryAction)
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Image(systemName: "play.circle")
                            .foregroundStyle(accent)
                    }
                    .padding(Theme.Spacing.m)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.control).fill(Theme.backgroundElevated))
                }
            }
        }
    }

    private func startEndless(filter: EndlessTrainer.Filter) {
        let seed = DailyChallenge.seed(forDateKey: "endless#\(filter.rawValue)#\(training.progress.totalQuestionsAnswered)")
        let weak = training.progress.dueConcepts(now: Date(), limit: 10)
        let questions = EndlessTrainer.batch(filter: filter, seed: seed, count: 8, weakConcepts: weak)
        guard !questions.isEmpty else { return }
        activeDrill = DrillActivity(
            title: filter.displayName,
            questions: questions,
            conceptTagsFallback: [],
            onFinish: { _ in }
        )
    }
}

/// One academy's ordered lessons with lock and mastery state (§12).
struct AcademyView: View {
    let academy: AcademyID
    @EnvironmentObject var training: TrainingStore
    @EnvironmentObject var settingsStore: SettingsStore

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    ForEach(Curriculum.lessons(in: academy)) { lesson in
                        lessonRow(lesson)
                    }
                }
                .padding(Theme.Spacing.xl)
            }
        }
        .navigationTitle(academy.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func lessonRow(_ lesson: Lesson) -> some View {
        let unlocked = training.progress.isUnlocked(lesson)
        let mastered = training.progress.isMastered(lesson.id)
        if unlocked {
            NavigationLink(value: lesson) {
                lessonRowContent(lesson, mastered: mastered, locked: false)
            }
        } else {
            lessonRowContent(lesson, mastered: false, locked: true)
        }
    }

    private func lessonRowContent(_ lesson: Lesson, mastered: Bool, locked: Bool) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: mastered ? "checkmark.seal.fill" : (locked ? "lock.fill" : "book.fill"))
                .font(.system(size: 15))
                .foregroundStyle(mastered ? Theme.positive : (locked ? Theme.textTertiary : settingsStore.accent))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(lesson.title)
                    .font(Theme.Fonts.secondaryAction)
                    .foregroundStyle(locked ? Theme.textTertiary : Theme.textPrimary)
                Text(locked ? "Master the previous lesson to unlock" : "≈\(lesson.estimatedMinutes) min · \(lesson.drill.questionCount) questions")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            if !locked {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.backgroundElevated.opacity(locked ? 0.5 : 1)))
    }
}
