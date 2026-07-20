import Foundation

/// Monte Carlo equity estimation against unknown (random) opponent holdings.
///
/// Deterministic for a given seed, so bot decisions and tests reproduce
/// exactly. Never sees any real opponent's actual cards: opponents are dealt
/// random holdings from the cards not visible to the acting player.
public enum EquityEstimator {

    public struct Estimate: Equatable, Sendable {
        /// Probability of winning outright plus split-adjusted share, 0...1.
        public let equity: Double
        public let samples: Int
    }

    /// Estimates equity of `hole` + `board` versus `opponents` random hands.
    ///
    /// - Parameters:
    ///   - hole: the acting player's two hole cards.
    ///   - board: 0, 3, 4 or 5 community cards dealt so far.
    ///   - opponents: number of opponents still in the hand (1...8).
    ///   - iterations: Monte Carlo samples.
    ///   - rng: deterministic generator (consumed).
    public static func equityVsRandom(hole: [Card], board: [Card], opponents: Int, iterations: Int, rng: inout SeededRNG) -> Estimate {
        precondition(hole.count == 2, "need exactly two hole cards")
        precondition(board.count <= 5, "board cannot exceed five cards")
        let opponentCount = max(1, min(8, opponents))

        let known = Set(hole + board)
        let stock = Deck.standard().filter { !known.contains($0) }
        let boardNeeded = 5 - board.count
        var winShare = 0.0
        var count = 0

        var pool = stock
        for _ in 0..<max(1, iterations) {
            // Partial Fisher-Yates: draw just the cards needed for this sample.
            let needed = boardNeeded + opponentCount * 2
            var drawn: [Card] = []
            drawn.reserveCapacity(needed)
            var upper = pool.count
            for _ in 0..<needed {
                let j = rng.int(upperBound: upper)
                pool.swapAt(j, upper - 1)
                drawn.append(pool[upper - 1])
                upper -= 1
            }

            var fullBoard = board
            for k in 0..<boardNeeded {
                fullBoard.append(drawn[k])
            }
            let heroValue = HandEvaluator.evaluate(hole: hole, board: fullBoard)

            var bestOpponent: HandValue? = nil
            var opponentIndex = boardNeeded
            for _ in 0..<opponentCount {
                let oppHole = [drawn[opponentIndex], drawn[opponentIndex + 1]]
                opponentIndex += 2
                let value = HandEvaluator.evaluate(hole: oppHole, board: fullBoard)
                if bestOpponent == nil || value > bestOpponent! {
                    bestOpponent = value
                }
            }

            if let opponentBest = bestOpponent {
                if heroValue > opponentBest {
                    winShare += 1
                } else if heroValue == opponentBest {
                    // Split credit. (Approximation: full enumeration of exact
                    // multi-way split shares is not needed for decisions.)
                    winShare += 0.5
                }
            }
            count += 1
        }

        return Estimate(equity: count > 0 ? winShare / Double(count) : 0, samples: count)
    }

    /// Simple draw detection used for semi-bluff decisions and beginner hints.
    public struct Draws: Equatable, Sendable {
        public let flushDraw: Bool
        public let openEndedStraightDraw: Bool
        public let gutshotStraightDraw: Bool

        /// Rough count of clean outs implied by the detected draws.
        public var estimatedOuts: Int {
            var outs = 0
            if flushDraw { outs += 9 }
            if openEndedStraightDraw { outs += flushDraw ? 6 : 8 }
            else if gutshotStraightDraw { outs += flushDraw ? 3 : 4 }
            return outs
        }
    }

    public static func detectDraws(hole: [Card], board: [Card]) -> Draws {
        guard board.count >= 3 && board.count < 5 else {
            return Draws(flushDraw: false, openEndedStraightDraw: false, gutshotStraightDraw: false)
        }
        let all = hole + board

        // Flush draw: exactly four of one suit, using at least one hole card.
        var flushDraw = false
        for suit in Suit.allCases {
            let total = all.filter { $0.suit == suit }.count
            let mine = hole.filter { $0.suit == suit }.count
            if total == 4 && mine >= 1 {
                flushDraw = true
            }
        }

        // Straight draws via rank bitmask: count 4-in-a-row windows.
        var mask = 0
        for card in all {
            mask |= 1 << card.rank.rawValue
            if card.rank == .ace {
                mask |= 1 << 1
            }
        }
        var completions = Set<Int>()
        // A rank r (2...14) completes a straight if adding it makes 5 in a row.
        for candidate in 2...14 {
            if mask & (1 << candidate) != 0 { continue }
            let candidateMask = mask | (1 << candidate) | (candidate == 14 ? (1 << 1) : 0)
            var run = 0
            var made = false
            for r in 1...14 {
                if candidateMask & (1 << r) != 0 {
                    run += 1
                    if run >= 5 { made = true }
                } else {
                    run = 0
                }
            }
            if made {
                completions.insert(candidate)
            }
        }
        // If a straight is already made, treat as no draw (made hand instead).
        var run = 0
        var alreadyStraight = false
        for r in 1...14 {
            if mask & (1 << r) != 0 {
                run += 1
                if run >= 5 { alreadyStraight = true }
            } else {
                run = 0
            }
        }
        let openEnded = !alreadyStraight && completions.count >= 2
        let gutshot = !alreadyStraight && completions.count == 1
        return Draws(flushDraw: flushDraw, openEndedStraightDraw: openEnded, gutshotStraightDraw: gutshot)
    }
}
