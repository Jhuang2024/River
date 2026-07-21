import SwiftUI
import RiverKit

/// RIVER design tokens (§4): near-black backgrounds, graphite surfaces, deep
/// muted table green, cool grey type, restrained metallic details. One
/// player-selected accent at a time; semantic colours keep fixed meanings.
enum Theme {

    // MARK: - Base palette

    static let background = Color(red: 0.055, green: 0.06, blue: 0.07)
    static let backgroundElevated = Color(red: 0.10, green: 0.11, blue: 0.125)
    static let surface = Color(red: 0.13, green: 0.14, blue: 0.155)
    static let feltDark = Color(red: 0.045, green: 0.115, blue: 0.09)
    static let feltLight = Color(red: 0.08, green: 0.19, blue: 0.145)
    static let rail = Color(red: 0.14, green: 0.12, blue: 0.10)
    static let textPrimary = Color(white: 0.93)
    static let textSecondary = Color(white: 0.60)
    static let textTertiary = Color(white: 0.42)
    static let metallic = Color(red: 0.68, green: 0.70, blue: 0.73)
    static let separator = Color.white.opacity(0.08)

    // MARK: - Semantic colours (§4): fixed meanings, never decorative.

    /// Favourable / correct.
    static let positive = Color(red: 0.30, green: 0.66, blue: 0.44)
    /// Warning / marginal.
    static let caution = Color(red: 0.85, green: 0.66, blue: 0.30)
    /// Dangerous / major mistake / destructive action.
    static let danger = Color(red: 0.80, green: 0.30, blue: 0.27)
    /// Informational.
    static let info = Color(red: 0.35, green: 0.58, blue: 0.85)
    /// Neutral / inactive.
    static let neutral = Color(white: 0.45)

    // MARK: - Cards & chips

    static let cardFace = Color(white: 0.96)
    static let cardFaceMinimal = Color(white: 0.92)
    static let cardBack = Color(red: 0.15, green: 0.22, blue: 0.30)
    static let chipCommitted = Color(red: 0.24, green: 0.46, blue: 0.62)

    // MARK: - Gradients

    static let tableGradient = RadialGradient(
        colors: [feltLight, feltDark],
        center: .center,
        startRadius: 30,
        endRadius: 340
    )

    /// Cosmetic felt themes (§42) - visual only, never gameplay.
    static func tableGradient(for theme: TableThemeChoice) -> RadialGradient {
        let light: Color
        let dark: Color
        switch theme {
        case .classic:
            light = feltLight; dark = feltDark
        case .midnight:
            light = Color(red: 0.10, green: 0.13, blue: 0.22); dark = Color(red: 0.05, green: 0.06, blue: 0.12)
        case .crimson:
            light = Color(red: 0.22, green: 0.08, blue: 0.10); dark = Color(red: 0.10, green: 0.03, blue: 0.05)
        case .slate:
            light = Color(red: 0.16, green: 0.17, blue: 0.19); dark = Color(red: 0.07, green: 0.08, blue: 0.09)
        }
        return RadialGradient(colors: [light, dark], center: .center, startRadius: 30, endRadius: 340)
    }

    /// Cosmetic chip colours (§42).
    static func chipColor(for style: ChipStyleChoice) -> Color {
        switch style {
        case .azure: return chipCommitted
        case .ruby: return Color(red: 0.62, green: 0.22, blue: 0.24)
        case .brass: return Color(red: 0.62, green: 0.52, blue: 0.30)
        case .mono: return Color(white: 0.55)
        }
    }

    static let backgroundGradient = LinearGradient(
        colors: [Color(red: 0.085, green: 0.09, blue: 0.105), Color(red: 0.045, green: 0.05, blue: 0.06)],
        startPoint: .top,
        endPoint: .bottom
    )

    // MARK: - Spacing scale

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - Corner radii

    enum Radius {
        static let chip: CGFloat = 8
        static let control: CGFloat = 13
        static let card: CGFloat = 14
        static let sheet: CGFloat = 22
    }

    // MARK: - Motion base durations (§39), multiplied by GameSpeed.motionScale
    // at animation sites where pacing is speed-dependent.

    enum Motion {
        static let micro: Double = 0.14
        static let button: Double = 0.18
        static let cardDeal: Double = 0.24
        static let chip: Double = 0.26
        static let sheet: Double = 0.32
        static let major: Double = 0.5
    }

    // MARK: - Typography roles (§5). Numbers use monospaced digits.

    enum Fonts {
        static let display = Font.system(size: 44, weight: .black, design: .rounded)
        static let screenTitle = Font.system(size: 22, weight: .bold, design: .rounded)
        static let sectionTitle = Font.system(size: 11, weight: .bold, design: .rounded)
        static let playerName = Font.system(size: 11, weight: .semibold, design: .rounded)
        static let stackValue = Font.system(size: 12, weight: .bold, design: .rounded)
        static let potValue = Font.system(size: 15, weight: .bold, design: .rounded)
        static let primaryAction = Font.system(size: 17, weight: .semibold, design: .rounded)
        static let secondaryAction = Font.system(size: 14, weight: .semibold, design: .rounded)
        static let body = Font.system(size: 15, design: .rounded)
        static let caption = Font.system(size: 11, design: .rounded)
        static let telemetry = Font.system(size: 11, weight: .medium, design: .monospaced)
    }

    // MARK: - Suit colours (§21)

    static func suitColor(_ suit: Suit, style: DeckStyle) -> Color {
        switch style {
        case .fourColor:
            switch suit {
            case .clubs: return Color(red: 0.18, green: 0.52, blue: 0.32)
            case .diamonds: return Color(red: 0.17, green: 0.40, blue: 0.75)
            case .hearts: return Color(red: 0.76, green: 0.20, blue: 0.20)
            case .spades: return Color(white: 0.13)
            }
        case .highContrast:
            switch suit {
            case .spades, .clubs: return Color.black
            case .hearts, .diamonds: return Color(red: 0.82, green: 0.10, blue: 0.10)
            }
        default:
            switch suit {
            case .spades, .clubs: return Color(white: 0.15)
            case .hearts, .diamonds: return Color(red: 0.74, green: 0.21, blue: 0.21)
            }
        }
    }
}

// MARK: - Shared control styling

extension View {
    /// Standard prominent action button fill.
    func riverButton(prominent: Bool = true, accent: Color) -> some View {
        self
            .font(Theme.Fonts.primaryAction)
            .foregroundStyle(prominent ? Color.black : Theme.textPrimary)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(prominent ? accent : Theme.backgroundElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .strokeBorder(Color.white.opacity(prominent ? 0 : 0.08))
            )
    }

    /// Section header style ("SESSION STATS").
    func sectionHeader() -> some View {
        self
            .font(Theme.Fonts.sectionTitle)
            .kerning(1.2)
            .foregroundStyle(Theme.textSecondary)
    }
}
