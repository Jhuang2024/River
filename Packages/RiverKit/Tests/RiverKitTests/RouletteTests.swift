import XCTest
@testable import RiverKit

/// Roulette wheels, bet validation, payouts and determinism (§5, §13).
final class RouletteTests: XCTestCase {

    func testEuropeanWheelContainsExactlyZeroToThirtySix() {
        let pockets = RouletteWheel.european.pocketOrder
        XCTAssertEqual(pockets.count, 37)
        XCTAssertEqual(Set(pockets), Set(0...36))
    }

    func testAmericanWheelAddsDoubleZero() {
        let pockets = RouletteWheel.american.pocketOrder
        XCTAssertEqual(pockets.count, 38)
        XCTAssertEqual(Set(pockets), Set(0...36).union([RoulettePocket.doubleZero]))
    }

    func testColorsMatchTheStandardLayout() {
        XCTAssertEqual(RoulettePocket.color(0), .green)
        XCTAssertEqual(RoulettePocket.color(RoulettePocket.doubleZero), .green)
        XCTAssertEqual(RoulettePocket.color(1), .red)
        XCTAssertEqual(RoulettePocket.color(2), .black)
        XCTAssertEqual(RoulettePocket.reds.count, 18)
        let blacks = Set(1...36).subtracting(RoulettePocket.reds)
        XCTAssertEqual(blacks.count, 18)
    }

    // MARK: - Bet validation (§5)

    func testEveryBetKindValidatesCorrectly() {
        let wheel = RouletteWheel.european
        XCTAssertNil(RouletteLayout.validate(RouletteBet(kind: .straightUp, numbers: [17], amount: 5), wheel: wheel))
        XCTAssertNil(RouletteLayout.validate(RouletteBet(kind: .split, numbers: [17, 18], amount: 5), wheel: wheel))
        XCTAssertNil(RouletteLayout.validate(RouletteBet(kind: .split, numbers: [17, 20], amount: 5), wheel: wheel))
        XCTAssertNil(RouletteLayout.validate(RouletteBet(kind: .split, numbers: [0, 2], amount: 5), wheel: wheel))
        XCTAssertNil(RouletteLayout.validate(RouletteBet(kind: .street, numbers: [16, 17, 18], amount: 5), wheel: wheel))
        XCTAssertNil(RouletteLayout.validate(RouletteBet(kind: .corner, numbers: [16, 17, 19, 20], amount: 5), wheel: wheel))
        XCTAssertNil(RouletteLayout.validate(RouletteBet(kind: .sixLine, numbers: Set(16...21), amount: 5), wheel: wheel))
        XCTAssertNil(RouletteLayout.validate(RouletteBet(kind: .dozen, numbers: Set(13...24), amount: 5), wheel: wheel))
        XCTAssertNil(RouletteLayout.validate(RouletteBet(kind: .column, numbers: Set(stride(from: 2, through: 35, by: 3)), amount: 5), wheel: wheel))
        for kind in [RouletteBetKind.red, .black, .odd, .even, .low, .high] {
            let bet = RouletteLayout.outsideBet(kind, amount: 5)
            XCTAssertNotNil(bet)
            XCTAssertNil(RouletteLayout.validate(bet!, wheel: wheel))
        }
    }

