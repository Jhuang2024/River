import SwiftUI
import RiverKit

/// A runnable drill: a titled batch of questions plus what to do with the
/// final score. Shared by lessons, the daily challenge and endless training.
struct DrillActivity: Identifiable {
    let id = UUID()
    let title: String
    let questions: [DrillQuestion]
    let conceptTagsFallback: [String]
    /// Called once with the earned credit fraction (0...1).
    let onFinish: (Double) -> Void
}

/// One question at a time, graded instantly with the real analyzer's labels
/// and explanations (§14). No lives, no timers — just honest feedback.
struct DrillSessionView: View {
    let activity: DrillActivity
    @EnvironmentObject var training: TrainingStore
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var index = 0
    @State private var selectedChoice: Int?
    @State private var earnedCredit: Double = 0
    @State private var correctCount = 0
    @State private var finished = false
    @State private var reportedScore = false

    private var accent: Color { settingsStore.accent }
    private var question: DrillQuestion? {
        return activity.questions.indices.contains(index) ? activity.questions[index] : nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                if finished {
                    summary
                } else if let question {
                    questionBody(question)
                }
            }
            .navigationTitle(activity.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(min(index + 1, activity.questions.count))/\(activity.questions.count)")
                        .font(Theme.Fonts.telemetry)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .interactiveDismissDisabled(selectedChoice != nil && !finished)
    }

    // MARK: - Question

    private func questionBody(_ question: DrillQuestion) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Text(question.prompt)
                    .font(Theme.Fonts.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let scenario = question.scenario {
                    scenarioCard(scenario)
                }

                VStack(spacing: Theme.Spacing.s) {
                    ForEach(Array(question.choices.enumerated()), id: \.offset) { choiceIndex, choice in
                        choiceRow(choice, at: choiceIndex)
                    }
                }

                if let selectedChoice, question.choices.indices.contains(selectedChoice) {
                    feedback(question.choices[selectedChoice])
                }
            }
            .padding(Theme.Spacing.xl)
        }
    }

    private func scenarioCard(_ scenario: DrillScenario) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.m) {
                HStack(spacing: 4) {
                    ForEach(Array(scenario.heroCards.enumerated()), id: \.offset) { _, card in
                        PlayingCardView(card: card, width: 40, style: settingsStore.settings.deckStyle)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(scenario.positionName)
                        .font(Theme.Fonts.stackValue)
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(scenario.stackBB) BB deep")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("Pot \(scenario.pot)")
                        .font(Theme.Fonts.stackValue)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    if scenario.toCall > 0 {
                        Text("To call \(scenario.toCall)")
                            .font(Theme.Fonts.caption)
                            .monospacedDigit()
                            .foregroundStyle(Theme.caution)
                    }
                }
            }
            if !scenario.board.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(scenario.board.enumerated()), id: \.offset) { _, card in
                        PlayingCardView(card: card, width: 34, style: settingsStore.settings.deckStyle)
                    }
                }
            }
            ForEach(scenario.contextLines, id: \.self) { line in
                Text(line)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.backgroundElevated))
    }

    private func choiceRow(_ choice: DrillChoice, at choiceIndex: Int) -> some View {
        let answered = selectedChoice != nil
        let isSelected = selectedChoice == choiceIndex
        let showAsCorrect = answered && choice.grade == .correct
        return Button {
            select(choiceIndex)
        } label: {
            HStack {
                Text(choice.label)
                    .font(Theme.Fonts.secondaryAction)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer()
                if answered && (isSelected || showAsCorrect) {
                    Text(choice.grade.displayName)
                        .font(Theme.Fonts.caption.weight(.bold))
                        .foregroundStyle(gradeColor(choice.grade))
                }
            }
            .padding(Theme.Spacing.m)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.control)
                    .fill(Theme.backgroundElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.control)
                    .strokeBorder(
                        answered
                            ? (showAsCorrect ? Theme.positive : (isSelected ? gradeColor(choice.grade) : Theme.separator))
                            : Theme.separator,
                        lineWidth: answered && (isSelected || showAsCorrect) ? 1.5 : 1
                    )
            )
        }
        .disabled(answered)
    }

    private func feedback(_ choice: DrillChoice) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                Image(systemName: choice.grade.countsAsCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(gradeColor(choice.grade))
                Text(choice.grade.displayName)
                    .font(Theme.Fonts.secondaryAction)
                    .foregroundStyle(gradeColor(choice.grade))
                Spacer()
            }
            Text(choice.explanation)
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            ActionButton(
                title: index + 1 < activity.questions.count ? "Next question" : "See results",
                role: .primary, accent: accent, identifier: "drill.next"
            ) {
                advance()
            }
        }
        .padding(Theme.Spacing.l)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.backgroundElevated))
    }

    private func gradeColor(_ grade: DrillGradeLabel) -> Color {
        switch grade {
        case .correct: return Theme.positive
        case .strongAlternative: return Theme.positive.opacity(0.85)
        case .defensible: return Theme.caution
        case .inaccuracy: return Theme.caution
        case .mistake: return Theme.danger
        }
    }

    // MARK: - Flow

    private func select(_ choiceIndex: Int) {
        guard selectedChoice == nil, let question else { return }
        selectedChoice = choiceIndex
        let choice = question.choices[choiceIndex]
        earnedCredit += choice.grade.credit
        if choice.grade.countsAsCorrect { correctCount += 1 }
        let tags = question.conceptTag.isEmpty ? activity.conceptTagsFallback : [question.conceptTag]
        training.recordAnswer(conceptTags: tags, correct: choice.grade.countsAsCorrect)
    }

    private func advance() {
        selectedChoice = nil
        if index + 1 < activity.questions.count {
            index += 1
        } else {
            finished = true
            if !reportedScore {
                reportedScore = true
                activity.onFinish(score)
            }
        }
    }

    private var score: Double {
        guard !activity.questions.isEmpty else { return 0 }
        return earnedCredit / Double(activity.questions.count)
    }

    // MARK: - Summary

    private var summary: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()
            Text("\(Int((score * 100).rounded()))%")
                .font(Theme.Fonts.display)
                .foregroundStyle(score >= 0.8 ? Theme.positive : (score >= 0.5 ? Theme.caution : Theme.danger))
                .monospacedDigit()
            Text("\(correctCount) of \(activity.questions.count) answered well")
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            ActionButton(title: "Done", role: .primary, accent: accent, identifier: "drill.done") {
                dismiss()
            }
        }
        .padding(Theme.Spacing.xl)
    }
}
