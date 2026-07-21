import XCTest
@testable import RiverKit

/// Independent Chip Model correctness (§21, §63).
final class ICMTests: XCTestCase {

    func testEqualStacksShareEquallyAndConserveThePrizePool() {
        let payouts = [390.0, 210.0]
        let equities = ICM.equities(stacks: [1500, 1500, 1500], payouts: payouts)
        XCTAssertEqual(equities.count, 3)
        XCTAssertEqual(equities[0], equities[1], accuracy: 1e-9)
        XCTAssertEqual(equities[1], equities[2], accuracy: 1e-9)
        XCTAssertEqual(equities.reduce(0, +), payouts.reduce(0, +), accuracy: 1e-6)
    }

    func testEquitySumsToPrizePoolForUnevenStacks() {
        let payouts = [390.0, 210.0]
        let equities = ICM.equities(stacks: [4200, 2400, 1500, 600, 200, 100], payouts: payouts)
        XCTAssertEqual(equities.reduce(0, +), payouts.reduce(0, +), accuracy: 1e-6)
    }

    func testMoreChipsNeverMeansLessEquity() {
        let payouts = [390.0, 210.0]
        let stacks = [4000, 2500, 1500, 800, 200]
        let equities = ICM.equities(stacks: stacks, payouts: payouts)
        for index in 1..<stacks.count {
            XCTAssertGreaterThanOrEqual(equities[index - 1], equities[index] - 1e-9,
                                        "bigger stack must hold at least equal equity")
        }
    }

    func testBustedPlayerOutsideThePayoutsHasZeroEquity() {
        let equities = ICM.equities(stacks: [2000, 1000, 0], payouts: [390.0, 210.0])
        XCTAssertEqual(equities[2], 0, accuracy: 1e-9)
        XCTAssertEqual(equities.reduce(0, +), 600, accuracy: 1e-6)
    }

    func testHeadsUpEquityIsLinearInStackShare() {
        // With two players, P(win) = stack share, so equity is the runner-up
        // prize plus the stack-share fraction of the difference.
        let payouts = [390.0, 210.0]
        let stacks = [3000, 1500]
        let equities = ICM.equities(stacks: stacks, payouts: payouts)
        let share = 3000.0 / 4500.0
        XCTAssertEqual(equities[0], 210.0 + (390.0 - 210.0) * share, accuracy: 1e-6)
        XCTAssertEqual(equities[1], 210.0 + (390.0 - 210.0) * (1 - share), accuracy: 1e-6)
    }

    func testChipEVAndICMDivergeUnderAFlatPayout() {
        // Doubling up less than doubles tournament equity: the classic reason
        // marginal all-ins are worse in tournaments than in cash games.
        let payouts = [390.0, 210.0]
        let before = ICM.equities(stacks: [1500, 1500, 1500, 1500], payouts: payouts)[0]
        let afterWin = ICM.equities(stacks: [3000, 0, 1500, 1500], payouts: payouts)[0]
        XCTAssertLessThan(afterWin, before * 2, "ICM equity must grow sublinearly in chips")
    }

    func testRiskPremiumIsBoundedAndPositiveOnTheBubble() {
        // Three players left, two paid, medium stack risking everything.
        let premium = ICM.riskPremium(
            stacks: [3000, 1500, 1500],
            payouts: [390.0, 210.0],
            heroIndex: 1,
            villainIndex: 0,
            amountAtRisk: 1500
        )
        XCTAssertGreaterThan(premium, 0, "risking elimination on the bubble must carry a premium")
        XCTAssertLessThanOrEqual(premium, 0.4)
    }

    func testRiskPremiumViaTournamentContextIsZeroForZeroAmount() {
        let context = TournamentContext(
            playersRemaining: 3, payouts: [390, 210],
            stacks: [3000, 1500, 1500], onBubble: true, levelIndex: 4
        )
        XCTAssertEqual(context.riskPremium(for: 1, amount: 0), 0)
        XCTAssertGreaterThan(context.riskPremium(for: 1, amount: 1500), 0)
    }
}
