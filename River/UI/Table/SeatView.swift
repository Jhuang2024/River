import SwiftUI
import RiverKit

/// One opponent seat: avatar, name, stack, cards, current bet and status.
struct SeatView: View {
    let seat: SeatUIState
    var fourColor: Bool

    private var dimmed: Bool {
        return seat.hasFolded
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .top) {
                // Face-down or revealed cards peeking from behind the avatar.
                if seat.hasCards && !seat.isHero {
                    HStack(spacing: 2) {
                        if let cards = seat.visibleCards, cards.count == 2 {
                            CardView(card: cards[0], width: 26, fourColor: fourColor)
                            CardView(card: cards[1], width: 26, fourColor: fourColor)
                        } else {
                            CardView(card: nil, width: 26)
                            CardView(card: nil, width: 26)
                        }
                    }
                    .offset(y: -16)
                }
                avatar
            }
            nameplate
            if let action = seat.lastAction, !seat.isHero {
                Text(action)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .opacity(dimmed ? 0.42 : 1)
        .animation(.easeInOut(duration: 0.25), value: dimmed)
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(Theme.backgroundElevated)
                .frame(width: 44, height: 44)
            Image(systemName: seat.symbolName)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(seat.isHero ? Theme.accent : Theme.textSecondary)
            if seat.isActing {
                Circle()
                    .strokeBorder(Theme.actingRing, lineWidth: 2.5)
                    .frame(width: 50, height: 50)
            }
            if seat.netWon > 0 {
                Circle()
                    .strokeBorder(Theme.positive, lineWidth: 2.5)
                    .frame(width: 50, height: 50)
            }
            if seat.isButton {
                Text("D")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.black)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Color.white))
                    .offset(x: 20, y: -18)
            }
        }
    }

    private var nameplate: some View {
        VStack(spacing: 1) {
            Text(seat.name)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Text(seat.isAllIn ? "ALL-IN" : "\(seat.stack)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(seat.isAllIn ? Theme.danger : Theme.accent)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(Color.black.opacity(0.45))
        )
    }
}

/// Chips a seat has committed on the current street, drawn toward the pot.
struct CommittedChipView: View {
    let amount: Int

    var body: some View {
        if amount > 0 {
            HStack(spacing: 3) {
                Circle()
                    .fill(Theme.chipCommitted)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
                Text("\(amount)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.black.opacity(0.4)))
            .transition(.scale.combined(with: .opacity))
        }
    }
}
