import XCTest
@testable import RiverKit

final class SessionPersistenceTests: XCTestCase {

    private func tempStore() -> PersistenceStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("river-tests-\(UUID().uuidString)", isDirectory: true)
        return PersistenceStore(directory: dir)
    }

    func testButtonRotatesEachHand() throws {
        var session = CashSessionState(
            config: SessionConfig(handsTarget: 3, seed: 5, bots: BotProfile.defaultLineup(difficulty: .beginner)),
            startDate: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(session.buttonIndex, 0)
        var rng = SeededRNG(seed: 88)
        for expectedButton in [1, 2, 3] {
            let hand = PokerHand(config: session.nextHandConfig())
            playRandomHand(hand, rng: &rng)
            session.complete(hand: hand)
            XCTAssertEqual(session.buttonIndex, expectedButton)
        }
        XCTAssertTrue(session.isFinished)
        XCTAssertEqual(session.heroNetByHand.count, 3)
    }

    func testPerHandSeedsAreStableAndDistinct() {
        let config = SessionConfig(seed: 99, bots: BotProfile.defaultLineup(difficulty: .beginner))
        var a = CashSessionState(config: config, startDate: Date(timeIntervalSince1970: 0))
        var b = CashSessionState(config: config, startDate: Date(timeIntervalSince1970: 500))
        let seedA1 = a.seedForNextHand()
        XCTAssertEqual(seedA1, b.seedForNextHand(), "hand seeds depend only on session seed and hand number")
        a.handsPlayed = 1
        b.handsPlayed = 1
        XCTAssertEqual(a.seedForNextHand(), b.seedForNextHand())
        XCTAssertNotEqual(seedA1, a.seedForNextHand(), "different hands get different seeds")
    }

    func testAutoReloadTopsUpBustedSeats() {
        var session = CashSessionState(
            config: SessionConfig(seed: 7, bots: BotProfile.defaultLineup(difficulty: .beginner)),
            startDate: Date(timeIntervalSince1970: 0)
        )
        session.stacks[2] = 0
        session.stacks[4] = 1
        let config = session.nextHandConfig()
        XCTAssertEqual(config.stacks[2], 200)
        XCTAssertEqual(config.stacks[4], 200)
        XCTAssertTrue(session.lastReloadedSeats.contains(2))
        XCTAssertTrue(session.lastReloadedSeats.contains(4))
    }

    func testHandHistoryRoundTripsThroughJSON() throws {
        var rng = SeededRNG(seed: 3)
        let config = HandConfig(stacks: Array(repeating: 200, count: 6), buttonIndex: 1, smallBlind: 1, bigBlind: 2, seed: 12345)
        let hand = PokerHand(config: config)
        playRandomHand(hand, rng: &rng)
        let history = HandHistory(date: Date(timeIntervalSince1970: 1000), heroSeat: 0, playerNames: ["You", "A", "B", "C", "D", "E"], hand: hand)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(history)
        let decoded = try decoder.decode(HandHistory.self, from: data)
        XCTAssertEqual(decoded, history)
        XCTAssertEqual(decoded.schemaVersion, HandHistory.currentSchemaVersion)
        XCTAssertEqual(decoded.seed, 12345)
    }

    func testPersistenceStoreSaveLoadDelete() throws {
        let store = tempStore()
        var session = CashSessionState(
            config: SessionConfig(seed: 4, bots: BotProfile.defaultLineup(difficulty: .intermediate)),
            startDate: Date(timeIntervalSince1970: 0)
        )
        session.handsPlayed = 7
        try store.save(session, as: PersistenceStore.FileName.session)
        XCTAssertTrue(store.exists(PersistenceStore.FileName.session))
        let loaded = store.load(CashSessionState.self, from: PersistenceStore.FileName.session)
        XCTAssertEqual(loaded, session)
        store.delete(PersistenceStore.FileName.session)
        XCTAssertFalse(store.exists(PersistenceStore.FileName.session))
        XCTAssertNil(store.load(CashSessionState.self, from: PersistenceStore.FileName.session))
    }

    func testHistoryRingBufferLimit() throws {
        let store = tempStore()
        var rng = SeededRNG(seed: 21)
        for i in 0..<5 {
            let config = HandConfig(stacks: [100, 100], buttonIndex: 0, smallBlind: 1, bigBlind: 2, seed: UInt64(i), handNumber: i)
            let hand = PokerHand(config: config)
            playRandomHand(hand, rng: &rng)
            let history = HandHistory(date: Date(timeIntervalSince1970: 0), heroSeat: 0, playerNames: ["You", "Bot"], hand: hand)
            store.appendHistory(history, limit: 3)
        }
        let all = store.loadHistories()
        XCTAssertEqual(all.count, 3, "ring buffer must cap stored histories")
        XCTAssertEqual(all.last?.handNumber, 4, "most recent hand kept")
    }

    func testSessionStatsFromHistories() throws {
        // Hand where hero (seat 0, button) raises preflop and everyone folds.
        let config = HandConfig(stacks: Array(repeating: 200, count: 3), buttonIndex: 1, smallBlind: 1, bigBlind: 2, seed: 8)
        let hand = PokerHand(config: config)
        // Button 1 → SB 2, BB 0. First to act 3-handed is the button (1).
        try hand.apply(.fold, by: 1)
        try hand.apply(.fold, by: 2)
        XCTAssertTrue(hand.isComplete)
        let history = HandHistory(date: Date(timeIntervalSince1970: 0), heroSeat: 0, playerNames: ["You", "A", "B"], hand: hand)
        let stats = SessionStats.compute(histories: [history], seat: 0)
        XCTAssertEqual(stats.handsPlayed, 1)
        XCTAssertEqual(stats.handsWon, 1)
        XCTAssertEqual(stats.netChips, 1, "big blind wins the small blind")
        XCTAssertEqual(stats.vpipCount, 0, "winning in the blinds without acting is not VPIP")
    }

    func testAdvisorGivesReasonedRecommendations() {
        // Nuts on the river facing a bet: advisor must not fold and must explain.
        let config = HandConfig(stacks: Array(repeating: 200, count: 2), buttonIndex: 0, smallBlind: 1, bigBlind: 2, seed: 44)
        let stacks = [200, 200]
        let board = [c(.queen, .spades), c(.jack, .spades), c(.ten, .spades), c(.two, .hearts), c(.three, .diamonds)]
        let deck = riggedDeck(
            holes: [
                0: [c(.ace, .spades), c(.king, .spades)],
                1: [c(.king, .hearts), c(.king, .diamonds)]
            ],
            board: board,
            stacks: stacks,
            button: 0
        )
        let hand = PokerHand(config: config, riggedDeck: deck)
        do {
            try hand.apply(.call, by: 0)
            try hand.apply(.check, by: 1)
            while hand.street != .river {
                guard let seat = hand.actionOn else { break }
                try hand.apply(.check, by: seat)
            }
            // River: seat 1 bets into hero.
            try hand.apply(.bet(to: 20), by: 1)
        } catch {
            XCTFail("setup failed: \(error)")
            return
        }
        let advice = Advisor.advise(hand: hand, seat: 0)
        XCTAssertNotNil(advice)
        XCTAssertNotEqual(advice?.kind, .fold, "royal flush must never be folded")
        XCTAssertFalse(advice?.explanation.isEmpty ?? true)
        XCTAssertGreaterThan(advice?.equity ?? 0, 0.9)
    }
}
