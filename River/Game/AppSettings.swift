import Foundation
import SwiftUI
import RiverKit

/// Table pacing presets. Big all-ins and showdowns still get brief drama pauses.
enum GameSpeed: String, Codable, CaseIterable, Identifiable {
    case cinematic
    case standard
    case fast
    case instant

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cinematic: return "Cinematic"
        case .standard: return "Standard"
        case .fast: return "Fast"
        case .instant: return "Instant"
        }
    }

    /// Multiplier applied to all motion-system base durations.
    var motionScale: Double {
        switch self {
        case .cinematic: return 1.45
        case .standard: return 1.0
        case .fast: return 0.5
        case .instant: return 0.12
        }
    }

    /// Seconds a bot appears to "think" before acting.
    var botDelay: Double {
        switch self {
        case .cinematic: return 1.1
        case .standard: return 0.65
        case .fast: return 0.28
        case .instant: return 0.05
        }
    }

    /// Pause when new board cards land.
    var dealPause: Double {
        switch self {
        case .cinematic: return 0.8
        case .standard: return 0.5
        case .fast: return 0.22
        case .instant: return 0.04
        }
    }

    /// Pause on showdown reveals and pot pushes.
    var showdownPause: Double {
        switch self {
        case .cinematic: return 1.5
        case .standard: return 1.0
        case .fast: return 0.55
        case .instant: return 0.15
        }
    }
}

/// Teaching styles: presets over the individual assistance toggles.
enum AssistanceLevel: String, Codable, CaseIterable, Identifiable {
    case guided
    case hints
    case pure

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .guided: return "Guided"
        case .hints: return "Hints"
        case .pure: return "Pure"
        }
    }

    var summary: String {
        switch self {
        case .guided: return "Explains everything as you play. Best for learning the game."
        case .hints: return "Clean table, help on request. Ask for advice when you want it."
        case .pure: return "No help during the hand. Analysis stays available afterwards."
        }
    }
}

/// Card face rendering styles (§21).
enum DeckStyle: String, Codable, CaseIterable, Identifiable {
    case classic
    case minimal
    case highContrast
    case fourColor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .minimal: return "Minimal"
        case .highContrast: return "High Contrast"
        case .fourColor: return "Four Colour"
        }
    }
}

/// Player-selected accent colour (§4). One accent at a time.
enum AccentChoice: String, Codable, CaseIterable, Identifiable {
    case electricBlue
    case deepRed
    case emerald
    case amber
    case violet
    case ice

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .electricBlue: return "Electric Blue"
        case .deepRed: return "Deep Red"
        case .emerald: return "Emerald"
        case .amber: return "Amber"
        case .violet: return "Violet"
        case .ice: return "Ice"
        }
    }

    var color: Color {
        switch self {
        case .electricBlue: return Color(red: 0.25, green: 0.62, blue: 0.96)
        case .deepRed: return Color(red: 0.85, green: 0.30, blue: 0.28)
        case .emerald: return Color(red: 0.26, green: 0.72, blue: 0.50)
        case .amber: return Color(red: 0.88, green: 0.70, blue: 0.36)
        case .violet: return Color(red: 0.64, green: 0.50, blue: 0.90)
        case .ice: return Color(red: 0.85, green: 0.90, blue: 0.95)
        }
    }
}

/// Hand-completion pacing (§25).
enum AutoDealSetting: String, Codable, CaseIterable, Identifiable {
    case manual
    case oneSecond
    case twoSeconds
    case threeSeconds

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .manual: return "Manual"
        case .oneSecond: return "Auto · 1s"
        case .twoSeconds: return "Auto · 2s"
        case .threeSeconds: return "Auto · 3s"
        }
    }

    /// nil = wait for the player to tap Next hand.
    var delay: Double? {
        switch self {
        case .manual: return nil
        case .oneSecond: return 1
        case .twoSeconds: return 2
        case .threeSeconds: return 3
        }
    }
}

