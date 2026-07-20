import XCTest
@testable import RiverKit

final class EvaluatorTests: XCTestCase {

    func testWheelStraight() {
        let value = HandEvaluator.evaluate([
            c(.ace, .clubs), c(.two, .diamonds), c(.three, .hearts),
            c(.four, .spades), c(.five, .clubs), c(.nine, .diamonds), c(.king, .hearts)
        ])
        XCTAssertEqual(value.category, .straight)
        XCTAssertEqual(value.tiebreakers[0], 5)
        XCTAssertEqual(value.readableDescription, "Five-high straight")
    }

    func testWheelLosesToSixHighStraight() {
        let wheel = HandEvaluator.evaluate([
            c(.ace, .clubs), c(.two, .diamonds), c(.three, .hearts),
            c(.four, .spades), c(.five, .clubs)
        ])
        let sixHigh = HandEvaluator.evaluate([
            c(.two, .clubs), c(.three, .diamonds), c(.four, .hearts),
            c(.five, .spades), c(.six, .clubs)
        ])
        XCTAssertTrue(wheel < sixHigh)
    }

    func testSteelWheelStraightFlush() {
        let value = HandEvaluator.evaluate([
            c(.ace, .hearts), c(.two, .hearts), c(.three, .hearts),
            c(.four, .hearts), c(.five, .hearts), c(.nine, .diamonds), c(.king, .clubs)
        ])
        XCTAssertEqual(value.category, .straightFlush)
        XCTAssertEqual(value.tiebreakers[0], 5)
    }

    func testRoyalFlushDescription() {
        let value = HandEvaluator.evaluate([
            c(.ace, .spades), c(.king, .spades), c(.queen, .spades),
            c(.jack, .spades), c(.ten, .spades), c(.two, .diamonds), c(.three, .clubs)
        ])
        XCTAssertEqual(value.category, .straightFlush)
        XCTAssertEqual(value.readableDescription, "Royal flush")
    }

    func testFlushBeatsStraightOnSevenCards() {
        // Both a straight and a flush are present; flush must win.
        let value = HandEvaluator.evaluate([
            c(.two, .clubs), c(.five, .clubs), c(.nine, .clubs),
            c(.jack, .clubs), c(.king, .clubs), c(.ten, .diamonds), c(.queen, .hearts)
        ])
        XCTAssertEqual(value.category, .flush)
        XCTAssertEqual(value.tiebreakers, [13, 11, 9, 5, 2])
    }

    func testFullHouseFromTwoSetsOfTrips() {
        let value = HandEvaluator.evaluate([
            c(.nine, .clubs), c(.nine, .diamonds), c(.nine, .hearts),
            c(.four, .clubs), c(.four, .diamonds), c(.four, .hearts), c(.king, .spades)
        ])
        XCTAssertEqual(value.category, .fullHouse)
        XCTAssertEqual(value.tiebreakers[0], 9)
        XCTAssertEqual(value.tiebreakers[1], 4)
        XCTAssertEqual(value.readableDescription, "Full house, nines over fours")
    }

    func testFullHouseUsesBestPairWhenTripsPlusTwoPairs() {
        let value = HandEvaluator.evaluate([
            c(.nine, .clubs), c(.nine, .diamonds), c(.nine, .hearts),
            c(.four, .clubs), c(.four, .diamonds), c(.queen, .hearts), c(.queen, .spades)
        ])
        XCTAssertEqual(value.category, .fullHouse)
        XCTAssertEqual(value.tiebreakers[0], 9)
        XCTAssertEqual(value.tiebreakers[1], 12)
    }

    func testThreePairsCounterfeitPicksBestKicker() {
        // 99 44 QQ + A: plays QQ 99 with ace kicker.
        let value = HandEvaluator.evaluate([
            c(.nine, .clubs), c(.nine, .diamonds), c(.four, .clubs),
            c(.four, .diamonds), c(.queen, .hearts), c(.queen, .spades), c(.ace, .clubs)
        ])
        XCTAssertEqual(value.category, .twoPair)
        XCTAssertEqual(value.tiebreakers, [12, 9, 14, 0, 0])
    }

    func testQuadsWithBoardKicker() {
        let value = HandEvaluator.evaluate([
            c(.eight, .clubs), c(.eight, .diamonds), c(.eight, .hearts),
            c(.eight, .spades), c(.three, .clubs), c(.ace, .diamonds), c(.two, .hearts)
        ])
        XCTAssertEqual(value.category, .fourOfAKind)
        XCTAssertEqual(value.tiebreakers[0], 8)
        XCTAssertEqual(value.tiebreakers[1], 14)
    }

