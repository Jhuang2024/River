import SwiftUI
import RiverKit

/// Session setup: hands, difficulty, assistance. Blinds are 1/2 with 200-chip
/// (100 BB) stacks in the first milestone.
struct QuickCashSetupView: View {
    @EnvironmentObject var game: GameViewModel
    @EnvironmentObject var settingsStore: SettingsStore
    @Binding var path: NavigationPath

    @State private var handsTarget: Int = 20
    @State private var difficulty: BotDifficulty = .beginner

    private let handOptions = [5, 10, 20, 50, 0]

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("Session length") {
                        HStack(spacing: 8) {
                            ForEach(handOptions, id: \.self) { option in
                                choiceChip(
                                    option == 0 ? "∞" : "\(option)",
                                    selected: handsTarget == option
                                ) {
                                    handsTarget = option
                                }
                            }
                        }
                        Text(handsTarget == 0 ? "Play until you leave. Progress saves after every hand." : "About \(handsTarget / 2)–\(handsTarget) minutes.")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                    }

                    section("Opponents") {
                        HStack(spacing: 8) {
                            ForEach(BotDifficulty.allCases, id: \.self) { level in
                                choiceChip(level.displayName, selected: difficulty == level) {
                                    difficulty = level
                                }
                            }
                        }
                        VStack(spacing: 8) {
                            ForEach(BotProfile.defaultLineup(difficulty: difficulty)) { bot in
                                HStack(spacing: 10) {
                                    Image(systemName: bot.symbolName)
                                        .font(.system(size: 14))
                                        .foregroundStyle(settingsStore.accent)
                                        .frame(width: 26)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("\(bot.name) · \(bot.archetype.displayName)")
                                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                                            .foregroundStyle(Theme.textPrimary)
                                        Text(bot.note)
                                            .font(.system(size: 11, design: .rounded))
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.backgroundElevated))
                            }
                        }
                    }

                    section("Assistance") {
                        ForEach(AssistanceLevel.allCases) { level in
                            Button {
                                settingsStore.settings.applyAssistancePreset(level)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(level.displayName)
                                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                                            .foregroundStyle(Theme.textPrimary)
                                        Text(level.summary)
                                            .font(.system(size: 11, design: .rounded))
                                            .foregroundStyle(Theme.textSecondary)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer()
                                    Image(systemName: settingsStore.settings.assistanceLevel == level ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(settingsStore.settings.assistanceLevel == level ? settingsStore.accent : Theme.textSecondary)
                                }
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.backgroundElevated))
                            }
                        }
                    }

                    Text("Blinds 1/2 · 200-chip stacks · fictional chips")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)

                    ActionButton(title: "Deal me in", role: .primary, accent: settingsStore.accent, identifier: "setup.start") {
                        startSession()
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("New session")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            handsTarget = settingsStore.settings.preferredHandsTarget
            difficulty = settingsStore.settings.preferredDifficulty
        }
    }

    private func startSession() {
        settingsStore.settings.preferredHandsTarget = handsTarget
        settingsStore.settings.preferredDifficulty = difficulty
        let config = SessionConfig(
            handsTarget: handsTarget,
            seed: UITestSupport.seedOverride ?? UInt64.random(in: UInt64.min...UInt64.max),
            bots: BotProfile.defaultLineup(difficulty: difficulty)
        )
        path = NavigationPath()
        // The table presents itself as a full-screen cover once the session starts.
        game.startNewSession(config: config)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).sectionHeader()
            content()
        }
    }

    private func choiceChip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(selected ? Color.black : Theme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 11)
                        .fill(selected ? settingsStore.accent : Theme.backgroundElevated)
                )
        }
    }
}
