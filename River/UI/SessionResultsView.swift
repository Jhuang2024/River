import SwiftUI
import RiverKit

/// End-of-session summary: net result, per-hand graph, basic stats.
struct SessionResultsView: View {
    @EnvironmentObject var game: GameViewModel
    @EnvironmentObject var settingsStore: SettingsStore
    @Binding var path: NavigationPath

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    header
                    if let session = game.session, !session.heroNetByHand.isEmpty {
                        netGraph(session.heroNetByHand)
                    }
                    if let stats = game.sessionStats {
                        statsGrid(stats)
                    }
                    recentHands
                    VStack(spacing: 10) {
                        Button {
                            playAgain()
                        } label: {
                            Text("Run it again").riverButton()
                        }
                        Button {
                            game.endSessionAndClear()
                            path = NavigationPath()
                        } label: {
                            Text("Back to menu").riverButton(prominent: false)
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Session results")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
    }

    private var net: Int {
        return game.session?.heroNetTotal ?? 0
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text(net >= 0 ? "+\(net)" : "\(net)")
                .font(.system(size: 46, weight: .black, design: .rounded))
                .foregroundStyle(net >= 0 ? Theme.positive : Theme.danger)
                .monospacedDigit()
            Text("chips over \(game.session?.handsPlayed ?? 0) hands")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            if let bb = game.session?.config.bigBlind, bb > 0, let hands = game.session?.handsPlayed, hands > 0 {
                Text(String(format: "%.1f BB per hand", Double(net) / Double(bb) / Double(hands)))
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.top, 10)
    }

    /// Simple cumulative bar graph of per-hand results.
    private func netGraph(_ perHand: [Int]) -> some View {
        var cumulative: [Int] = []
        var running = 0
        for value in perHand {
            running += value
            cumulative.append(running)
        }
        let maxAbs = max(1, cumulative.map { abs($0) }.max() ?? 1)
        return VStack(alignment: .leading, spacing: 6) {
            Text("CHIP GRAPH")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .kerning(1.2)
                .foregroundStyle(Theme.textSecondary)
            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(cumulative.enumerated()), id: \.offset) { _, value in
                    VStack {
                        if value >= 0 {
                            Spacer(minLength: 0)
                            Rectangle()
                                .fill(Theme.positive)
                                .frame(height: max(2, CGFloat(abs(value)) / CGFloat(maxAbs) * 40))
                            Rectangle().fill(Color.clear).frame(height: 40)
                        } else {
                            Rectangle().fill(Color.clear).frame(height: 40)
                            Rectangle()
                                .fill(Theme.danger)
                                .frame(height: max(2, CGFloat(abs(value)) / CGFloat(maxAbs) * 40))
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            .frame(height: 84)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.backgroundElevated))
    }

    private func statsGrid(_ stats: SessionStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SESSION STATS")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .kerning(1.2)
                .foregroundStyle(Theme.textSecondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                statCell("Hands won", "\(stats.handsWon)/\(stats.handsPlayed)")
                statCell("VPIP", String(format: "%.0f%%", stats.vpipPercent))
                statCell("PFR", String(format: "%.0f%%", stats.pfrPercent))
                statCell("Showdowns", "\(stats.showdownsWon)/\(stats.showdownsSeen)")
                statCell("Biggest pot", "\(stats.biggestPotWon)")
                statCell("Net", "\(stats.netChips)")
            }
            Text("Small sample — treat these as a snapshot, not a verdict.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.backgroundElevated))
    }

    private func statCell(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var recentHands: some View {
        let histories = Array(game.store.loadHistories().suffix(game.session?.handsPlayed ?? 20).reversed())
        return VStack(alignment: .leading, spacing: 10) {
            Text("HANDS")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .kerning(1.2)
                .foregroundStyle(Theme.textSecondary)
            ForEach(histories) { history in
                NavigationLink(value: Route.replay(history)) {
                    HandHistoryRow(history: history)
                }
            }
        }
    }

    private func playAgain() {
        guard let previous = game.session else { return }
        var config = previous.config
        config.seed = UInt64.random(in: UInt64.min...UInt64.max)
        game.startNewSession(config: config)
        path = NavigationPath()
        path.append(Route.table)
    }
}

/// A single hand row shared between results and the history browser.
struct HandHistoryRow: View {
    let history: HandHistory

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Hand #\(history.handNumber)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(history.wentToShowdown ? "Showdown" : "No showdown") · pot \(history.potSize)")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Text(history.heroNet >= 0 ? "+\(history.heroNet)" : "\(history.heroNet)")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(history.heroNet >= 0 ? Theme.positive : Theme.danger)
                .monospacedDigit()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.backgroundElevated))
    }
}
