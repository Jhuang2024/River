import SwiftUI
import RiverKit

/// Sit-and-Go setup (§19): six players, rising blinds, fictional prize pool
/// paid to the top two. Structure and opposition are the only knobs.
struct TournamentSetupView: View {
    @EnvironmentObject var game: GameViewModel
    @EnvironmentObject var settingsStore: SettingsStore
    @Binding var path: NavigationPath

    @State private var structure: TournamentStructure = .standard
    @State private var difficulty: BotDifficulty = .beginner

    private var accent: Color { settingsStore.accent }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    section("Structure") {
                        ForEach(TournamentStructure.all) { option in
                            Button {
                                structure = option
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(option.name)
                                            .font(Theme.Fonts.secondaryAction)
                                            .foregroundStyle(Theme.textPrimary)
                                        Text(option.summary)
                                            .font(Theme.Fonts.caption)
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: structure.id == option.id ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(structure.id == option.id ? accent : Theme.textSecondary)
                                }
                                .padding(Theme.Spacing.m)
                                .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.backgroundElevated))
                            }
                        }
                    }

                    section("Opponents") {
                        HStack(spacing: 8) {
                            ForEach(BotDifficulty.allCases, id: \.self) { level in
                                choiceChip(level.displayName, selected: difficulty == level) {
                                    difficulty = level
                                }
                            }
                        }
                    }

                    section("Payouts") {
                        let payouts = structure.payoutFractions
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(payouts.enumerated()), id: \.offset) { place, fraction in
                                HStack {
                                    Text(place == 0 ? "1st" : "2nd")
                                        .font(Theme.Fonts.secondaryAction)
                                        .foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    Text("\(Int((600.0 * fraction).rounded())) chips")
                                        .font(Theme.Fonts.stackValue)
                                        .monospacedDigit()
                                        .foregroundStyle(accent)
                                }
                            }
                            Text("Six players · winner takes the trophy · chips are fictional")
                                .font(Theme.Fonts.caption)
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .padding(Theme.Spacing.m)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.backgroundElevated))
                    }

                    Text("Blinds rise every \(structure.handsPerLevel) hands. Short stacks change correct strategy: the push-fold lessons in the Tournament academy apply directly here.")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textSecondary)

                    ActionButton(title: "Take my seat", role: .primary, accent: accent, identifier: "tournament.start") {
                        start()
                    }
                }
                .padding(Theme.Spacing.xl)
            }
            .readableColumn()
        }
        .navigationTitle("Sit & Go")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func start() {
        path = NavigationPath()
        game.startTournament(
            structure: structure,
            difficulty: difficulty,
            seed: UITestSupport.seedOverride ?? UInt64.random(in: UInt64.min...UInt64.max)
        )
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
                        .fill(selected ? accent : Theme.backgroundElevated)
                )
        }
    }
}