/// Optional decision timer (§24). Expiry checks when free, otherwise folds.
enum DecisionTimerSetting: String, Codable, CaseIterable, Identifiable {
    case off
    case sixty
    case thirty
    case fifteen

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .sixty: return "60s"
        case .thirty: return "30s"
        case .fifteen: return "15s"
        }
    }

    var seconds: Double? {
        switch self {
        case .off: return nil
        case .sixty: return 60
        case .thirty: return 30
        case .fifteen: return 15
        }
    }
}

/// Hero stack display mode (§8) - cycled by tapping the stack.
enum StackDisplayMode: String, Codable, CaseIterable {
    case chips
    case bigBlinds
    case both

    var next: StackDisplayMode {
        switch self {
        case .chips: return .bigBlinds
        case .bigBlinds: return .both
        case .both: return .chips
        }
    }
}


/// Hand-history retention (§53). Bookmarked hands are always preserved.
enum HistoryRetention: String, Codable, CaseIterable, Identifiable {
    case all
    case last500
    case last2000

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "Keep everything"
        case .last500: return "Last 500 hands"
        case .last2000: return "Last 2,000 hands"
        }
    }

    var detailedLimit: Int {
        switch self {
        case .all: return 100_000
        case .last500: return 500
        case .last2000: return 2000
        }
    }
}

/// Unlockable table felt themes (§42). Purely cosmetic.
enum TableThemeChoice: String, Codable, CaseIterable, Identifiable {
    case classic
    case midnight
    case crimson
    case slate

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "Classic Felt"
        case .midnight: return "Midnight"
        case .crimson: return "Crimson Room"
        case .slate: return "Slate"
        }
    }
}

/// Unlockable chip styles (§42). Purely cosmetic.
enum ChipStyleChoice: String, Codable, CaseIterable, Identifiable {
    case azure
    case ruby
    case brass
    case mono

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .azure: return "Azure"
        case .ruby: return "Ruby"
        case .brass: return "Brass"
        case .mono: return "Monochrome"
        }
    }
}

/// Haptic intensity levels (§48).
enum HapticLevel: String, Codable, CaseIterable, Identifiable {
    case off
    case minimal
    case standard
    case strong

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .minimal: return "Minimal"
        case .standard: return "Standard"
        case .strong: return "Strong"
        }
    }

    /// Multiplier fed to HapticsPlayer.intensityScale.
    var intensity: Double {
        switch self {
        case .off: return 0
        case .minimal: return 0.5
        case .standard: return 1.0
        case .strong: return 1.3
        }
    }
}

/// All local preferences. Stored as versioned JSON on device; nothing leaves
/// the phone. Decoding is field-by-field resilient so adding settings never
/// wipes existing ones.
struct AppSettings: Codable, Equatable {
    var speed: GameSpeed = .standard
    var soundEnabled: Bool = true
    var hapticsEnabled: Bool = true
    var deckStyle: DeckStyle = .classic
    var accent: AccentChoice = .amber
    var assistanceLevel: AssistanceLevel = .hints
    // Individual assistance toggles (presets set sensible defaults, each can
    // be flipped independently afterwards).
    var showHandStrength: Bool = true
    var showPotOdds: Bool = true
    var showRequiredEquity: Bool = false
    var showBoardTexture: Bool = false
    var allowRecommendations: Bool = true
    var revealFoldedBotCards: Bool = false
    // Safety and pacing.
    var confirmAllIn: Bool = true
    var protectStrongHands: Bool = true
    var swipeDownToFold: Bool = false
    var autoDeal: AutoDealSetting = .manual
    var decisionTimer: DecisionTimerSetting = .off
    // Cosmetics & storage (§42, §53).
    var tableTheme: TableThemeChoice = .classic
    var chipStyle: ChipStyleChoice = .azure
    var historyRetention: HistoryRetention = .last2000
    var hapticLevel: HapticLevel = .standard
    // Layout and display.
    var leftHandedMode: Bool = false
    var stackDisplay: StackDisplayMode = .chips
    var showSeedAfterHand: Bool = false
    // Session setup memory.
    var preferredHandsTarget: Int = 20
    var preferredDifficulty: BotDifficulty = .beginner
    var hasCompletedOnboarding: Bool = false

    init() {}