    func testKickerDecidesBetweenEqualPairs() {
        let board = [c(.king, .clubs), c(.seven, .diamonds), c(.two, .hearts), c(.nine, .spades), c(.four, .clubs)]
        let aceKicker = HandEvaluator.evaluate(hole: [c(.king, .hearts), c(.ace, .clubs)], board: board)
        let queenKicker = HandEvaluator.evaluate(hole: [c(.king, .spades), c(.queen, .clubs)], board: board)
        XCTAssertEqual(aceKicker.category, .pair)
        XCTAssertEqual(queenKicker.category, .pair)
        XCTAssertTrue(queenKicker < aceKicker)
        XCTAssertEqual(aceKicker.readableDescription, "Pair of kings, ace kicker")
    }

    func testBoardPlaysForBothIsExactTie() {
        let board = [c(.ace, .clubs), c(.ace, .diamonds), c(.king, .hearts), c(.king, .spades), c(.queen, .clubs)]
        let a = HandEvaluator.evaluate(hole: [c(.two, .clubs), c(.three, .diamonds)], board: board)
        let b = HandEvaluator.evaluate(hole: [c(.five, .hearts), c(.six, .spades)], board: board)
        XCTAssertEqual(a, b)
        XCTAssertFalse(a < b)
        XCTAssertFalse(b < a)
    }

    func testCounterfeitedTwoPair() {
        // Hero 5-5 on 9-9-Q-Q-A: hero's pair of fives is counterfeited;
        // best five is QQ 99 A, identical to a player holding 3-2.
        let board = [c(.nine, .clubs), c(.nine, .diamonds), c(.queen, .hearts), c(.queen, .spades), c(.ace, .clubs)]
        let fives = HandEvaluator.evaluate(hole: [c(.five, .clubs), c(.five, .diamonds)], board: board)
        let nothing = HandEvaluator.evaluate(hole: [c(.three, .clubs), c(.two, .diamonds)], board: board)
        XCTAssertEqual(fives, nothing)
    }

    func testSuitsNeverBreakTies() {
        let spadesFlush = HandEvaluator.evaluate([
            c(.ace, .spades), c(.jack, .spades), c(.nine, .spades), c(.five, .spades), c(.three, .spades)
        ])
        let heartsFlush = HandEvaluator.evaluate([
            c(.ace, .hearts), c(.jack, .hearts), c(.nine, .hearts), c(.five, .hearts), c(.three, .hearts)
        ])
        XCTAssertEqual(spadesFlush, heartsFlush)
    }

    func testCategoryOrdering() {
        let highCard = HandEvaluator.evaluate([c(.ace, .clubs), c(.king, .diamonds), c(.nine, .hearts), c(.five, .spades), c(.three, .clubs)])
        let pair = HandEvaluator.evaluate([c(.two, .clubs), c(.two, .diamonds), c(.nine, .hearts), c(.five, .spades), c(.three, .clubs)])
        let twoPair = HandEvaluator.evaluate([c(.two, .clubs), c(.two, .diamonds), c(.three, .hearts), c(.three, .spades), c(.nine, .clubs)])
        let trips = HandEvaluator.evaluate([c(.two, .clubs), c(.two, .diamonds), c(.two, .hearts), c(.five, .spades), c(.three, .clubs)])
        let straight = HandEvaluator.evaluate([c(.two, .clubs), c(.three, .diamonds), c(.four, .hearts), c(.five, .spades), c(.six, .clubs)])
        let flush = HandEvaluator.evaluate([c(.two, .clubs), c(.seven, .clubs), c(.nine, .clubs), c(.five, .clubs), c(.three, .clubs)])
        let fullHouse = HandEvaluator.evaluate([c(.two, .clubs), c(.two, .diamonds), c(.two, .hearts), c(.three, .spades), c(.three, .clubs)])
        let quads = HandEvaluator.evaluate([c(.two, .clubs), c(.two, .diamonds), c(.two, .hearts), c(.two, .spades), c(.three, .clubs)])
        let straightFlush = HandEvaluator.evaluate([c(.two, .clubs), c(.three, .clubs), c(.four, .clubs), c(.five, .clubs), c(.six, .clubs)])
        let ascending = [highCard, pair, twoPair, trips, straight, flush, fullHouse, quads, straightFlush]
        for i in 0..<(ascending.count - 1) {
            XCTAssertTrue(ascending[i] < ascending[i + 1], "category \(i) should lose to category \(i + 1)")
        }
    }

