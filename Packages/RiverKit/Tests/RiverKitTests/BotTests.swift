import XCTest
@testable import RiverKit

final class BotTests: XCTestCase {

    private func lineup() -> [BotProfile] {
        return BotProfile.defaultLineup(difficulty: .intermediate)
    }

    /// Bots (occupying every seat, including seat 0) must complete whole
    /// sessions with only legal actions and exact chip conservation.
    func testBotsPlayFullSessionLegally() throws {
        let bots = lineup()
        var session = CashSessionState(
            config: SessionConfig(seed: 987654321, bots: bots),
            startDate: Date(timeIntervalSince1970: 0)
        )
        let heroProfile = BotProfile.looseAggressive(name: "HeroBot", symbolName: "person", difficulty: .intermediate)

        var handsCompleted = 0
        while session.canContinue {
            let config = session.nextHandConfig()
            let hand = PokerHand(config: config)
            let totalBefore = config.stacks.reduce(0, +)
            var actionCount = 0
            while !hand.isComplete {
                guard let seat = hand.actionOn else {
                    XCTFail("no actor but hand incomplete")
                    return
                }
                let profile = seat == heroSeatIndex ? heroProfile : session.botProfile(forSeat: seat)!
                guard let decision = BotDecider.decide(hand: hand, seat: seat, profile: profile) else {
                    XCTFail("bot could not decide")
                    return
                }
                XCTAssertNoThrow(try hand.apply(decision.action, by: seat, annotation: decision.annotation), "bot chose illegal action \(decision.action)")
                actionCount += 1
                if actionCount > 400 {
                    XCTFail("bot hand exceeded 400 actions")
                    return
                }
            }
            XCTAssertEqual(hand.seats.reduce(0) { $0 + $1.stack }, totalBefore)
            session.complete(hand: hand)
            handsCompleted += 1
            if handsCompleted > 25 { break }
        }
        XCTAssertEqual(session.handsPlayed, 20)
        XCTAssertTrue(session.isFinished)
    }