    mutating func applyAssistancePreset(_ level: AssistanceLevel) {
        assistanceLevel = level
        switch level {
        case .guided:
            showHandStrength = true
            showPotOdds = true
            showRequiredEquity = true
            showBoardTexture = true
            allowRecommendations = true
            protectStrongHands = true
        case .hints:
            showHandStrength = true
            showPotOdds = false
            showRequiredEquity = false
            showBoardTexture = false
            allowRecommendations = true
        case .pure:
            showHandStrength = false
            showPotOdds = false
            showRequiredEquity = false
            showBoardTexture = false
            allowRecommendations = false
        }
    }

    // MARK: - Resilient Codable

    private enum CodingKeys: String, CodingKey {
        case speed, soundEnabled, hapticsEnabled, deckStyle, accent, assistanceLevel
        case showHandStrength, showPotOdds, showRequiredEquity, showBoardTexture
        case allowRecommendations, revealFoldedBotCards
        case confirmAllIn, protectStrongHands, swipeDownToFold, autoDeal, decisionTimer
        case tableTheme, chipStyle, historyRetention, hapticLevel
        case leftHandedMode, stackDisplay, showSeedAfterHand
        case preferredHandsTarget, preferredDifficulty, hasCompletedOnboarding
    }

    /// Reads one field, keeping the default when the key is absent or invalid.
    private static func field<T: Decodable>(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys, _ fallback: T) -> T {
        // try? flattens the nested optional: nil here means the key was
        // absent OR held an invalid value - either way, keep the default.
        if let value = try? container.decodeIfPresent(T.self, forKey: key) {
            return value
        }
        return fallback
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        speed = AppSettings.field(c, .speed, .standard)
        soundEnabled = AppSettings.field(c, .soundEnabled, true)
        hapticsEnabled = AppSettings.field(c, .hapticsEnabled, true)
        deckStyle = AppSettings.field(c, .deckStyle, .classic)
        accent = AppSettings.field(c, .accent, .amber)
        assistanceLevel = AppSettings.field(c, .assistanceLevel, .hints)
        showHandStrength = AppSettings.field(c, .showHandStrength, true)
        showPotOdds = AppSettings.field(c, .showPotOdds, true)
        showRequiredEquity = AppSettings.field(c, .showRequiredEquity, false)
        showBoardTexture = AppSettings.field(c, .showBoardTexture, false)
        allowRecommendations = AppSettings.field(c, .allowRecommendations, true)
        revealFoldedBotCards = AppSettings.field(c, .revealFoldedBotCards, false)
        confirmAllIn = AppSettings.field(c, .confirmAllIn, true)
        protectStrongHands = AppSettings.field(c, .protectStrongHands, true)
        swipeDownToFold = AppSettings.field(c, .swipeDownToFold, false)
        autoDeal = AppSettings.field(c, .autoDeal, .manual)
        decisionTimer = AppSettings.field(c, .decisionTimer, .off)
        tableTheme = AppSettings.field(c, .tableTheme, .classic)
        chipStyle = AppSettings.field(c, .chipStyle, .azure)
        historyRetention = AppSettings.field(c, .historyRetention, .last2000)
        hapticLevel = AppSettings.field(c, .hapticLevel, .standard)
        leftHandedMode = AppSettings.field(c, .leftHandedMode, false)
        stackDisplay = AppSettings.field(c, .stackDisplay, .chips)
        showSeedAfterHand = AppSettings.field(c, .showSeedAfterHand, false)
        preferredHandsTarget = AppSettings.field(c, .preferredHandsTarget, 20)
        preferredDifficulty = AppSettings.field(c, .preferredDifficulty, .beginner)
        hasCompletedOnboarding = AppSettings.field(c, .hasCompletedOnboarding, false)
    }
}

/// Observable wrapper that persists on every change.
@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            if settings != oldValue {
                try? store.save(settings, as: PersistenceStore.FileName.settings)
            }
        }
    }

    private let store: PersistenceStore

    init(store: PersistenceStore) {
        self.store = store
        self.settings = store.load(AppSettings.self, from: PersistenceStore.FileName.settings) ?? AppSettings()
    }

    var accent: Color {
        return settings.accent.color
    }
}
