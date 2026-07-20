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
        case .cinematic: return 0.9
        case .standard: return 0.55
        case .fast: return 0.25
        case .instant: return 0.05
        }
    }

    /// Pause on showdown reveals and pot pushes.
    var showdownPause: Double {
        switch self {
        case .cinematic: return 1.6
        case .standard: return 1.1
        case .fast: return 0.6
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

/// All local preferences. Stored as versioned JSON on device; nothing leaves
/// the phone.
struct AppSettings: Codable, Equatable {
    var speed: GameSpeed = .standard
    var soundEnabled: Bool = true
    var hapticsEnabled: Bool = true
    var fourColorDeck: Bool = false
    var assistanceLevel: AssistanceLevel = .hints
    /// Individual assistance toggles (the presets set sensible defaults, but
    /// each can be flipped independently).
    var showHandStrength: Bool = true
    var showPotOdds: Bool = true
    var allowRecommendations: Bool = true
    var revealFoldedBotCards: Bool = false
    var confirmAllIn: Bool = true
    var showSeedAfterHand: Bool = false
    /// Session setup memory.
    var preferredHandsTarget: Int = 20
    var preferredDifficulty: BotDifficulty = .beginner

    mutating func applyAssistancePreset(_ level: AssistanceLevel) {
        assistanceLevel = level
        switch level {
        case .guided:
            showHandStrength = true
            showPotOdds = true
            allowRecommendations = true
        case .hints:
            showHandStrength = true
            showPotOdds = false
            allowRecommendations = true
        case .pure:
            showHandStrength = false
            showPotOdds = false
            allowRecommendations = false
        }
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
}