    /// Same session seed → byte-identical sequence of events across runs.
    func testBotSessionsAreDeterministic() throws {
        func run() throws -> [[HandEvent]] {
            let bots = lineup()
            var session = CashSessionState(
                config: SessionConfig(handsTarget: 5, seed: 1122334455, bots: bots),
                startDate: Date(timeIntervalSince1970: 0)
            )
            let heroProfile = BotProfile.nit(name: "HeroBot", symbolName: "person", difficulty: .intermediate)
            var allEvents: [[HandEvent]] = []
            while session.canContinue {
                let hand = PokerHand(config: session.nextHandConfig())
                while !hand.isComplete {
                    guard let seat = hand.actionOn else { break }
                    let profile = seat == heroSeatIndex ? heroProfile : session.botProfile(forSeat: seat)!
                    guard let decision = BotDecider.decide(hand: hand, seat: seat, profile: profile) else { break }
                    try hand.apply(decision.action, by: seat)
                }
                allEvents.append(hand.events)
                session.complete(hand: hand)
            }
            return allEvents
        }
        let first = try run()
        let second = try run()
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 5)
    }

    /// Hidden-information isolation: a bot's observation must never contain
    /// another seat's hole cards, no matter when it is built.
    func testObservationsNeverLeakHiddenCards() throws {
        var rng = SeededRNG(seed: 31337)
        for trial in 0..<40 {
            let config = HandConfig(
                stacks: Array(repeating: 200, count: 6),
                buttonIndex: trial % 6,
                smallBlind: 1,
                bigBlind: 2,
                seed: rng.nextUInt64(),
                handNumber: trial
            )
            let hand = PokerHand(config: config)
            while !hand.isComplete {
                guard let seat = hand.actionOn, let available = hand.availableActions(for: seat) else { break }
                let observation = try XCTUnwrap(hand.observation(for: seat))
                // Own cards only.
                XCTAssertEqual(observation.holeCards, hand.seats[seat].holeCards)
                // No dealtHoleCards event for any other seat survives filtering.
                for event in observation.visibleEvents {
                    if let owner = event.privateSeat {
                        XCTAssertEqual(owner, seat, "observation leaked seat \(owner)'s cards to seat \(seat)")
                    }
                }
                // Opponent public state carries no cards at all (by type), and
                // covers every other participating seat.
                XCTAssertEqual(observation.opponents.count, 5)
                XCTAssertFalse(observation.opponents.contains { $0.seatIndex == seat })
                let action = randomLegalAction(available, rng: &rng)
                try hand.apply(action, by: seat)
            }
        }
    }

    /// Personalities must actually differ: over many hands the nit folds far
    /// more preflop than the calling station.
    func testArchetypesBehaveDistinctly() throws {
        var nitVoluntary = 0
        var stationVoluntary = 0
        var handsCounted = 0
        let nit = BotProfile.nit(name: "N", symbolName: "person", difficulty: .intermediate)
        let station = BotProfile.callingStation(name: "S", symbolName: "person", difficulty: .intermediate)
        let filler = BotProfile.looseAggressive(name: "L", symbolName: "person", difficulty: .intermediate)

        for trial in 0..<120 {
            let config = HandConfig(
                stacks: Array(repeating: 200, count: 6),
                buttonIndex: trial % 6,
                smallBlind: 1,
                bigBlind: 2,
                seed: 5000 &+ UInt64(trial),
                handNumber: trial
            )
            let hand = PokerHand(config: config)
            // Seat 0 = nit, seat 1 = station, rest filler.
            func profile(_ seat: Int) -> BotProfile {
                if seat == 0 { return nit }
                if seat == 1 { return station }
                return filler
            }
            while !hand.isComplete {
                guard let seat = hand.actionOn else { break }
                guard let decision = BotDecider.decide(hand: hand, seat: seat, profile: profile(seat)) else { break }
                try hand.apply(decision.action, by: seat)
            }
            handsCounted += 1
            for decision in hand.decisions where decision.street == .preflop {
                let voluntary = decision.chosen.kind == .call || decision.chosen.kind == .raise || decision.chosen.kind == .bet
                if decision.seat == 0 && voluntary { nitVoluntary += 1 }
                if decision.seat == 1 && voluntary { stationVoluntary += 1 }
            }
        }
        XCTAssertGreaterThan(handsCounted, 100)
        XCTAssertGreaterThan(stationVoluntary, nitVoluntary * 2, "calling station (\(stationVoluntary)) should enter far more pots than nit (\(nitVoluntary))")
    }

    func testEquityEstimatorIsDeterministicAndSane() {
        var rngA = SeededRNG(seed: 12)
        var rngB = SeededRNG(seed: 12)
        let hole = [c(.ace, .spades), c(.ace, .hearts)]
        let a = EquityEstimator.equityVsRandom(hole: hole, board: [], opponents: 1, iterations: 500, rng: &rngA)
        let b = EquityEstimator.equityVsRandom(hole: hole, board: [], opponents: 1, iterations: 500, rng: &rngB)
        XCTAssertEqual(a, b, "same seed must give identical estimates")
        XCTAssertGreaterThan(a.equity, 0.75, "aces should be a big favorite heads-up")

        var rngC = SeededRNG(seed: 13)
        let trash = EquityEstimator.equityVsRandom(hole: [c(.seven, .clubs), c(.two, .diamonds)], board: [], opponents: 3, iterations: 500, rng: &rngC)
        XCTAssertLessThan(trash.equity, 0.35, "72o multiway should be weak")

        // Made nuts on the river: equity must be near 1.
        var rngD = SeededRNG(seed: 14)
        let nuts = EquityEstimator.equityVsRandom(
            hole: [c(.ace, .spades), c(.king, .spades)],
            board: [c(.queen, .spades), c(.jack, .spades), c(.ten, .spades), c(.two, .hearts), c(.three, .diamonds)],
            opponents: 2,
            iterations: 300,
            rng: &rngD
        )
        XCTAssertGreaterThan(nuts.equity, 0.99)
    }

    func testDrawDetection() {
        // Flush draw + open-ended straight draw.
        let combo = EquityEstimator.detectDraws(
            hole: [c(.nine, .hearts), c(.eight, .hearts)],
            board: [c(.seven, .hearts), c(.six, .hearts), c(.two, .clubs)]
        )
        XCTAssertTrue(combo.flushDraw)
        XCTAssertTrue(combo.openEndedStraightDraw)
        // Gutshot only.
        let gutshot = EquityEstimator.detectDraws(
            hole: [c(.nine, .clubs), c(.eight, .diamonds)],
            board: [c(.six, .hearts), c(.five, .spades), c(.ace, .clubs)]
        )
        XCTAssertFalse(gutshot.flushDraw)
        XCTAssertFalse(gutshot.openEndedStraightDraw)
        XCTAssertTrue(gutshot.gutshotStraightDraw)
        // No draws on the river.
        let river = EquityEstimator.detectDraws(
            hole: [c(.nine, .hearts), c(.eight, .hearts)],
            board: [c(.seven, .hearts), c(.six, .hearts), c(.two, .clubs), c(.king, .diamonds), c(.queen, .spades)]
        )
        XCTAssertFalse(river.flushDraw)
    }

    func testPreflopHandLabelsAndChen() {
        XCTAssertEqual(PreflopHands.label(for: [c(.ace, .spades), c(.king, .spades)]), "AKs")
        XCTAssertEqual(PreflopHands.label(for: [c(.king, .hearts), c(.ace, .spades)]), "AKo")
        XCTAssertEqual(PreflopHands.label(for: [c(.ten, .hearts), c(.ten, .spades)]), "TT")
        XCTAssertEqual(PreflopHands.chenScore(for: [c(.ace, .spades), c(.ace, .hearts)]), 20)
        XCTAssertEqual(PreflopHands.chenScore(for: [c(.ace, .spades), c(.king, .spades)]), 12)
        // AA must outrank AKs, which must outrank 72o.
        let aa = PreflopHands.chenScore(for: [c(.ace, .spades), c(.ace, .hearts)])
        let aks = PreflopHands.chenScore(for: [c(.ace, .spades), c(.king, .spades)])
        let trash = PreflopHands.chenScore(for: [c(.seven, .clubs), c(.two, .diamonds)])
        XCTAssertTrue(aa > aks && aks > trash)
    }
}
