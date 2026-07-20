import XCTest
@testable import RiverKit

final class PotBuilderTests: XCTestCase {

    func testClassicThreeWayAllInWithDeadMoney() {
        // A committed 100, B 60, C 30 (all live); D folded after 10.
        let result = PotBuilder.build(committed: [100, 60, 30, 10], liveSeats: [0, 1, 2])
        XCTAssertEqual(result.refunds, [40, 0, 0, 0], "uncalled 40 goes back to the top committer")
        XCTAssertEqual(result.pots.count, 2)
        XCTAssertEqual(result.pots[0].amount, 100) // 30*3 + 10 dead
        XCTAssertEqual(result.pots[0].eligibleSeats, [0, 1, 2])
        XCTAssertEqual(result.pots[1].amount, 60)  // 30 more from A and B
        XCTAssertEqual(result.pots[1].eligibleSeats, [0, 1])
    }

    func testNoRefundWhenTopCommittersTie() {
        let result = PotBuilder.build(committed: [50, 50, 20], liveSeats: [0, 1])
        XCTAssertEqual(result.refunds, [0, 0, 0])
        XCTAssertEqual(result.pots.count, 1)
        XCTAssertEqual(result.pots[0].amount, 120)
        XCTAssertEqual(result.pots[0].eligibleSeats, [0, 1])
    }

    func testSingleLivePlayerGetsEverythingMinusRefund() {
        let result = PotBuilder.build(committed: [80, 30, 0], liveSeats: [0])
        XCTAssertEqual(result.refunds, [50, 0, 0])
        XCTAssertEqual(result.pots.count, 1)
        XCTAssertEqual(result.pots[0].amount, 60)
        XCTAssertEqual(result.pots[0].eligibleSeats, [0])
    }

    func testFourLevelPots() {
        let result = PotBuilder.build(committed: [10, 20, 30, 40], liveSeats: [0, 1, 2, 3])
        XCTAssertEqual(result.refunds, [0, 0, 0, 10])
        XCTAssertEqual(result.pots.count, 3)
        XCTAssertEqual(result.pots[0].amount, 40)
        XCTAssertEqual(result.pots[0].eligibleSeats, [0, 1, 2, 3])
        XCTAssertEqual(result.pots[1].amount, 30)
        XCTAssertEqual(result.pots[1].eligibleSeats, [1, 2, 3])
        XCTAssertEqual(result.pots[2].amount, 20)
        XCTAssertEqual(result.pots[2].eligibleSeats, [2, 3])
    }

    func testConservationProperty() {
        var rng = SeededRNG(seed: 555)
        for _ in 0..<20000 {
            let n = rng.int(in: 2...6)
            var committed = (0..<n).map { _ in rng.int(in: 0...200) }
            let positive = (0..<n).filter { committed[$0] > 0 }
            guard positive.count >= 2 else { continue }
            let liveCount = rng.int(in: 2...positive.count)
            var pool = positive
            var live = Set<Int>()
            for _ in 0..<liveCount {
                let pick = rng.int(upperBound: pool.count)
                live.insert(pool.remove(at: pick))
            }
            // Engine invariant: a folded seat can never out-commit every live seat.
            let maxLive = live.map { committed[$0] }.max() ?? 0
            for i in 0..<n where !live.contains(i) && committed[i] > maxLive {
                committed[i] = maxLive
            }
            let total = committed.reduce(0, +)
            let result = PotBuilder.build(committed: committed, liveSeats: live)
            let potTotal = result.pots.reduce(0) { $0 + $1.amount }
            let refundTotal = result.refunds.reduce(0, +)
            XCTAssertEqual(potTotal + refundTotal, total, "chips lost or created for \(committed) live \(live)")
            for pot in result.pots {
                XCTAssertFalse(pot.eligibleSeats.isEmpty, "a pot must have at least one eligible winner")
                XCTAssertTrue(pot.eligibleSeats.allSatisfy { live.contains($0) })
            }
        }
    }
}
