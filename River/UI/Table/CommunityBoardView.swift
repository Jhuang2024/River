import SwiftUI
import RiverKit

/// The five community-card slots with flop/turn/river grouping and staged
/// one-at-a-time reveals driven by `visibleCount` (§9).
struct CommunityBoardView: View {
    let board: [Card]
    /// How many board cards are currently revealed (the view model stages this).
    let visibleCount: Int
    var deckStyle: DeckStyle
    var cardWidth: CGFloat = 45
    /// Optional board-texture labels, shown only when assistance enables them.
    var textureLabels: [String] = []

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                // Flop group.
                HStack(spacing: 4) {
                    slot(0)
                    slot(1)
                    slot(2)
                }
                Spacer().frame(width: 5)
                slot(3) // turn
                Spacer().frame(width: 5)
                slot(4) // river
            }
            if !textureLabels.isEmpty && visibleCount >= 3 {
                Text(textureLabels.joined(separator: " · "))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.12) : .spring(duration: Theme.Motion.cardDeal * 1.4), value: visibleCount)
    }

    @ViewBuilder
    private func slot(_ index: Int) -> some View {
        if index < min(visibleCount, board.count) {
            PlayingCardView(card: board[index], width: cardWidth, style: deckStyle)
                .transition(reduceMotion
                    ? .opacity
                    : .asymmetric(insertion: .scale(scale: 0.5).combined(with: .opacity), removal: .opacity))
        } else {
            RoundedRectangle(cornerRadius: cardWidth * 0.14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
                .frame(width: cardWidth, height: cardWidth * 1.42)
        }
    }
}

/// Pot display (§10): total, tappable for a breakdown when side pots exist.
struct PotView: View {
    let pot: Int
    /// True when tapping opens the breakdown sheet.
    var tappable: Bool
    var accent: Color
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)
                Text("Pot \(pot)")
                    .font(Theme.Fonts.potValue)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                if tappable {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.black.opacity(0.45)))
        }
        .buttonStyle(.plain)
        .disabled(!tappable)
        .accessibilityLabel("Pot, \(pot) chips")
        .accessibilityIdentifier("table.pot")
    }
}
