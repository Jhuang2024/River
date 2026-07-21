import XCTest
@testable import RiverKit

/// Shared fairness architecture (§3, §13): outcomes are functions of seeds
/// alone - bankroll, history, streaks and animation timing have no path into
/// any result. Plus bankroll modes, safeguards, records and achievements.
final class CasinoFairnessTests: XCTestCase {

    // MARK: - Outcomes depend on nothing but the seed

    func testOutcomesAreSeedFunctionsOnly() {
        // The engine APIs structurally take no bankroll/history arguments;
        // these assertions pin the behavioural half: repeated evaluation in
        // any order and any interleaving yields identical results.
        let rouletteFirst = RouletteEngine.winningPocket(wheel: .european, seed: 11).pocket
        let plinkoFirst = PlinkoEngine.drop(rows: .eight, risk: .high, wager: 10, seed: 11).slot
        let shoeFirst = BlackjackShoe(decks: 6, penetration: 0.75, seed: 11).cards

        // Simulate "a losing streak" by consuming lots of other outcomes.
        for seed in UInt64(1000)..<1200 {
            _ = RouletteEngine.winningPocket(wheel: .european, seed: seed)
            _ = PlinkoEngine.drop(rows: .sixteen, risk: .low, wager: 999, seed: seed)
        }

        XCTAssertEqual(RouletteEngine.winningPocket(wheel: .european, seed: 11).pocket, rouletteFirst)
        XCTAssertEqual(PlinkoEngine.drop(rows: .eight, risk: .high, wager: 10, seed: 11).slot, plinkoFirst)
        XCTAssertEqual(BlackjackShoe(decks: 6, penetration: 0.75, seed: 11).cards, shoeFirst)
    }

    func testWagerSizeNeverChangesAnyOutcome() {
        for seed in UInt64(0)..<50 {
            let smallDrop = PlinkoEngine.drop(rows: .twelve, risk: .medium, wager: 1, seed: seed)
            let hugeDrop = PlinkoEngine.drop(rows: .twelve, risk: .medium, wager: 1_000_000, seed: seed)
            XCTAssertEqual(smallDrop.slot, hugeDrop.slot)
            XCTAssertEqual(smallDrop.path, hugeDrop.path)
        }
    }

    // MARK: - Bankroll modes (§2)

    func testCareerBankrollSettlesExactly() {
        var bankroll = CasinoBankrollState(mode: .career, chips: 500)
        bankroll.settle(staked: 100, returned: 250)
        XCTAssertEqual(bankroll.chips, 650)
        XCTAssertEqual(bankroll.lifetimeNet, 150)
        bankroll.settle(staked: 650, returned: 0)
        XCTAssertEqual(bankroll.chips, 0)
        XCTAssertFalse(bankroll.canAfford(1))
        // Free recovery, never a purchase (§2).
        bankroll.rebuildCareer()
        XCTAssertEqual(bankroll.chips, CasinoBankrollState.rebuildAmount)
    }

    func testPracticeBankrollTracksNetWithoutLosingChips() {
        var bankroll = CasinoBankrollState(mode: .practice, chips: 100)
        XCTAssertTrue(bankroll.canAfford(1_000_000), "practice mode never blocks a wager")
        bankroll.settle(staked: 500, returned: 100)
        XCTAssertEqual(bankroll.chips, 100, "practice chips never drain")
        XCTAssertEqual(bankroll.lifetimeNet, -400, "statistics still count (§2)")
    }

    func testSessionBankrollResetsOnNewSession() {
        var bankroll = CasinoBankrollState(mode: .session, chips: 1000)
        bankroll.settle(staked: 300, returned: 0)
        XCTAssertEqual(bankroll.sessionNet, -300)
        bankroll.beginSession(stake: 1000)
        XCTAssertEqual(bankroll.chips, 1000)
        XCTAssertEqual(bankroll.sessionNet, 0)
    }

    func testRebuildOnlyAppliesToBrokeCareerBankrolls() {
        var rich = CasinoBankrollState(mode: .career, chips: 500)
        rich.rebuildCareer()
        XCTAssertEqual(rich.chips, 500, "rebuild refuses while chips remain")
        var practice = CasinoBankrollState(mode: .practice, chips: 0)
        practice.rebuildCareer()
        XCTAssertEqual(practice.chips, 0, "practice mode has nothing to rebuild")
    }

