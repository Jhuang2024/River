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
                    if let tournament = game.tournament, game.mode == .tournament {
                        tournamentHeader(tournament)
                        tournamentLadder(tournament)
                    } else {
                        header
                        if let session = game.session, !session.heroNetByHand.isEmpty {
                            netGraph(session.heroNetByHand)
                        }
                        if let stats = game.sessionStats {
                            statsGrid(stats)
                        }
                    }
                    recentHands
                    VStack(spacing: 10) {
                        ActionButton(title: "Run it again", role: .primary, accent: settingsStore.accent, identifier: "results.again") {
                            playAgain()
                        }
                        ActionButton(title: "Back to menu", role: .secondary, accent: settingsStore.accent, identifier: "results.menu") {
                            game.endSessionAndClear()
                            path = NavigationPath()
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle(game.mode == .tournament ? "Tournament result" : "Session results")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
    }

    private var net: Int {
        return game.session?.heroNetTotal ?? 0
    }

    // MARK: - Tournament summary (§21)

    private func placeText(_ place: Int?) -> String {
        switch place {
        case 1: return "1st place"
        case 2: return "2nd place"
        case 3: return "3rd place"
        case .some(let value): return "\(value)th place"
        case nil: return "Still alive"
        }
    }

    private func tournamentHeader(_ tournament: TournamentState) -> some View {
        let place = tournament.place(of: heroSeatIndex)
        let prize = tournament.prize(of: heroSeatIndex)
        return VStack(spacing: 6) {
            Image(systemName: place == 1 ? "trophy.fill" : (prize > 0 ? "medal.fill" : "flag.checkered"))
                .font(.system(size: 40))
                .foregroundStyle(place == 1 ? Theme.caution : (prize > 0 ? Theme.positive : Theme.textSecondary))
            Text(placeText(place))
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            if prize > 0 {
                Text("+\(prize) fictional chips")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.positive)
            }
            Text("\(tournament.handsPlayed) hands · reached level \(tournament.currentLevelIndex + 1) (\(tournament.currentLevel.smallBlind)/\(tournament.currentLevel.bigBlind))")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, 10)
    }

    /// Final standings, best known order: survivors by stack, then busts in
    /// reverse elimination order.
    private func tournamentLadder(_ tournament: TournamentState) -> some View {
        let names = tournament.playerNames
        var order: [(seat: Int, label: String)] = []
        let survivors = tournament.stacks.indices
            .filter { tournament.stacks[$0] > 0 }
            .sorted { tournament.stacks[$0] > tournament.stacks[$1] }
        for seat in survivors {
            let place = tournament.place(of: seat)
            order.append((seat, place.map { placeText($0) } ?? "\(tournament.stacks[seat]) chips"))
        }
        for seat in tournament.eliminationOrder.reversed() {
            order.append((seat, placeText(tournament.place(of: seat))))
        }
        return VStack(alignment: .leading, spacing: 8) {
            Text("STANDINGS")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .kerning(1.2)
                .foregroundStyle(Theme.textSecondary)
            ForEach(Array(order.enumerated()), id: \.offset) { rank, entry in
                HStack {
                    Text("\(rank + 1).")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 24, alignment: .trailing)
                    Text(entry.seat == heroSeatIndex ? "You" : (names.indices.contains(entry.seat) ? names[entry.seat] : "Seat \(entry.seat + 1)"))
                        .font(.system(size: 13, weight: entry.seat == heroSeatIndex ? .bold : .regular, design: .rounded))
                        .foregroundStyle(entry.seat == heroSeatIndex ? settingsStore.accent : Theme.textPrimary)
                    Spacer()
                    let prize = tournament.prize(of: entry.seat)
                    if prize > 0 {
                        Text("+\(prize)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.positive)
                    }
                    Text(entry.label)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.backgroundElevated))
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
        let handCount = game.mode == .tournament ? (game.tournament?.handsPlayed ?? 20) : (game.session?.handsPlayed ?? 20)
        let histories = Array(game.store.loadHistories().suffix(handCount).reversed())
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
        if game.mode == .tournament, let previous = game.tournament {
            var config = previous.config
            config.seed = UITestSupport.seedOverride ?? UInt64.random(in: UInt64.min...UInt64.max)
            path = NavigationPath()
            game.startTournament(config: config)
            return
        }
        guard let previous = game.session else { return }
        var config = previous.config
        config.seed = UITestSupport.seedOverride ?? UInt64.random(in: UInt64.min...UInt64.max)
        // Pop back to the table (root of the cover's stack) and start fresh.
        path = NavigationPath()
        game.startNewSession(config: config)
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
