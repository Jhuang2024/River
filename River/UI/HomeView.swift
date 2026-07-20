import SwiftUI
import RiverKit

struct HomeView: View {
    @EnvironmentObject var game: GameViewModel
    @EnvironmentObject var settingsStore: SettingsStore
    @Binding var path: NavigationPath

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                // Wordmark.
                VStack(spacing: 6) {
                    Text("RIVER")
                        .font(.system(size: 52, weight: .black, design: .rounded))
                        .kerning(14)
                        .foregroundStyle(Theme.textPrimary)
                    Rectangle()
                        .fill(Theme.accent)
                        .frame(width: 130, height: 2)
                    Text("No-Limit Hold'em, played seriously")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 4)
                }
                Spacer()
                VStack(spacing: 12) {
                    if game.hasSavedSession {
                        Button {
                            game.resumeSavedSession()
                            path.append(Route.table)
                        } label: {
                            Label("Continue session", systemImage: "play.fill")
                                .riverButton()
                        }
                    }
                    Button {
                        path.append(Route.setup)
                    } label: {
                        Label("Quick cash game", systemImage: "suit.spade.fill")
                            .riverButton(prominent: !game.hasSavedSession)
                    }
                    Button {
                        path.append(Route.historyList)
                    } label: {
                        Label("Hand history", systemImage: "clock.arrow.circlepath")
                            .riverButton(prominent: false)
                    }
                    Button {
                        path.append(Route.settings)
                    } label: {
                        Label("Settings", systemImage: "slider.horizontal.3")
                            .riverButton(prominent: false)
                    }
                }
                .padding(.horizontal, 28)
                Spacer()
                Text("Fictional chips only. Offline. Private.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
                    .padding(.bottom, 14)
            }
        }
        .navigationBarHidden(true)
    }
}
