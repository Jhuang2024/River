import SwiftUI
import RiverKit

/// Play tab (§31): one primary action, light recent-result context. Modes
/// that don't exist yet are not shown.
struct PlayHomeView: View {
    @EnvironmentObject var game: GameViewModel
    @EnvironmentObject var settingsStore: SettingsStore
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
                        recentModule
                        Text("Fictional chips only · Offline · Private")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(Theme.Spacing.xl)
                }
            }
            .navigationDestination(for: Route.self) { route in
                if case .setup = route {
                    QuickCashSetupView(path: $path)
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
            if game.hasSavedSession {
                ActionButton(title: "Continue session", role: .primary, accent: accent, identifier: "play.continue") {
                    game.resumeSavedSession()
                }
                ActionButton(title: "New cash game", role: .secondary, accent: accent, identifier: "play.quickCash") {
                    path.append(Route.setup)
                }
            } else {
                ActionButton(title: "Quick cash game", role: .primary, accent: accent, identifier: "play.quickCash") {
                    path.append(Route.setup)
                }
            }
            Text("Six-max no-limit hold'em against five AI opponents.\nSit-and-Go, Stakes Ladder and Daily Challenge arrive in later updates.")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.l)
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
                    metric("Hands", "\(stats.handsPlayed)")
                    metric("Net", stats.netChips >= 0 ? "+\(stats.netChips)" : "\(stats.netChips)",
                           color: stats.netChips >= 0 ? Theme.positive : Theme.danger)
                    metric("VPIP", String(format: "%.0f%%", stats.vpipPercent))
                    metric("Won", "\(stats.handsWon)")
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
            return "You're entering \(Int(stats.vpipPercent))% of pots — tightening up preflop usually pays."
        }
        if stats.pfrPercent < stats.vpipPercent / 2 {
            return "You call preflop far more than you raise — consider raising your playable hands."
        }
        return "Solid recent play. Review your biggest pots to keep improving."
    }
}
