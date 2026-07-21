import SwiftUI
import RiverKit

/// One AI opponent seat (§7): avatar, name, stack, state, blind/dealer marker,
/// action label. Tap opens the observed-tendencies sheet.
struct PokerSeatView: View {
    let seat: SeatUIState
    var deckStyle: DeckStyle
    var accent: Color
    /// Dim slightly while the hero is deciding (§15).
    var deEmphasized: Bool = false
    var onTap: (() -> Void)? = nil

    private var dimmed: Bool { seat.hasFolded }

    var body: some View {
        Button {
            onTap?()
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .top) {
                    if seat.hasCards {
                        HStack(spacing: 2) {
                            if let cards = seat.visibleCards, cards.count == 2 {
                                PlayingCardView(card: cards[0], width: 25, style: deckStyle)
                                PlayingCardView(card: cards[1], width: 25, style: deckStyle)
                            } else {
                                PlayingCardView(card: nil, width: 25, style: deckStyle)
                                PlayingCardView(card: nil, width: 25, style: deckStyle)
                            }
                        }
                        .offset(y: -15)
                    }
                    avatar
                }
                nameplate
                actionLabel
            }
        }
        .buttonStyle(.plain)
        .opacity(dimmed ? 0.4 : (deEmphasized ? 0.8 : 1))
        .animation(.easeInOut(duration: Theme.Motion.button), value: dimmed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityIdentifier("seat.\(seat.id)")
    }

    private var accessibilitySummary: String {
        var parts = [seat.name, "\(seat.stack) chips"]
        if seat.hasFolded { parts.append("folded") }
        if seat.isAllIn { parts.append("all in") }
        if seat.isActing { parts.append("acting") }
        if seat.isButton { parts.append("dealer") }
        return parts.joined(separator: ", ")
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(Theme.backgroundElevated)
                .frame(width: 42, height: 42)
            Image(systemName: seat.symbolName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            if seat.isActing {
                Circle()
                    .strokeBorder(accent, lineWidth: 2.5)
                    .frame(width: 48, height: 48)
            } else if seat.netWon > 0 {
                Circle()
                    .strokeBorder(Theme.positive, lineWidth: 2.5)
                    .frame(width: 48, height: 48)
            }
            if seat.isButton {
                DealerButtonView()
                    .offset(x: 19, y: -17)
            } else if let blind = seat.blindLabel {
                Text(blind)
                    .font(.system(size: 7.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Color.white.opacity(0.14)))
                    .offset(x: 19, y: -17)
            }
        }
    }

    private var nameplate: some View {
        VStack(spacing: 0) {
            Text(seat.name)
                .font(Theme.Fonts.playerName)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Text(seat.isAllIn ? "ALL-IN" : "\(seat.stack)")
                .font(Theme.Fonts.stackValue)
                .monospacedDigit()
                .foregroundStyle(seat.isAllIn ? Theme.danger : Theme.metallic)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(minWidth: 58)
        .background(Capsule().fill(Color.black.opacity(0.5)))
    }

    @ViewBuilder
    private var actionLabel: some View {
        if let action = seat.lastAction {
            Text(action)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .transition(.opacity)
        } else {
            // Reserve the line so seats do not jump vertically.
            Text(" ")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
        }
    }
}

/// The dealer button marker.
struct DealerButtonView: View {
    var size: CGFloat = 16

    var body: some View {
        Text("D")
            .font(.system(size: size * 0.56, weight: .heavy, design: .rounded))
            .foregroundStyle(Color.black)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.white))
            .overlay(Circle().strokeBorder(Color.black.opacity(0.2), lineWidth: 0.5))
    }
}

/// Chips a seat has committed on the current street, rendered between the
/// seat and the pot. A small stack plus an exact monospaced label (§22).
struct ChipStackView: View {
    let amount: Int
    /// Cosmetic chip colour (§42); azure by default.
    var chipColor: Color = Theme.chipCommitted

    var body: some View {
        if amount > 0 {
            HStack(spacing: 3) {
                ZStack {
                    Circle()
                        .fill(chipColor)
                        .frame(width: 11, height: 11)
                        .offset(y: -2.5)
                    Circle()
                        .fill(chipColor.opacity(0.85))
                        .frame(width: 11, height: 11)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: 1))
                }
                Text("\(amount)")
                    .font(Theme.Fonts.stackValue)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.black.opacity(0.42)))
            .transition(.opacity)
        }
    }
}
