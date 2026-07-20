import Foundation

/// Canonical starting-hand utilities: labels like "AKs" and a strength score.
public enum PreflopHands {

    /// Canonical label for two hole cards: "AA", "AKs", "T9o", …
    public static func label(for cards: [Card]) -> String {
        guard cards.count == 2 else { return "?" }
        let high = max(cards[0].rank, cards[1].rank)
        let low = min(cards[0].rank, cards[1].rank)
        if high == low {
            return high.shortSymbol + low.shortSymbol
        }
        let suited = cards[0].suit == cards[1].suit
        return high.shortSymbol + low.shortSymbol + (suited ? "s" : "o")
    }

    /// Chen formula score, roughly -1.5...20. AA = 20, AKs = 12, 72o ≈ -1.
    /// A simple, well-known baseline for preflop hand quality; bot thresholds
    /// and difficulty adjustments are layered on top of it.
    public static func chenScore(for cards: [Card]) -> Double {
        guard cards.count == 2 else { return 0 }
        let high = max(cards[0].rank, cards[1].rank)
        let low = min(cards[0].rank, cards[1].rank)

        func cardPoints(_ rank: Rank) -> Double {
            switch rank {
            case .ace: return 10
            case .king: return 8
            case .queen: return 7
            case .jack: return 6
            default: return Double(rank.rawValue) / 2.0
            }
        }

        var score = cardPoints(high)

        if high == low {
            return max(5, score * 2)
        }

        if cards[0].suit == cards[1].suit {
            score += 2
        }

        let gap = high.rawValue - low.rawValue - 1
        switch gap {
        case 0: break
        case 1: score -= 1
        case 2: score -= 2
        case 3: score -= 4
        default: score -= 5
        }

        // Straight potential bonus for connected low cards.
        if gap <= 1 && high.rawValue < Rank.queen.rawValue {
            score += 1
        }

        // Chen rounds half points up.
        return (score * 2).rounded(.up) / 2
    }

    /// Rough percentile of hand quality in [0, 1], 1 = best. Derived from the
    /// Chen score; adequate for bot range decisions at this phase.
    public static func strengthPercentile(for cards: [Card]) -> Double {
        let score = chenScore(for: cards)
        // Chen scores range about -1.5...20; normalize with light shaping so
        // playable hands (score >= 5) sit above ~0.5.
        let normalized = (score + 1.5) / 21.5
        return min(1, max(0, normalized))
    }
}
