import SwiftUI
import RiverKit

/// RIVER's visual language: deep charcoal, near-black felt, restrained metallic
/// accents. No casino gold overload, no jackpot flash.
enum Theme {
    static let background = Color(red: 0.07, green: 0.08, blue: 0.09)
    static let backgroundElevated = Color(red: 0.11, green: 0.12, blue: 0.14)
    static let feltDark = Color(red: 0.05, green: 0.13, blue: 0.10)
    static let feltLight = Color(red: 0.09, green: 0.21, blue: 0.16)
    static let rail = Color(red: 0.16, green: 0.13, blue: 0.10)
    static let accent = Color(red: 0.79, green: 0.67, blue: 0.44)      // muted brass
    static let accentSoft = Color(red: 0.79, green: 0.67, blue: 0.44).opacity(0.6)
    static let textPrimary = Color(white: 0.94)
    static let textSecondary = Color(white: 0.62)
    static let cardFace = Color(white: 0.96)
    static let cardBack = Color(red: 0.16, green: 0.24, blue: 0.32)
    static let chipCommitted = Color(red: 0.22, green: 0.45, blue: 0.62)
    static let danger = Color(red: 0.78, green: 0.29, blue: 0.26)
    static let positive = Color(red: 0.32, green: 0.62, blue: 0.42)
    static let actingRing = Color(red: 0.85, green: 0.75, blue: 0.5)

    static let tableGradient = RadialGradient(
        colors: [feltLight, feltDark],
        center: .center,
        startRadius: 30,
        endRadius: 320
    )

    static let backgroundGradient = LinearGradient(
        colors: [Color(red: 0.09, green: 0.10, blue: 0.12), Color(red: 0.05, green: 0.06, blue: 0.07)],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Suit color, honoring the colorblind-friendly four-color deck option.
    static func suitColor(_ suit: Suit, fourColor: Bool) -> Color {
        if fourColor {
            switch suit {
            case .spades: return Color(white: 0.15)
            case .hearts: return Color(red: 0.75, green: 0.20, blue: 0.20)
            case .diamonds: return Color(red: 0.16, green: 0.38, blue: 0.72)
            case .clubs: return Color(red: 0.18, green: 0.52, blue: 0.34)
            }
        }
        switch suit {
        case .spades, .clubs: return Color(white: 0.15)
        case .hearts, .diamonds: return Color(red: 0.75, green: 0.20, blue: 0.20)
        }
    }
}

extension View {
    /// Standard prominent action button style.
    func riverButton(prominent: Bool = true) -> some View {
        self
            .font(.system(.headline, design: .rounded))
            .foregroundStyle(prominent ? Color.black : Theme.textPrimary)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(prominent ? Theme.accent : Theme.backgroundElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(prominent ? 0 : 0.08))
            )
    }
}
