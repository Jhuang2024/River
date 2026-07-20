import SwiftUI
import RiverKit

/// A single playing card (§21): large corner rank, clear suit, readable at
/// small sizes, four deck styles. Pass nil for a face-down card.
struct PlayingCardView: View {
    let card: Card?
    var width: CGFloat = 44
    var style: DeckStyle = .classic

    private var height: CGFloat { width * 1.42 }

    var body: some View {
        Group {
            if let card {
                face(card)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(card.rank.name.capitalized) of \(card.suit.name)")
            } else {
                back
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Face-down card")
            }
        }
        .frame(width: width, height: height)
    }

    private var faceColor: Color {
        switch style {
        case .highContrast: return .white
        case .minimal: return Theme.cardFaceMinimal
        default: return Theme.cardFace
        }
    }

    private var rankWeight: Font.Weight {
        return style == .highContrast ? .heavy : .bold
    }

    private func face(_ card: Card) -> some View {
        let suitColor = Theme.suitColor(card.suit, style: style)
        return RoundedRectangle(cornerRadius: width * 0.14, style: .continuous)
            .fill(faceColor)
            .overlay(
                VStack(spacing: width * (style == .minimal ? 0.04 : 0.01)) {
                    Text(card.rank.symbol)
                        .font(.system(size: width * (style == .highContrast ? 0.46 : 0.42), weight: rankWeight, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(card.suit.symbol)
                        .font(.system(size: width * (style == .minimal ? 0.30 : 0.38)))
                }
                .foregroundStyle(suitColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: width * 0.14, style: .continuous)
                    .strokeBorder(Color.black.opacity(style == .highContrast ? 0.4 : 0.15), lineWidth: style == .highContrast ? 1 : 0.5)
            )
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
    }

    private var back: some View {
        RoundedRectangle(cornerRadius: width * 0.14, style: .continuous)
            .fill(Theme.cardBack)
            .overlay(
                RoundedRectangle(cornerRadius: width * 0.10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                    .padding(width * 0.09)
            )
            .overlay(
                Image(systemName: "drop.fill")
                    .font(.system(size: width * 0.3))
                    .foregroundStyle(Color.white.opacity(0.25))
            )
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
    }
}

/// The hero's two hole cards, with optional long-press magnification (§14)
/// and an optional swipe-down fold gesture (§12, off by default).
struct HoleCardsView: View {
    let cards: [Card]?
    var width: CGFloat = 58
    var style: DeckStyle
    var dimmed: Bool = false
    var onSwipeDownFold: (() -> Void)? = nil

    @State private var magnified = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            if let cards, cards.count == 2 {
                PlayingCardView(card: cards[0], width: width, style: style)
                PlayingCardView(card: cards[1], width: width, style: style)
            } else {
                PlayingCardView(card: nil, width: width, style: style)
                PlayingCardView(card: nil, width: width, style: style)
            }
        }
        .opacity(dimmed ? 0.4 : 1)
        .scaleEffect(magnified && !reduceMotion ? 1.35 : 1, anchor: .bottom)
        .animation(.spring(duration: Theme.Motion.button), value: magnified)
        .onLongPressGesture(minimumDuration: 0.25, perform: {}, onPressingChanged: { pressing in
            magnified = pressing
        })
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    if let onSwipeDownFold, value.translation.height > 50, abs(value.translation.width) < 60 {
                        onSwipeDownFold()
                    }
                }
        )
        .accessibilityIdentifier("hero.holeCards")
    }
}

#Preview("Deck styles") {
    VStack(spacing: 16) {
        ForEach(DeckStyle.allCases) { style in
            HStack(spacing: 8) {
                PlayingCardView(card: Card(.ace, .spades), width: 50, style: style)
                PlayingCardView(card: Card(.king, .hearts), width: 50, style: style)
                PlayingCardView(card: Card(.ten, .diamonds), width: 50, style: style)
                PlayingCardView(card: Card(.four, .clubs), width: 50, style: style)
                PlayingCardView(card: nil, width: 50, style: style)
            }
        }
    }
    .padding()
    .background(Theme.background)
}
