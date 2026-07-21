import SwiftUI
import RiverKit

/// Play tab (§31): one primary action, light recent-result context. Modes
/// that don't exist yet are not shown.
struct PlayHomeView: View {
    @EnvironmentObject var game: GameViewModel
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var casino: CasinoStore
    @State private var path = NavigationPath()

    private var accent: Color { settingsStore.accent }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: Theme.Spacing.xl) {
                        wordmark
                        primaryCard
                        beginnerCard
                        recentModule
                        Text("Fictional chips only · Offline · Private")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(Theme.Spacing.xl)
                }
                .readableColumn()
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .setup:
                    QuickCashSetupView(path: $path)
                case .tournamentSetup:
                    TournamentSetupView(path: $path)
                default:
                    EmptyView()
                }
            }
            .navigationDestination(for: String.self) { destination in
                switch destination {
                case "campaign":
                    CampaignView()
                case "casino":
                    CasinoFloorView()
                case CasinoGameKind.blackjack.rawValue:
                    BlackjackView(casino: casino)
                case CasinoGameKind.roulette.rawValue:
                    RouletteView(casino: casino)
                case CasinoGameKind.plinko.rawValue:
                    PlinkoView(casino: casino)
                case "casino-history":
                    CasinoHistoryView()
                case "counting-trainer":
                    CountingTrainerView()
                case "casino-settings", "blackjack-settings", "roulette-settings", "plinko-settings":
                    CasinoSettingsView()
                case "glossary":
                    GlossaryView()
                default:
                    EmptyView()
                }
            }
        }
        .tint(accent)
    }

    private var wordmark: some View {
        VStack(spacing: 6) {
            Text("RIVER")
                .font(.system(size: 44, weight: .black, design: .rounded))
                .kerning(12)
                .foregroundStyle(Theme.textPrimary)
            Rectangle()
                .fill(accent)
                .frame(width: 110, height: 2)
            Text("No-Limit Hold'em, played seriously")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 2)
        }
        .padding(.top, Theme.Spacing.l)
    }

    private var primaryCard: some View {
        VStack(spacing: Theme.Spacing.m) {
            if game.hasSavedTournament {
                ActionButton(title: "Continue tournament", subtitle: "Pick up where you left off",
                             role: .primary, accent: accent, identifier: "play.continueTournament") {
                    game.resumeSavedTournament()
                }
            }
            if game.hasSavedSession {
                ActionButton(title: "Continue playing", subtitle: "Return to your saved poker table",
                             role: game.hasSavedTournament ? .secondary : .primary,
                             accent: accent, identifier: "play.continue") {
                    game.resumeSavedSession()
                }
                ActionButton(title: "New poker table", subtitle: "Start a fresh game",
                             role: .secondary, accent: accent, identifier: "play.quickCash") {
                    path.append(Route.setup)
                }
            } else {
                ActionButton(title: "Play poker", subtitle: "Sit down at a table and go",
                             role: game.hasSavedTournament ? .secondary : .primary,
                             accent: accent, identifier: "play.quickCash") {
                    path.append(Route.setup)
                }
            }
            ActionButton(title: "Tournament", subtitle: "6 players, last one standing wins",
                         role: .secondary, accent: accent, identifier: "play.tournament") {
                path.append(Route.tournamentSetup)
            }
            ActionButton(title: "Stakes Ladder", subtitle: "A campaign: climb 7 tiers by playing well",
                         role: .secondary, accent: accent, identifier: "play.campaign") {
                path.append("campaign")
            }
            ActionButton(title: "Casino Floor", subtitle: "Blackjack, Roulette and Plinko",
                         role: .quiet, accent: accent, identifier: "play.casino") {
                path.append("casino")
            }
        }
        .padding(Theme.Spacing.l)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.sheet).fill(Theme.backgroundElevated.opacity(0.6)))
    }

    /// First-timers get a clear path: lessons and a plain-words glossary.
    private var beginnerCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("NEW TO POKER?").sectionHeader()
            Text("Start with the Foundations lessons in the Train tab. They explain everything from zero, and you can look up any word in the glossary at any time.")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                path.append("glossary")
            } label: {
                Label("Open the glossary", systemImage: "book.closed")
                    .font(Theme.Fonts.secondaryAction)
                    .foregroundStyle(accent)
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.sheet).fill(Theme.backgroundElevated.opacity(0.6)))
    }

    @ViewBuilder
    private var recentModule: some View {
        let histories = game.store.loadHistories()
        if !histories.isEmpty {
            let recent = Array(histories.suffix(50))
            let stats = SessionStats.compute(histories: recent, seat: heroSeatIndex)
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("RECENT FORM").sectionHeader()
                HStack(spacing: Theme.Spacing.xl) {
                    metric("Hands played", "\(stats.handsPlayed)")
                    metric("Chips won/lost", stats.netChips >= 0 ? "+\(stats.netChips)" : "\(stats.netChips)",
                           color: stats.netChips >= 0 ? Theme.positive : Theme.danger)
                    metric("Pots entered", String(format: "%.0f%%", stats.vpipPercent))
                    metric("Hands won", "\(stats.handsWon)")
                }
                Text(suggestion(stats: stats))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.sheet).fill(Theme.backgroundElevated.opacity(0.6)))
        }
    }

    private func metric(_ label: String, _ value: String, color: Color = Theme.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Theme.Fonts.potValue)
                .monospacedDigit()
                .foregroundStyle(color)
            Text(label)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    /// One relevant improvement pointer, hedged for small samples (§34).
    private func suggestion(stats: SessionStats) -> String {
        if stats.handsPlayed < 30 {
            return "Play more hands to build a meaningful sample."
        }
        if stats.vpipPercent > 35 {
            return "You're entering \(Int(stats.vpipPercent))% of pots: tightening up preflop usually pays."
        }
        if stats.pfrPercent < stats.vpipPercent / 2 {
            return "You call preflop far more than you raise: consider raising your playable hands."
        }
        return "Solid recent play. Review your biggest pots to keep improving."
    }
}
