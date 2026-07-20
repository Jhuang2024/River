import SwiftUI
import RiverKit

/// First launch (§3): three useful questions, no account, no feature tour.
/// Answers only configure the starting experience.
struct OnboardingView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var game: GameViewModel

    enum Experience: String, CaseIterable, Identifiable {
        case never = "Never"
        case aLittle = "A little"
        case regularly = "Regularly"
        var id: String { rawValue }
    }

    enum Goal: String, CaseIterable, Identifiable {
        case rules = "The rules"
        case mistakes = "Stop obvious mistakes"
        case strategy = "Play stronger strategy"
        var id: String { rawValue }
    }

    @State private var experience: Experience = .aLittle
    @State private var help: AssistanceLevel = .hints
    @State private var goal: Goal = .mistakes

    private var accent: Color { settingsStore.accent }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("RIVER")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .kerning(8)
                            .foregroundStyle(Theme.textPrimary)
                        Text("Three quick questions — no account, nothing leaves your phone.")
                            .font(Theme.Fonts.body)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.top, Theme.Spacing.xl)

                    question("Have you played Texas Hold'em before?") {
                        ForEach(Experience.allCases) { option in
                            chip(option.rawValue, selected: experience == option) { experience = option }
                        }
                    }
                    question("How much help do you want during hands?") {
                        ForEach(AssistanceLevel.allCases) { option in
                            chip(option.displayName, selected: help == option) { help = option }
                        }
                    }
                    question("What do you want to work on first?") {
                        ForEach(Goal.allCases) { option in
                            chip(option.rawValue, selected: goal == option) { goal = option }
                        }
                    }

                    ActionButton(title: "Deal me in", role: .primary, accent: accent, identifier: "onboarding.start") {
                        finish(startGame: true)
                    }
                    Button {
                        finish(startGame: false)
                    } label: {
                        Text("Just take me to the app")
                            .font(Theme.Fonts.secondaryAction)
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.bottom, Theme.Spacing.xl)
                }
                .padding(Theme.Spacing.xl)
            }
        }
    }

    private func question(_ title: String, @ViewBuilder options: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(title)
                .font(Theme.Fonts.secondaryAction)
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: Theme.Spacing.s) {
                options()
            }
        }
    }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(selected ? Color.black : Theme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 11).fill(selected ? accent : Theme.backgroundElevated))
        }
    }

    private func finish(startGame: Bool) {
        var settings = settingsStore.settings
        // Beginners get Guided help and slower defaults regardless of the
        // help answer only when they have never played.
        if experience == .never {
            settings.applyAssistancePreset(.guided)
            settings.preferredDifficulty = .beginner
            settings.preferredHandsTarget = 10
        } else {
            settings.applyAssistancePreset(help)
            settings.preferredDifficulty = experience == .regularly ? .intermediate : .beginner
        }
        if goal == .strategy {
            settings.preferredDifficulty = .intermediate
        }
        settings.hasCompletedOnboarding = true
        settingsStore.settings = settings

        if startGame {
            let config = SessionConfig(
                handsTarget: settings.preferredHandsTarget,
                seed: UITestSupport.seedOverride ?? UInt64.random(in: UInt64.min...UInt64.max),
                bots: BotProfile.defaultLineup(difficulty: settings.preferredDifficulty)
            )
            game.startNewSession(config: config)
        }
    }
}
