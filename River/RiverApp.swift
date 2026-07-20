import SwiftUI
import RiverKit

/// Navigation destinations.
enum Route: Hashable {
    case table
    case setup
    case results
    case historyList
    case replay(HandHistory)
    case settings
}

@main
struct RiverApp: App {
    @StateObject private var settingsStore: SettingsStore
    @StateObject private var game: GameViewModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = PersistenceStore.standard()
        let settings = SettingsStore(store: store)
        let sounds = SoundPlayer()
        let haptics = HapticsPlayer()
        let gameModel = GameViewModel(
            store: store,
            sounds: sounds,
            haptics: haptics,
            settingsProvider: { AppSettings() }
        )
        _settingsStore = StateObject(wrappedValue: settings)
        _game = StateObject(wrappedValue: gameModel)
        // Rebind so the game always reads live settings.
        gameModel.settingsProvider = { [weak settings] in
            settings?.settings ?? AppSettings()
        }
        sounds.enabled = settings.settings.soundEnabled
        haptics.enabled = settings.settings.hapticsEnabled
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settingsStore)
                .environmentObject(game)
                .preferredColorScheme(.dark)
                .onChange(of: settingsStore.settings.soundEnabled) { _, enabled in
                    game.sounds.enabled = enabled
                }
                .onChange(of: settingsStore.settings.hapticsEnabled) { _, enabled in
                    game.haptics.enabled = enabled
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .background || newPhase == .inactive {
                        // Autosave on background: an in-progress hand is
                        // abandoned by design, the session resumes at the
                        // last completed hand.
                        game.saveSession()
                    }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var game: GameViewModel
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(path: $path)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .table:
                        TableView(game: game)
                    case .setup:
                        QuickCashSetupView(path: $path)
                    case .results:
                        SessionResultsView(path: $path)
                    case .historyList:
                        HandHistoryListView()
                    case .replay(let history):
                        HandReplayView(history: history)
                    case .settings:
                        SettingsView()
                    }
                }
        }
        .tint(Theme.accent)
    }
}
