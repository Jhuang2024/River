import SwiftUI
import RiverKit

/// One lesson (§12): objectives, short teaching sections, then a drill graded
/// by the real analyzer. Mastery unlocks the next lesson in the academy.
struct LessonView: View {
    let lesson: Lesson
    @EnvironmentObject var training: TrainingStore
    @EnvironmentObject var settingsStore: SettingsStore

    @State private var activeDrill: DrillActivity?
    @State private var lastScore: Double?

    private var accent: Color { settingsStore.accent }
    private var mastery: MasteryState {
        return training.progress.mastery[lesson.id] ?? MasteryState()
    }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    header
                    objectivesCard
                    Text(lesson.intro)
                        .font(Theme.Fonts.body)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(lesson.sections.enumerated()), id: \.offset) { _, section in
                        sectionCard(section)
                    }
                    drillCard
                }
                .padding(Theme.Spacing.xl)
            }
        }
        .navigationTitle(lesson.title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $activeDrill) { drill in
            DrillSessionView(activity: drill)
                .environmentObject(training)
                .environmentObject(settingsStore)
        }
    }

    private var header: some View {
        HStack {
            Label(lesson.academy.title, systemImage: lesson.academy.symbolName)
                .font(Theme.Fonts.caption.weight(.semibold))
                .foregroundStyle(accent)
            Spacer()
            Text("≈\(lesson.estimatedMinutes) min")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textSecondary)
            if mastery.mastered {
                Label("Mastered", systemImage: "checkmark.seal.fill")
                    .font(Theme.Fonts.caption.weight(.bold))
                    .foregroundStyle(Theme.positive)
            }
        }
    }

    private var objectivesCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("YOU WILL LEARN").sectionHeader()
            ForEach(lesson.objectives, id: \.self) { objective in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 5))
                        .foregroundStyle(accent)
                        .padding(.top, 6)
                    Text(objective)
                        .font(Theme.Fonts.body)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.backgroundElevated))
    }

    private func sectionCard(_ section: LessonSection) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(section.heading)
                .font(Theme.Fonts.body.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            Text(section.body)
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var drillCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("PRACTICE").sectionHeader()
            Text("\(lesson.drill.questionCount) questions · \(Int(lesson.masteryThreshold * 100))% needed to master")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textSecondary)
            if mastery.attempts > 0 {
                Text("Best \(Int((mastery.bestScore * 100).rounded()))% over \(mastery.attempts) attempt\(mastery.attempts == 1 ? "" : "s")")
                    .font(Theme.Fonts.caption)
                    .monospacedDigit()
                    .foregroundStyle(mastery.mastered ? Theme.positive : Theme.textSecondary)
            }
            if let lastScore {
                Text(lastScore >= lesson.masteryThreshold
                     ? "Passed with \(Int((lastScore * 100).rounded()))% — nicely done."
                     : "\(Int((lastScore * 100).rounded()))% — review the sections above and try again.")
                    .font(Theme.Fonts.caption.weight(.semibold))
                    .foregroundStyle(lastScore >= lesson.masteryThreshold ? Theme.positive : Theme.caution)
            }
            ActionButton(
                title: mastery.mastered ? "Practice again" : (mastery.attempts > 0 ? "Try again" : "Start drill"),
                role: .primary, accent: accent, identifier: "lesson.drill"
            ) {
                startDrill()
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.backgroundElevated))
    }

    private func startDrill() {
        // Each attempt gets a fresh deterministic seed so retries see new
        // scenarios but the same attempt always regenerates identically.
        let attemptSeed = DailyChallenge.seed(forDateKey: "\(lesson.id)#\(mastery.attempts)")
        let questions = DrillEngine.questions(
            for: lesson.drill,
            seed: attemptSeed,
            conceptTag: lesson.conceptTags.first ?? lesson.id
        )
        guard !questions.isEmpty else { return }
        let captured = lesson
        activeDrill = DrillActivity(
            title: lesson.title,
            questions: questions,
            conceptTagsFallback: lesson.conceptTags,
            onFinish: { score in
                training.recordLessonResult(captured, score: score)
                lastScore = score
            }
        )
    }
}
