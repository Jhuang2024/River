import SwiftUI
import RiverKit

/// Review tab (§1): recent hands with filters. Each row opens the replay.
struct ReviewListView: View {
    @EnvironmentObject var game: GameViewModel
    @EnvironmentObject var settingsStore: SettingsStore

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case bigPots = "Big pots"
        case allIns = "All-ins"
        case showdowns = "Showdowns"
        case wins = "Won"
        case losses = "Lost"

        var id: String { rawValue }
    }

    @State private var filter: Filter = .all
    @State private var histories: [HandHistory] = []

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                VStack(spacing: 0) {
                    filterBar
                    if filtered.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            LazyVStack(spacing: Theme.Spacing.s) {
                                ForEach(filtered) { history in
                                    NavigationLink(value: history) {
                                        HandHistoryRow(history: history)
                                    }
                                }
                            }
                            .padding(Theme.Spacing.l)
                        }
                    }
                }
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: HandHistory.self) { history in
                HandReplayView(history: history)
            }
            .onAppear {
                histories = Array(game.store.loadHistories().reversed())
            }
        }
        .tint(settingsStore.accent)
    }

    private var filtered: [HandHistory] {
        switch filter {
        case .all:
            return histories
        case .bigPots:
            return histories.filter { $0.potSize >= $0.bigBlind * 30 }
        case .allIns:
            return histories.filter { history in
                history.events.contains { event in
                    if case .action(_, _, _, _, _, let isAllIn) = event { return isAllIn }
                    return false
                }
            }
        case .showdowns:
            return histories.filter { $0.wentToShowdown }
        case .wins:
            return histories.filter { $0.heroNet > 0 }
        case .losses:
            return histories.filter { $0.heroNet < 0 }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(Filter.allCases) { option in
                    Button {
                        filter = option
                    } label: {
                        Text(option.rawValue)
                            .font(Theme.Fonts.secondaryAction)
                            .foregroundStyle(filter == option ? Color.black : Theme.textPrimary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(filter == option ? settingsStore.accent : Theme.backgroundElevated)
                            )
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.s)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.s) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 34))
                .foregroundStyle(Theme.textTertiary)
            Text(histories.isEmpty ? "No hands yet" : "Nothing matches this filter")
                .font(Theme.Fonts.screenTitle)
                .foregroundStyle(Theme.textPrimary)
            Text(histories.isEmpty
                 ? "Play a session and every hand is stored here for review."
                 : "Try a different filter, or play more hands.")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }
}