    func testAmbiguousOrIllegalPlacementsAreRejected() {
        let wheel = RouletteWheel.european
        XCTAssertNotNil(RouletteLayout.validate(RouletteBet(kind: .split, numbers: [17, 19], amount: 5), wheel: wheel),
                        "17-19 are not adjacent")
        XCTAssertNotNil(RouletteLayout.validate(RouletteBet(kind: .split, numbers: [3, 4], amount: 5), wheel: wheel),
                        "3-4 cross a row boundary")
        XCTAssertNotNil(RouletteLayout.validate(RouletteBet(kind: .street, numbers: [17, 18, 19], amount: 5), wheel: wheel))
        XCTAssertNotNil(RouletteLayout.validate(RouletteBet(kind: .corner, numbers: [17, 18, 19, 20], amount: 5), wheel: wheel))
        XCTAssertNotNil(RouletteLayout.validate(RouletteBet(kind: .straightUp, numbers: [RoulettePocket.doubleZero], amount: 5), wheel: wheel),
                        "no double zero on a European wheel")
        XCTAssertNotNil(RouletteLayout.validate(RouletteBet(kind: .straightUp, numbers: [17], amount: 0), wheel: wheel),
                        "zero stakes rejected")
        // Double-zero split legal only on the American wheel.
        let dzSplit = RouletteBet(kind: .split, numbers: [RoulettePocket.doubleZero, 2], amount: 5)
        XCTAssertNotNil(RouletteLayout.validate(dzSplit, wheel: .european))
        XCTAssertNil(RouletteLayout.validate(dzSplit, wheel: .american))
    }

    func testLayoutTablesHaveTheRightSizes() {
        XCTAssertEqual(RouletteLayout.legalStreets.count, 12)
        XCTAssertEqual(RouletteLayout.legalCorners.count, 22)
        XCTAssertEqual(RouletteLayout.legalSixLines.count, 11)
        XCTAssertEqual(RouletteLayout.dozens.count, 3)
        XCTAssertEqual(RouletteLayout.columns.count, 3)
        // Splits: 24 horizontal + 33 vertical + 3 zero splits.
        XCTAssertEqual(RouletteLayout.legalSplits(wheel: .european).count, 60)
        XCTAssertEqual(RouletteLayout.legalSplits(wheel: .american).count, 63)
    }

    // MARK: - Payouts (§5)

    private func forceSpin(pocket: Int, wheel: RouletteWheel, bets: [RouletteBet]) throws -> RouletteSpinResult {
        // Find a seed landing on the wanted pocket; uniform draw makes this
        // quick and keeps the engine's public API untouched.
        for seed in UInt64(0)...5000 {
            if RouletteEngine.winningPocket(wheel: wheel, seed: seed).pocket == pocket {
                return try RouletteEngine.spin(wheel: wheel, bets: bets, seed: seed)
            }
        }
        throw RouletteError.invalidBet("no seed found for pocket \(pocket)")
    }

    func testStandardPayoutsAreExact() throws {
        let cases: [(RouletteBet, Int)] = [
            (RouletteBet(kind: .straightUp, numbers: [17], amount: 10), 360),  // 35:1 + stake
            (RouletteBet(kind: .split, numbers: [17, 18], amount: 10), 180),   // 17:1 + stake
            (RouletteBet(kind: .street, numbers: [16, 17, 18], amount: 10), 120),
            (RouletteBet(kind: .corner, numbers: [16, 17, 19, 20], amount: 10), 90),
            (RouletteBet(kind: .sixLine, numbers: Set(13...18), amount: 10), 60),
            (RouletteBet(kind: .dozen, numbers: Set(13...24), amount: 10), 30),
            (RouletteBet(kind: .column, numbers: Set(stride(from: 2, through: 35, by: 3)), amount: 10), 30),
            (RouletteLayout.outsideBet(.black, amount: 10)!, 20)               // 17 is black
        ]
        for (bet, expectedReturn) in cases {
            let result = try forceSpin(pocket: 17, wheel: .european, bets: [bet])
            XCTAssertEqual(result.betResults[0].returned, expectedReturn, "\(bet.kind) payout")
        }
    }

    func testOverlappingBetsSettleIndependently() throws {
        let bets = [
            RouletteBet(kind: .straightUp, numbers: [17], amount: 10),
            RouletteBet(kind: .split, numbers: [17, 18], amount: 10),
            RouletteBet(kind: .dozen, numbers: Set(13...24), amount: 10),
            RouletteLayout.outsideBet(.red, amount: 10)!  // 17 is black: loses
        ]
        let result = try forceSpin(pocket: 17, wheel: .european, bets: bets)
        XCTAssertEqual(result.totalStaked, 40)
        XCTAssertEqual(result.totalReturned, 360 + 180 + 30 + 0)
        XCTAssertEqual(result.net, 570 - 40)
    }

