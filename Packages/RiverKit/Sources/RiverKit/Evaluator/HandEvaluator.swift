import Foundation

/// Poker hand categories, ordered weakest to strongest.
public enum HandCategory: Int, Codable, Comparable, CaseIterable, Sendable {
    case highCard = 0
    case pair = 1
    case twoPair = 2
    case threeOfAKind = 3
    case straight = 4
    case flush = 5
    case fullHouse = 6
    case fourOfAKind = 7
    case straightFlush = 8

    public static func < (lhs: HandCategory, rhs: HandCategory) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }

    public var name: String {
        switch self {
        case .highCard: return "High card"
        case .pair: return "Pair"
        case .twoPair: return "Two pair"
        case .threeOfAKind: return "Three of a kind"
        case .straight: return "Straight"
        case .flush: return "Flush"
        case .fullHouse: return "Full house"
        case .fourOfAKind: return "Four of a kind"
        case .straightFlush: return "Straight flush"
        }
    }
}

/// The evaluated value of a best-five-card hand.
///
/// Comparison is category first, then the five tiebreaker values in order.
/// Two hands with equal category and tiebreakers are exact ties (suits never
/// break ties in Hold'em), which is how split pots arise.
public struct HandValue: Comparable, Equatable, Codable, Sendable {
    public let category: HandCategory
    /// Exactly five values (padded with 0). Meaning depends on category, e.g.
    /// for two pair: [high pair, low pair, kicker, 0, 0].
    public let tiebreakers: [Int]

    public init(category: HandCategory, tiebreakers: [Int]) {
        self.category = category
        var padded = tiebreakers
        while padded.count < 5 { padded.append(0) }
        self.tiebreakers = Array(padded.prefix(5))
    }

    public static func < (lhs: HandValue, rhs: HandValue) -> Bool {
        if lhs.category != rhs.category {
            return lhs.category < rhs.category
        }
        for i in 0..<5 {
            if lhs.tiebreakers[i] != rhs.tiebreakers[i] {
                return lhs.tiebreakers[i] < rhs.tiebreakers[i]
            }
        }
        return false
    }

    private func rankName(_ value: Int) -> String {
        return Rank(rawValue: value)?.name ?? "?"
    }

    private func rankPlural(_ value: Int) -> String {
        return Rank(rawValue: value)?.pluralName ?? "?"
    }

    /// Readable description such as "Pair of kings, ace kicker" or
    /// "Full house, tens over fours".
    public var readableDescription: String {
        switch category {
        case .highCard:
            return "\(rankName(tiebreakers[0]).capitalized) high"
        case .pair:
            return "Pair of \(rankPlural(tiebreakers[0])), \(rankName(tiebreakers[1])) kicker"
        case .twoPair:
            return "Two pair, \(rankPlural(tiebreakers[0])) and \(rankPlural(tiebreakers[1]))"
        case .threeOfAKind:
            return "Three of a kind, \(rankPlural(tiebreakers[0]))"
        case .straight:
            return "\(rankName(tiebreakers[0]).capitalized)-high straight"
        case .flush:
            return "\(rankName(tiebreakers[0]).capitalized)-high flush"
        case .fullHouse:
            return "Full house, \(rankPlural(tiebreakers[0])) over \(rankPlural(tiebreakers[1]))"
        case .fourOfAKind:
            return "Four of a kind, \(rankPlural(tiebreakers[0]))"
        case .straightFlush:
            if tiebreakers[0] == Rank.ace.rawValue {
                return "Royal flush"
            }
            return "\(rankName(tiebreakers[0]).capitalized)-high straight flush"
        }
    }
}

/// Evaluates the best five-card poker hand from five, six, or seven cards.
///
/// Algorithm: rank counts + flush suit detection + straight bitmask scan
/// (including the ace-low wheel). Validated against a brute force
/// best-of-21-combinations reference on hundreds of thousands of random hands.
public enum HandEvaluator {

    /// Returns the highest straight top rank present in the rank bitmask, or 0.
    /// Bit `r` of the mask is set when rank `r` (2...14) is present. The ace
    /// additionally counts as rank 1 for the wheel (A-2-3-4-5).
    private static func straightHigh(mask: Int) -> Int {
        var m = mask
        if m & (1 << 14) != 0 {
            m |= 1 << 1
        }
        var run = 0
        var best = 0
        var r = 1
        while r <= 14 {
            if m & (1 << r) != 0 {
                run += 1
                if run >= 5 {
                    best = r
                }
            } else {
                run = 0
            }
            r += 1
        }
        return best
    }

