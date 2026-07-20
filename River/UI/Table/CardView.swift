import SwiftUI
import RiverKit

/// A single playing card. Readable at small sizes: rank on top, suit below.
struct CardView: View {
    let card: Card?
    var width: CGFloat = 44
    var fourColor: Bool = false

    private var height: CGFloat { width * 1.42 }

    var body: some View {
        Group {
            if let card {
                face(card)
            } else {
                back
            }
        }
        .frame(width: width, height: height)
    }

    private func face(_ card: Card) -> some View {
        RoundedRectangle(cornerRadius: width * 0.14, style: .continuous)
            .fill(Theme.cardFace)
            .overlay(
                VStack(spacing: width * 0.02) {
                    Text(card.rank.symbol)
                        .font(.system(size: width * 0.42, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(card.suit.symbol)
                        .font(.system(size: width * 0.38))
                }
                .foregroundStyle(Theme.suitColor(card.suit, fourColor: fourColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: width * 0.14, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.15), lineWidth: 0.5)
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

/// The five community card slots.
struct BoardView: View {
    let board: [Card]
    var fourColor: Bool
    var cardWidth: CGFloat = 46

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<5, id: \.self) { index in
                if index < board.count {
                    CardView(card: board[index], width: cardWidth, fourColor: fourColor)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.4).combined(with: .opacity),
                            removal: .opacity
                        ))
                } else {
                    RoundedRectangle(cornerRadius: cardWidth * 0.14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                        .frame(width: cardWidth, height: cardWidth * 1.42)
                }
            }
        }
        .animation(.spring(duration: 0.35), value: board)
    }
}
