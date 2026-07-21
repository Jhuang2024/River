import XCTest
@testable import RiverKit

/// Range-aware equity and pot-odds tests (§18, §44).
final class EquityEngineTests: XCTestCase {

    private func range(_ labels: [String]) -> HandRange {
        var map: [String: Double] = [:]
        for label in labels { map[label] = 1 }
        return HandRange.fromLabels(map)
    }

    func testPairVersusOvercardsPreflop() {
        // QQ vs AKo: the classic race, roughly 56-57% for the pair.
        let result = EquityEngine.equity(
            hole: [c(.queen, .spades), c(.queen, .hearts)],
            board: [],
            vsRanges: [range(["AKo"])],
            iterations: 4000,
            seed: 12345
        )
        XCTAssertEqual(result.share, 0.565, accuracy: 0.05)
        XCTAssertFalse(result.isExact)
        XCTAssertEqual(result.trials, 4000)
    }

    func testDominatingAce() {
        // AK vs AQ: dominated, around 72-74% for AK.
        let result = EquityEngine.equity(
            hole: [c(.ace, .spades), c(.king, .spades)],
            board: [],
            vsRanges: [range(["AQo"])],
            iterations: 4000,
            seed: 777
        )
        XCTAssertEqual(result.share, 0.72, accuracy: 0.06)
    }

    func testSetVersusFlushDrawOnFlop() {
        // Set of eights vs nut flush draw: around 62-70% for the set.
        let result = EquityEngine.equity(
            hole: [c(.eight, .spades), c(.eight, .diamonds)],
            board: [c(.eight, .hearts), c(.seven, .hearts), c(.two, .clubs)],
            vsRanges: [rangeOfExact(c(.ace, .hearts), c(.king, .hearts))],
            iterations: 3000,
            seed: 42
        )
        XCTAssertEqual(result.share, 0.66, accuracy: 0.08)
    }

    func testExactRiverEnumeration() {
        // Hero holds the nut flush on a completed board vs a made-hand range:
        // exact, and near-certain.
        let board = [c(.two, .hearts), c(.nine, .hearts), c(.king, .hearts), c(.four, .spades), c(.ten, .clubs)]
        let result = EquityEngine.equity(
            hole: [c(.ace, .hearts), c(.five, .hearts)],
            board: board,
            vsRanges: [range(["KQo", "99", "44"])],
            iterations: 100,
            seed: 5
        )
        XCTAssertTrue(result.isExact)
        XCTAssertEqual(result.share, 1.0, accuracy: 1e-9)
    }

    func testExactRiverTiedBoard() {
        // Board plays for both: exact split.
        let board = [c(.ace, .spades), c(.ace, .diamonds), c(.king, .hearts), c(.king, .spades), c(.queen, .clubs)]
        let result = EquityEngine.equity(
            hole: [c(.two, .clubs), c(.three, .diamonds)],
            board: board,
            vsRanges: [rangeOfExact(c(.five, .hearts), c(.six, .spades))],
            iterations: 100,
            seed: 5
        )
        XCTAssertTrue(result.isExact)
        XCTAssertEqual(result.tie, 1.0, accuracy: 1e-9)
        XCTAssertEqual(result.share, 0.5, accuracy: 1e-9)
    }

    func testMultiwayEquityIsLowerThanHeadsUp() {
        let hole = [c(.ace, .clubs), c(.jack, .clubs)]
        let single = EquityEngine.equity(hole: hole, board: [], vsRanges: [HandRange.uniform()], iterations: 2500, seed: 9)
        let multi = EquityEngine.equity(hole: hole, board: [], vsRanges: [HandRange.uniform(), HandRange.uniform(), HandRange.uniform()], iterations: 2500, seed: 9)
        XCTAssertGreaterThan(single.share, multi.share + 0.1)
    }

    func testDeadCardRemovalAffectsEquity() {
        // Villain range is exactly AA; hero holding two aces blocks it down
        // to one combo - equity must be far better than versus full AA.
        let blocked = EquityEngine.equity(
            hole: [c(.ace, .spades), c(.ace, .hearts)],
            board: [],
            vsRanges: [range(["AA"])],
            iterations: 2000,
            seed: 21
        )
        // The only remaining combo is AdAc: an almost pure tie.
        XCTAssertEqual(blocked.share, 0.5, accuracy: 0.05)
    }

    func testMonteCarloDeterministicSeeding() {
        let hole = [c(.king, .diamonds), c(.queen, .diamonds)]
        let a = EquityEngine.equity(hole: hole, board: [], vsRanges: [HandRange.uniform()], iterations: 1500, seed: 314)
        let b = EquityEngine.equity(hole: hole, board: [], vsRanges: [HandRange.uniform()], iterations: 1500, seed: 314)
        XCTAssertEqual(a, b)
        let c2 = EquityEngine.equity(hole: hole, board: [], vsRanges: [HandRange.uniform()], iterations: 1500, seed: 315)
        XCTAssertNotEqual(a.share, c2.share, "different seeds should differ slightly")
    }

    func testAsyncEquityMatchesSyncSemantics() async {
        let hole = [c(.nine, .spades), c(.nine, .clubs)]
        let result = await EquityEngine.equityAsync(hole: hole, board: [], vsRanges: [HandRange.uniform()], iterations: 800, seed: 66)
        XCTAssertEqual(result.trials, 800)
        XCTAssertGreaterThan(result.share, 0.55, "99 is well above average vs a random hand")
        XCTAssertLessThan(result.share, 0.85)
    }

    // MARK: - Pot odds (§18)

    func testPotOddsKnownExamples() {
        // Call 18 into 54: required equity 18 / 72 = 25%.
        let a = PotMath.odds(amountToCall: 18, potBeforeCall: 54)
        XCTAssertEqual(a.finalPot, 72)
        XCTAssertEqual(a.requiredEquity, 0.25, accuracy: 1e-9)
        // Call 40 into 100 (the spec's example shape): 40/140 ≈ 28.6%.
        let b = PotMath.odds(amountToCall: 40, potBeforeCall: 100)
        XCTAssertEqual(b.requiredEquity, 40.0 / 140.0, accuracy: 1e-9)
        // Nothing to call.
        let c3 = PotMath.odds(amountToCall: 0, potBeforeCall: 50)
        XCTAssertEqual(c3.requiredEquity, 0)
        XCTAssertEqual(c3.finalPot, 50)
    }

    func testCallEV() {
        // 50% equity calling 20 into 60: EV = 0.5*80 - 20 = +20.
        XCTAssertEqual(PotMath.callEV(equity: 0.5, amountToCall: 20, potBeforeCall: 60), 20, accuracy: 1e-9)
        // Break-even: equity exactly required.
        let odds = PotMath.odds(amountToCall: 30, potBeforeCall: 90)
        XCTAssertEqual(PotMath.callEV(equity: odds.requiredEquity, amountToCall: 30, potBeforeCall: 90), 0, accuracy: 1e-9)
    }

    private func rangeOfExact(_ a: Card, _ b: Card) -> HandRange {
        var range = HandRange()
        range.set(HoleCombo(a, b), weight: 1)
        return range
    }
}
