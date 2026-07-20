import SwiftUI
import RiverKit

/// Browser over all locally stored hands (most recent first).
struct HandHistoryListView: View {
    @EnvironmentObject var game: GameViewModel
    @State private var histories: [HandHistory] = []

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            if histories.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 34))
                        .foregroundStyle(Theme.textSecondary)
                    Text("No hands yet")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Play a session and every hand will be stored here for review.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(histories) { history in
                            NavigationLink(value: Route.replay(history)) {
                                HandHistoryRow(history: history)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("Hand history")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            histories = Array(game.store.loadHistories().reversed())
        }
    }
}