    func testZeroBeatsAllOutsideBets() throws {
        let bets: [RouletteBet] = [.red, .black, .odd, .even, .low, .high].map {
            RouletteLayout.outsideBet($0, amount: 10)!
        } + [RouletteBet(kind: .dozen, numbers: Set(1...12), amount: 10)]
        let result = try forceSpin(pocket: 0, wheel: .european, bets: bets)
        XCTAssertEqual(result.totalReturned, 0, "zero loses every outside bet")

        let saved = try forceSpin(pocket: 0, wheel: .european,
                                  bets: [RouletteBet(kind: .straightUp, numbers: [0], amount: 10)])
        XCTAssertEqual(saved.totalReturned, 360, "straight-up zero still pays 35:1")
    }

    func testDoubleZeroBehavesLikeZeroOnTheAmericanWheel() throws {
        let dz = RoulettePocket.doubleZero
        let bets = [
            RouletteLayout.outsideBet(.red, amount: 10)!,
            RouletteBet(kind: .straightUp, numbers: [dz], amount: 10)
        ]
        let result = try forceSpin(pocket: dz, wheel: .american, bets: bets)
        XCTAssertEqual(result.betResults[0].returned, 0)
        XCTAssertEqual(result.betResults[1].returned, 360)
    }

    // MARK: - Determinism and fairness (§3)

    func testSameSeedSameResult() throws {
        let bets = [RouletteLayout.outsideBet(.red, amount: 10)!]
        let a = try RouletteEngine.spin(wheel: .european, bets: bets, seed: 999)
        let b = try RouletteEngine.spin(wheel: .european, bets: bets, seed: 999)
        XCTAssertEqual(a.pocket, b.pocket)
        XCTAssertEqual(a.totalReturned, b.totalReturned)
    }

    func testOutcomeIgnoresBetsPlaced() {
        // The winning pocket is a function of the seed alone: betting
        // differently can never move the ball (§3).
        let seed: UInt64 = 4242
        let bare = RouletteEngine.winningPocket(wheel: .european, seed: seed).pocket
        let heavyBets = [RouletteBet(kind: .straightUp, numbers: [bare], amount: 1_000_000)]
        let result = try? RouletteEngine.spin(wheel: .european, bets: heavyBets, seed: seed)
        XCTAssertEqual(result?.pocket, bare, "stake size cannot influence the pocket")
    }

    func testSpinDistributionCoversTheWholeWheel() {
        var seen = Set<Int>()
        for seed in UInt64(0)..<2000 {
            seen.insert(RouletteEngine.winningPocket(wheel: .european, seed: seed).pocket)
        }
        XCTAssertEqual(seen, Set(0...36), "every pocket reachable")
    }

    func testBankrollConservationAcrossSpins() throws {
        var bankroll = 1_000
        var expectedNet = 0
        for seed in UInt64(100)..<160 {
            let bets = [
                RouletteLayout.outsideBet(.red, amount: 5)!,
                RouletteBet(kind: .straightUp, numbers: [Int(seed % 36) + 1], amount: 5)
            ]
            let result = try RouletteEngine.spin(wheel: .european, bets: bets, seed: seed)
            bankroll -= result.totalStaked
            bankroll += result.totalReturned
            expectedNet += result.net
        }
        XCTAssertEqual(bankroll, 1_000 + expectedNet)
    }

    func testInvalidBetsFailTheWholeSpin() {
        let bad = RouletteBet(kind: .split, numbers: [1, 5], amount: 10)
        XCTAssertThrowsError(try RouletteEngine.spin(wheel: .european, bets: [bad], seed: 1))
    }
}