    /// Evaluates 5 to 7 cards and returns the value of the best five-card hand.
    public static func evaluate(_ cards: [Card]) -> HandValue {
        precondition(cards.count >= 5 && cards.count <= 7, "evaluator needs 5-7 cards")

        // counts[r] = number of cards of rank r; index 0..14, only 2..14 used.
        var counts = [Int](repeating: 0, count: 15)
        var suitRanks: [[Int]] = [[], [], [], []]
        var mask = 0
        for card in cards {
            let r = card.rank.rawValue
            counts[r] += 1
            suitRanks[card.suit.rawValue].append(r)
            mask |= 1 << r
        }

        var flushSuit = -1
        for s in 0..<4 where suitRanks[s].count >= 5 {
            flushSuit = s
            break
        }

        // Straight flush: run the straight scan on the flush suit's ranks only.
        if flushSuit >= 0 {
            var flushMask = 0
            for r in suitRanks[flushSuit] {
                flushMask |= 1 << r
            }
            let sf = straightHigh(mask: flushMask)
            if sf > 0 {
                return HandValue(category: .straightFlush, tiebreakers: [sf])
            }
        }

        var quads: [Int] = []
        var trips: [Int] = []
        var pairs: [Int] = []
        var r = 14
        while r >= 2 {
            switch counts[r] {
            case 4: quads.append(r)
            case 3: trips.append(r)
            case 2: pairs.append(r)
            default: break
            }
            r -= 1
        }

        if let quad = quads.first {
            var kicker = 0
            var k = 14
            while k >= 2 {
                if counts[k] > 0 && k != quad {
                    kicker = k
                    break
                }
                k -= 1
            }
            return HandValue(category: .fourOfAKind, tiebreakers: [quad, kicker])
        }

        // Full house can use a second set of trips as the pair
        // (e.g. 999 444 K plays as nines full of fours).
        if let bigTrips = trips.first {
            var pairPart = 0
            if pairs.count >= 1 {
                pairPart = pairs[0]
            }
            if trips.count > 1 {
                pairPart = max(pairPart, trips[1])
            }
            if pairPart > 0 {
                return HandValue(category: .fullHouse, tiebreakers: [bigTrips, pairPart])
            }
        }

        if flushSuit >= 0 {
            let top5 = suitRanks[flushSuit].sorted(by: >).prefix(5)
            return HandValue(category: .flush, tiebreakers: Array(top5))
        }

        let straight = straightHigh(mask: mask)
        if straight > 0 {
            return HandValue(category: .straight, tiebreakers: [straight])
        }

        if let tripsRank = trips.first {
            var kickers: [Int] = []
            var k = 14
            while k >= 2 && kickers.count < 2 {
                if counts[k] > 0 && k != tripsRank {
                    kickers.append(k)
                }
                k -= 1
            }
            return HandValue(category: .threeOfAKind, tiebreakers: [tripsRank] + kickers)
        }

        // Three pairs among seven cards: two best pairs play, best remaining
        // card (which may be the third pair's rank) is the kicker.
        if pairs.count >= 2 {
            let high = pairs[0]
            let low = pairs[1]
            var kicker = 0
            var k = 14
            while k >= 2 {
                if counts[k] > 0 && k != high && k != low {
                    kicker = k
                    break
                }
                k -= 1
            }
            return HandValue(category: .twoPair, tiebreakers: [high, low, kicker])
        }

        if let pairRank = pairs.first {
            var kickers: [Int] = []
            var k = 14
            while k >= 2 && kickers.count < 3 {
                if counts[k] > 0 && k != pairRank {
                    kickers.append(k)
                }
                k -= 1
            }
            return HandValue(category: .pair, tiebreakers: [pairRank] + kickers)
        }

        var tops: [Int] = []
        var k = 14
        while k >= 2 && tops.count < 5 {
            if counts[k] > 0 {
                tops.append(k)
            }
            k -= 1
        }
        return HandValue(category: .highCard, tiebreakers: tops)
    }

    /// Convenience: best hand from hole cards plus board.
    public static func evaluate(hole: [Card], board: [Card]) -> HandValue {
        return evaluate(hole + board)
    }
}