    func testDescriptions() {
        let straight = HandEvaluator.evaluate([c(.five, .clubs), c(.six, .diamonds), c(.seven, .hearts), c(.eight, .spades), c(.nine, .clubs)])
        XCTAssertEqual(straight.readableDescription, "Nine-high straight")
        let flush = HandEvaluator.evaluate([c(.ace, .clubs), c(.jack, .clubs), c(.nine, .clubs), c(.five, .clubs), c(.three, .clubs)])
        XCTAssertEqual(flush.readableDescription, "Ace-high flush")
        let fullHouse = HandEvaluator.evaluate([c(.ten, .clubs), c(.ten, .diamonds), c(.ten, .hearts), c(.four, .spades), c(.four, .clubs)])
        XCTAssertEqual(fullHouse.readableDescription, "Full house, tens over fours")
        let sixes = HandEvaluator.evaluate([c(.six, .clubs), c(.six, .diamonds), c(.six, .hearts), c(.four, .spades), c(.nine, .clubs)])
        XCTAssertEqual(sixes.readableDescription, "Three of a kind, sixes")
    }

    /// Randomized cross-check against a brute-force best-of-21 evaluation
    /// using an independent naive five-card scorer.
    func testRandomizedAgainstBruteForce() {
        var rng = SeededRNG(seed: 20260720)
        let deck = Deck.standard()
        for _ in 0..<3000 {
            var pool = deck
            var seven: [Card] = []
            var upper = pool.count
            for _ in 0..<7 {
                let j = rng.int(upperBound: upper)
                pool.swapAt(j, upper - 1)
                seven.append(pool[upper - 1])
                upper -= 1
            }
            let fast = HandEvaluator.evaluate(seven)
            let brute = bruteForceBest(seven)
            XCTAssertEqual(fast, brute, "mismatch for \(seven)")
        }
    }

    /// Independent naive implementation: evaluate all 21 five-card subsets.
    private func bruteForceBest(_ cards: [Card]) -> HandValue {
        var best: HandValue? = nil
        let n = cards.count
        for a in 0..<n {
            for b in (a + 1)..<n {
                var five: [Card] = []
                for i in 0..<n where i != a && i != b {
                    five.append(cards[i])
                }
                let value = naiveFive(five)
                if best == nil || value > best! {
                    best = value
                }
            }
        }
        return best!
    }

    /// Naive 5-card evaluator written with a different approach (sorting and
    /// grouping) so a shared bug with the main evaluator is unlikely.
    private func naiveFive(_ five: [Card]) -> HandValue {
        precondition(five.count == 5)
        let ranks = five.map { $0.rank.rawValue }.sorted(by: >)
        let isFlush = Set(five.map { $0.suit }).count == 1
        let unique = Array(Set(ranks)).sorted(by: >)
        var straightHigh = 0
        if unique.count == 5 {
            if unique[0] - unique[4] == 4 {
                straightHigh = unique[0]
            } else if unique == [14, 5, 4, 3, 2] {
                straightHigh = 5
            }
        }
        var groups: [Int: Int] = [:]
        for r in ranks {
            groups[r, default: 0] += 1
        }
        let sortedGroups = groups.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key > rhs.key
        }
        if isFlush && straightHigh > 0 {
            return HandValue(category: .straightFlush, tiebreakers: [straightHigh])
        }
        if sortedGroups[0].value == 4 {
            return HandValue(category: .fourOfAKind, tiebreakers: [sortedGroups[0].key, sortedGroups[1].key])
        }
        if sortedGroups[0].value == 3 && sortedGroups[1].value == 2 {
            return HandValue(category: .fullHouse, tiebreakers: [sortedGroups[0].key, sortedGroups[1].key])
        }
        if isFlush {
            return HandValue(category: .flush, tiebreakers: ranks)
        }
        if straightHigh > 0 {
            return HandValue(category: .straight, tiebreakers: [straightHigh])
        }
        if sortedGroups[0].value == 3 {
            let kickers = ranks.filter { $0 != sortedGroups[0].key }
            return HandValue(category: .threeOfAKind, tiebreakers: [sortedGroups[0].key] + kickers)
        }
        if sortedGroups[0].value == 2 && sortedGroups[1].value == 2 {
            let kicker = ranks.filter { $0 != sortedGroups[0].key && $0 != sortedGroups[1].key }
            return HandValue(category: .twoPair, tiebreakers: [sortedGroups[0].key, sortedGroups[1].key] + kicker)
        }
        if sortedGroups[0].value == 2 {
            let kickers = ranks.filter { $0 != sortedGroups[0].key }
            return HandValue(category: .pair, tiebreakers: [sortedGroups[0].key] + kickers)
        }
        return HandValue(category: .highCard, tiebreakers: ranks)
    }
}
