import XCTest
@testable import RiverKit

/// Plinko configuration, payouts, determinism and auto-drop rules (§4, §13).
final class PlinkoTests: XCTestCase {

    func testAllMultiplierTablesValidate() {
        let problems = PlinkoTables.validate()
        XCTAssertEqual(problems, [], problems.joined(separator: "; "))
    }

    func testTablesAreSymmetricWithTheRightSlotCounts() {
        for rows in PlinkoRows.allCases {
            for risk in PlinkoRisk.allCases {
                let table = PlinkoTables.multipliers(rows: rows, risk: risk)
                XCTAssertEqual(table.count, rows.slotCount)
                XCTAssertEqual(table, table.reversed(), "\(rows)/\(risk) must be symmetric")
            }
        }
    }

    func testRiskLevelsOrderVarianceSensibly() {
        for rows in PlinkoRows.allCases {
            let low = PlinkoTables.multipliers(rows: rows, risk: .low)
            let medium = PlinkoTables.multipliers(rows: rows, risk: .medium)
            let high = PlinkoTables.multipliers(rows: rows, risk: .high)
            XCTAssertLessThan(low.max()!, medium.max()!, "\(rows): medium tops low")
            XCTAssertLessThan(medium.max()!, high.max()!, "\(rows): high tops medium")
            XCTAssertGreaterThanOrEqual(low[low.count / 2], high[high.count / 2],
                                        "\(rows): high risk has the leaner centre")
        }
    }

    func testExpectedValueSitsJustBelowOne() {
        for rows in PlinkoRows.allCases {
            for risk in PlinkoRisk.allCases {
                let ev = PlinkoTables.expectedValueMillionths(rows: rows, risk: risk)
                XCTAssertLessThan(ev, 1_000_000, "\(rows)/\(risk): no positive-EV table")
                XCTAssertGreaterThan(ev, 950_000, "\(rows)/\(risk): edge stays small and honest")
            }
        }
    }

    // MARK: - Drops

    func testDropIsDeterministicAndPathMatchesSlot() {
        for seed in UInt64(0)..<200 {
            let drop = PlinkoEngine.drop(rows: .twelve, risk: .medium, wager: 100, seed: seed)
            let again = PlinkoEngine.drop(rows: .twelve, risk: .medium, wager: 100, seed: seed)
            XCTAssertEqual(drop, again, "same seed, same drop")
            XCTAssertEqual(drop.path.count, 12)
            XCTAssertEqual(drop.slot, drop.path.filter { $0 }.count, "slot = number of rights")
            XCTAssertEqual(drop.payout, 100 * drop.multiplierHundredths / 100)
        }
    }

    func testPayoutUsesExactIntegerArithmetic() {
        // 0.5x on 25 chips floors to 12 — deterministic, documented flooring.
        let table = PlinkoTables.multipliers(rows: .eight, risk: .low)
        XCTAssertEqual(table[4], 50)
        var found = false
        for seed in UInt64(0)..<2000 {
            let drop = PlinkoEngine.drop(rows: .eight, risk: .low, wager: 25, seed: seed)
            if drop.slot == 4 {
                XCTAssertEqual(drop.payout, 12)
                found = true
                break
            }
        }
        XCTAssertTrue(found, "centre slot reachable")
    }

    func testWagerScalesPayoutLinearly() {
        let small = PlinkoEngine.drop(rows: .sixteen, risk: .high, wager: 100, seed: 7)
        let large = PlinkoEngine.drop(rows: .sixteen, risk: .high, wager: 1000, seed: 7)
        XCTAssertEqual(small.slot, large.slot, "wager size cannot steer the ball (§3)")
        XCTAssertEqual(large.payout, small.payout * 10)
    }

    func testSlotDistributionIsCentredNotRigged() {
        var slots: [Int: Int] = [:]
        let drops = 4000
        for index in 0..<drops {
            let seed = PlinkoEngine.ballSeed(sessionSeed: 55, ballIndex: index)
            let drop = PlinkoEngine.drop(rows: .eight, risk: .medium, wager: 10, seed: seed)
            slots[drop.slot, default: 0] += 1
        }
        // Binomial(8, 0.5): centre ≈ 27.3%, edges ≈ 0.39% each. Loose bounds.
        let centre = Double(slots[4] ?? 0) / Double(drops)
        XCTAssertGreaterThan(centre, 0.22)
        XCTAssertLessThan(centre, 0.33)
        XCTAssertGreaterThan(slots.keys.count, 6, "most slots visited over 4000 drops")
    }

    func testBankrollConservationOverABatch() {
        var bankroll = 100_000
        var expectedNet = 0
        for index in 0..<500 {
            let seed = PlinkoEngine.ballSeed(sessionSeed: 9, ballIndex: index)
            let drop = PlinkoEngine.drop(rows: .twelve, risk: .high, wager: 20, seed: seed)
            bankroll = bankroll - drop.wager + drop.payout
            expectedNet += drop.net
        }
        XCTAssertEqual(bankroll, 100_000 + expectedNet)
    }

    // MARK: - Auto-drop stopping (§4)

    func testAutoDropStopsAtBallCount() {
        let plan = PlinkoAutoDrop(ballCount: 5, wagerPerBall: 10)
        XCTAssertFalse(plan.shouldStop(ballsDropped: 4, sessionNet: 0, bankroll: 100, practiceBankroll: false))
        XCTAssertTrue(plan.shouldStop(ballsDropped: 5, sessionNet: 0, bankroll: 100, practiceBankroll: false))
    }

    func testAutoDropStopsAtProfitTargetAndLossLimit() {
        let plan = PlinkoAutoDrop(ballCount: 100, wagerPerBall: 10, profitTarget: 50, lossLimit: 40)
        XCTAssertTrue(plan.shouldStop(ballsDropped: 1, sessionNet: 50, bankroll: 500, practiceBankroll: false))
        XCTAssertTrue(plan.shouldStop(ballsDropped: 1, sessionNet: -40, bankroll: 500, practiceBankroll: false))
        XCTAssertFalse(plan.shouldStop(ballsDropped: 1, sessionNet: 20, bankroll: 500, practiceBankroll: false))
    }

    func testAutoDropStopsAtBankrollFloorAndInsufficientFunds() {
        let plan = PlinkoAutoDrop(ballCount: 100, wagerPerBall: 10, bankrollFloor: 50)
        XCTAssertTrue(plan.shouldStop(ballsDropped: 1, sessionNet: 0, bankroll: 49, practiceBankroll: false))
        XCTAssertFalse(plan.shouldStop(ballsDropped: 1, sessionNet: 0, bankroll: 50, practiceBankroll: false))
        let broke = PlinkoAutoDrop(ballCount: 100, wagerPerBall: 10)
        XCTAssertTrue(broke.shouldStop(ballsDropped: 1, sessionNet: 0, bankroll: 9, practiceBankroll: false))
        // Practice bankrolls never run dry (§2).
        XCTAssertFalse(broke.shouldStop(ballsDropped: 1, sessionNet: 0, bankroll: 0, practiceBankroll: true))
    }

    func testBallSeedsAreIndependentPerIndexButReproducible() {
        let a = PlinkoEngine.ballSeed(sessionSeed: 123, ballIndex: 0)
        let b = PlinkoEngine.ballSeed(sessionSeed: 123, ballIndex: 1)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a, PlinkoEngine.ballSeed(sessionSeed: 123, ballIndex: 0))
    }
}