    // MARK: - Safeguards (§11)

    func testSafeguardsTriggerOnlyAtConfiguredLimits() {
        let guards = SessionSafeguards(roundLimit: 10, lossLimit: 100, profitTarget: 200)
        XCTAssertNil(guards.triggered(roundsPlayed: 9, sessionNet: -99))
        XCTAssertEqual(guards.triggered(roundsPlayed: 10, sessionNet: 0), .roundLimit)
        XCTAssertEqual(guards.triggered(roundsPlayed: 1, sessionNet: -100), .lossLimit)
        XCTAssertEqual(guards.triggered(roundsPlayed: 1, sessionNet: 200), .profitTarget)
        XCTAssertNil(SessionSafeguards().triggered(roundsPlayed: 10_000, sessionNet: -10_000),
                     "no limits configured means no interruptions")
    }

    // MARK: - Records and statistics (§12, §8)

    private func plinkoRecord(net: Int, slot: Int = 4, rows: PlinkoRows = .eight) -> CasinoRoundRecord {
        let wager = 10
        return CasinoRoundRecord(
            game: .plinko, date: Date(timeIntervalSince1970: 0), seed: 1,
            wagered: wager, returned: wager + net, outcomeSummary: "x",
            detail: .plinko(.init(rows: rows, risk: .medium, slot: slot, multiplierHundredths: 100, path: []))
        )
    }

    func testCasinoStatsAggregateAcrossGames() {
        let records: [CasinoRoundRecord] = [
            plinkoRecord(net: -5), plinkoRecord(net: -5), plinkoRecord(net: 20, slot: 0),
            CasinoRoundRecord(
                game: .roulette, date: Date(timeIntervalSince1970: 0), seed: 2,
                wagered: 10, returned: 20, outcomeSummary: "17 black",
                detail: .roulette(.init(
                    wheel: .european, pocket: 17,
                    bets: [.init(bet: RouletteLayout.outsideBet(.black, amount: 10)!, won: true, returned: 20)]
                ))
            )
        ]
        let stats = CasinoStats.compute(records: records)
        XCTAssertEqual(stats.rounds, 4)
        XCTAssertEqual(stats.totalWagered, 40)
        XCTAssertEqual(stats.totalReturned, 5 + 5 + 30 + 20)
        XCTAssertEqual(stats.ballsDropped, 3)
        XCTAssertEqual(stats.longestLosingStreak, 2)
        XCTAssertEqual(stats.blackCount, 1)
        XCTAssertEqual(stats.rouletteWinsByKind[.black], 1)

        let plinkoOnly = CasinoStats.compute(records: records, game: .plinko)
        XCTAssertEqual(plinkoOnly.rounds, 3)
        XCTAssertEqual(plinkoOnly.totalWagered, 30)
    }

    func testRoundRecordsSurviveCodableRoundTrips() throws {
        let record = plinkoRecord(net: 15, slot: 8)
        let decoded = try JSONDecoder().decode(CasinoRoundRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(decoded, record)
    }

    // MARK: - Achievements (§10)

    func testCasinoAchievementsStartLockedAndUnlockOnEvidence() {
        let empty = CasinoAchievementLibrary.Evidence(records: [])
        XCTAssertTrue(CasinoAchievementLibrary.unlocked(evidence: empty).isEmpty)

        let edge = plinkoRecord(net: 20, slot: 0)
        let some = CasinoAchievementLibrary.Evidence(
            records: [edge],
            plinkoSessionLengths: [55],
            fullShoeCountedCorrectly: true,
            longestCorrectDecisionRun: 25
        )
        let unlocked = CasinoAchievementLibrary.unlocked(evidence: some)
        XCTAssertTrue(unlocked.contains("cas.plinko.edge"))
        XCTAssertTrue(unlocked.contains("cas.plinko.session50"))
        XCTAssertTrue(unlocked.contains("cas.bj.counted"))
        XCTAssertTrue(unlocked.contains("cas.bj.cleanshoe"))
        let ids = Set(CasinoAchievementLibrary.all.map { $0.id })
        XCTAssertTrue(unlocked.isSubset(of: ids), "every unlocked id exists in the library")
    }

    func testAchievementIdsAreUnique() {
        let ids = CasinoAchievementLibrary.all.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count)
    }
}
