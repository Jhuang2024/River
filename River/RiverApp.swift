import SwiftUI
import RiverKit

/// Navigation destinations used inside stacks (the table itself is a
/// full-screen cover outside the tab hierarchy, §1).
enum Route: Hashable {
    case setup
    case tournamentSetup
    case results
    case replay(HandHistory)
}

/// Launch-argument support for UI tests: deterministic seeds, instant speed.
enum UITestSupport {
    static var isActive: Bool {
        return ProcessInfo.processInfo.arguments.contains("-uitest")
    }

    static var seedOverride: UInt64? {
        return isActive ? 20260720 : nil
    }
}

@main
struct RiverApp: App {
    @StateObject private var settingsStore: SettingsStore
    @StateObject private var game: GameViewModel
    @StateObject private var training: TrainingStore
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
        gameModel.settingsProvider = { [weak settings] in
            settings?.settings ?? AppSettings()
        }
        if UITestSupport.isActive {
            settings.settings.hasCompletedOnboarding = true
            settings.settings.speed = .instant
            settings.settings.confirmAllIn = false
            settings.settings.protectStrongHands = false
            settings.settings.autoDeal = .manual
        }
        sounds.enabled = settings.settings.soundEnabled && !UITestSupport.isActive
        haptics.enabled = settings.settings.hapticsEnabled
        haptics.intensityScale = settings.settings.hapticLevel.intensity
        _settingsStore = StateObject(wrappedValue: settings)
        _game = StateObject(wrappedValue: gameModel)
        _training = StateObject(wrappedValue: TrainingStore(store: store))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settingsStore)
                .environmentObject(game)
                .environmentObject(training)
                .preferredColorScheme(.dark)
                .onChange(of: settingsStore.settings.soundEnabled) { _, enabled in
                    game.sounds.enabled = enabled
                }
                .onChange(of: settingsStore.settings.hapticsEnabled) { _, enabled in
                    game.haptics.enabled = enabled
                }
                .onChange(of: settingsStore.settings.hapticLevel) { _, level in
                    game.haptics.intensityScale = level.intensity
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .background || newPhase == .inactive {
                        // Autosave on background: an in-progress hand is
                        // abandoned by design; the session resumes at the
                        // last completed hand.
                        game.saveSession()
                    }
                }
        }
    }
}

/// Tab shell (§1): Play, Train, Progress, Review, Profile.
struct RootView: View {
    @EnvironmentObject var game: GameViewModel
    @EnvironmentObject var settingsStore: SettingsStore

    var body: some View {
        TabView {
            PlayHomeView()
                .tabItem { Label("Play", systemImage: "suit.spade.fill") }
            TrainHomeView()
                .tabItem { Label("Train", systemImage: "graduationcap.fill") }
            ProgressHomeView()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
            ReviewListView()
                .tabItem { Label("Review", systemImage: "clock.arrow.circlepath") }
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .tint(settingsStore.accent)
        .fullScreenCover(isPresented: Binding(
            get: { game.isTablePresented },
            set: { presented in
                if !presented {
                    game.exitToMenu()
                }
            }
        )) {
            TableCoverView()
                .environmentObject(settingsStore)
                .environmentObject(game)
        }
        .sheet(isPresented: Binding(
            get: { !settingsStore.settings.hasCompletedOnboarding },
            set: { _ in }
        )) {
            OnboardingView()
                .environmentObject(settingsStore)
                .environmentObject(game)
                .interactiveDismissDisabled(true)
        }
    }
}

/// The immersive table container: its own navigation stack for results and
/// replays, no tab bar (§1).
struct TableCoverView: View {
    @EnvironmentObject var game: GameViewModel
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            TableView(game: game)
                .navigationBarHidden(true)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .results:
                        SessionResultsView(path: $path)
                    case .replay(let history):
                        HandReplayView(history: history)
                    case .setup, .tournamentSetup:
                        // Setup screens live in the Play tab, never inside
                        // the table cover.
                        EmptyView()
                    }
                }
        }
        .tint(settingsStore.accent)
    }
}
