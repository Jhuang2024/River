import XCTest
@testable import RiverKit

/// Made-hand, draw, board-feature, grading and explanation tests (§11-13, §32-36).
final class AnalysisTests: XCTestCase {

    // MARK: - Made-hand classification (§13)

    func testMadeHandClasses() {
        let board = [c(.king, .spades), c(.eight, .diamonds), c(.two, .clubs)]
        XCTAssertEqual(MadeHandAnalyzer.classify(hole: [c(.ace, .hearts), c(.ace, .diamonds)], board: board), .overpair)
        XCTAssertEqual(MadeHandAnalyzer.classify(hole: [c(.king, .hearts), c(.ace, .diamonds)], board: board), .topPairStrongKicker)
        XCTAssertEqual(MadeHandAnalyzer.classify(hole: [c(.king, .hearts), c(.five, .diamonds)], board: board), .topPairWeakKicker)
        XCTAssertEqual(MadeHandAnalyzer.classify(hole: [c(.eight, .hearts), c(.ace, .diamonds)], board: board), .middlePair)
        XCTAssertEqual(MadeHandAnalyzer.classify(hole: [c(.two, .hearts), c(.ace, .diamonds)], board: board), .bottomPair)
        XCTAssertEqual(MadeHandAnalyzer.classify(hole: [c(.five, .hearts), c(.five, .diamonds)], board: board), .underpair)
        XCTAssertEqual(MadeHandAnalyzer.classify(hole: [c(.ace, .hearts), c(.queen, .diamonds)], board: board), .aceHigh)
        XCTAssertEqual(MadeHandAnalyzer.classify(hole: [c(.six, .hearts), c(.seven, .diamonds)], board: board), .air)
        XCTAssertEqual(MadeHandAnalyzer.classify(hole: [c(.king, .hearts), c(.eight, .clubs)], board: board), .twoPair)
        XCTAssertEqual(MadeHandAnalyzer.classify(hole: [c(.eight, .hearts), c(.eight, .clubs)], board: board), .threeOfAKind)
    }

    func testNutDetection() {
        // Royal flush is the literal nuts.
        let analysis = MadeHandAnalyzer.analyze(
            hole: [c(.ace, .spades), c(.king, .spades)],
            board: [c(.queen, .spades), c(.jack, .spades), c(.ten, .spades), c(.two, .hearts), c(.three, .diamonds)],
            opponents: 1
        )
        XCTAssertTrue(analysis.isNuts)
        XCTAssertEqual(analysis.fractionBeaten + 0.0, analysis.fractionBeaten, accuracy: 1e-9)
        XCTAssertGreaterThan(analysis.fractionBeaten, 0.99)
        // A weak pair on a wet board is not near-nuts and is a bluff catcher
        // territory hand at best.
        let weakHand = MadeHandAnalyzer.analyze(
            hole: [c(.eight, .hearts), c(.seven, .clubs)],
            board: [c(.eight, .spades), c(.ten, .spades), c(.jack, .diamonds)],
            opponents: 2
        )
        XCTAssertFalse(weakHand.isNuts)
        XCTAssertFalse(weakHand.isNearNuts)
    }

    // MARK: - Draws (§12)

    func testNutFlushDrawAndBackdoors() {
        let nutDraw = DrawAnalyzer.analyze(
            hole: [c(.ace, .hearts), c(.five, .hearts)],
            board: [c(.king, .hearts), c(.eight, .hearts), c(.two, .clubs)]
        )
        XCTAssertTrue(nutDraw.flushDraw)
        XCTAssertTrue(nutDraw.nutFlushDraw)
        XCTAssertTrue(nutDraw.isStrongDraw)

        let backdoor = DrawAnalyzer.analyze(
            hole: [c(.ace, .hearts), c(.five, .hearts)],
            board: [c(.king, .hearts), c(.eight, .clubs), c(.two, .diamonds)]
        )
        XCTAssertFalse(backdoor.flushDraw)
        XCTAssertTrue(backdoor.backdoorFlushDraw)
    }

    func testDoubleGutshotVersusOpenEnder() {
        // 9-8 on J-7-5: both a 6 (5-9) and a T (7-J) complete - double gutshot.
        let doubleGut = DrawAnalyzer.analyze(
            hole: [c(.nine, .diamonds), c(.eight, .diamonds)],
            board: [c(.jack, .clubs), c(.seven, .hearts), c(.five, .spades)]
        )
        XCTAssertTrue(doubleGut.doubleGutshot)
        XCTAssertFalse(doubleGut.openEndedStraightDraw)
        XCTAssertTrue(doubleGut.isStrongDraw)

        // 9-8 on 7-6-K: 5 or T completes a four-card run - open-ended.
        let openEnder = DrawAnalyzer.analyze(
            hole: [c(.nine, .diamonds), c(.eight, .diamonds)],
            board: [c(.seven, .clubs), c(.six, .hearts), c(.king, .spades)]
        )
        XCTAssertTrue(openEnder.openEndedStraightDraw)
        XCTAssertFalse(openEnder.doubleGutshot)

        // A-K on Q-J-4: only a ten completes - gutshot.
        let gutshot = DrawAnalyzer.analyze(
            hole: [c(.ace, .diamonds), c(.king, .diamonds)],
            board: [c(.queen, .clubs), c(.jack, .hearts), c(.four, .spades)]
        )
        XCTAssertTrue(gutshot.gutshot)
        XCTAssertFalse(gutshot.openEndedStraightDraw)
    }

    // MARK: - Board features (§11)

    func testBoardFeatureNumbers() {
        let dry = BoardTexture.features(for: [c(.king, .spades), c(.eight, .diamonds), c(.two, .clubs)])
        let wet = BoardTexture.features(for: [c(.nine, .hearts), c(.eight, .hearts), c(.seven, .hearts)])
        XCTAssertLessThan(dry.wetness, wet.wetness)
        XCTAssertEqual(wet.flushLevel, 2)
        XCTAssertEqual(dry.flushLevel, 0)
        XCTAssertGreaterThan(wet.straightness, 0.2)
        XCTAssertEqual(dry.pairedness, 0)
        let paired = BoardTexture.features(for: [c(.nine, .hearts), c(.nine, .clubs), c(.two, .diamonds)])
        XCTAssertEqual(paired.pairedness, 1)
        // River boards have zero dynamism.
        let river = BoardTexture.features(for: [c(.nine, .hearts), c(.eight, .hearts), c(.seven, .hearts), c(.two, .clubs), c(.three, .diamonds)])
        XCTAssertEqual(river.dynamism, 0, accuracy: 1e-9)
    }

    // MARK: - Grading semantics (§33-34)

    /// Builds a heads-up river spot with a bet facing the hero.
    private func riverSpot(heroCards: [Card], villainCards: [Card], board: [Card], villainBet: Int) throws -> BotObservation {
        let stacks = [200, 200]
        let holes = [0: heroCards, 1: villainCards]
        let hand = PokerHand(
            config: HandConfig(stacks: stacks, buttonIndex: 0, smallBlind: 1, bigBlind: 2, seed: 0),
            riggedDeck: riggedDeck(holes: holes, board: board, stacks: stacks, button: 0)
        )
        try hand.apply(.call, by: 0)
        try hand.apply(.check, by: 1)
        while hand.street != .river {
            guard let seat = hand.actionOn else { break }
            try hand.apply(.check, by: seat)
        }
        try hand.apply(.bet(to: villainBet), by: 1)
        return try XCTUnwrap(hand.observation(for: 0))
    }

    func testFoldingTheNutsIsGradedAsMistake() throws {
        let obs = try riverSpot(
            heroCards: [c(.ace, .spades), c(.king, .spades)],
            villainCards: [c(.king, .hearts), c(.king, .diamonds)],
            board: [c(.queen, .spades), c(.jack, .spades), c(.ten, .spades), c(.two, .hearts), c(.three, .diamonds)],
            villainBet: 20
        )
        let analysis = try XCTUnwrap(HandAnalyzer.analyzeDecision(
            observation: obs, chosen: .fold, decisionIndex: 0, bigBlind: 2
        ))
        XCTAssertNotEqual(analysis.recommendedLabel, "fold")
        XCTAssertGreaterThan(analysis.evLossBB, 1.0)
        XCTAssertTrue(
            [DecisionGrade.blunder, .significantMistake, .inaccuracy].contains(analysis.grade),
            "folding the nuts graded \(analysis.grade)"
        )
        XCTAssertFalse(analysis.explanation.isEmpty)
    }

    func testRaisingTheNutsIsNotAMistake() throws {
        let obs = try riverSpot(
            heroCards: [c(.ace, .spades), c(.king, .spades)],
            villainCards: [c(.king, .hearts), c(.king, .diamonds)],
            board: [c(.queen, .spades), c(.jack, .spades), c(.ten, .spades), c(.two, .hearts), c(.three, .diamonds)],
            villainBet: 20
        )
        // Raise using a legal target.
        let options = try XCTUnwrap(obs.available.betRaise)
        let analysis = try XCTUnwrap(HandAnalyzer.analyzeDecision(
            observation: obs, chosen: .raise(to: options.minTo + 20), decisionIndex: 0, bigBlind: 2
        ))
        XCTAssertFalse(
            [DecisionGrade.blunder, .significantMistake].contains(analysis.grade),
            "raising the nuts graded \(analysis.grade)"
        )
    }

    /// Result-independence (§33): grading uses only the observation - the
    /// villain's actual cards never enter, so two different villain holdings
    /// with identical public action produce identical grades.
    func testGradingIsResultIndependent() throws {
        let board = [c(.queen, .spades), c(.jack, .spades), c(.four, .diamonds), c(.two, .hearts), c(.nine, .clubs)]
        let hero = [c(.seven, .clubs), c(.six, .clubs)] // air
        let obsVsValue = try riverSpot(heroCards: hero, villainCards: [c(.queen, .hearts), c(.queen, .diamonds)], board: board, villainBet: 60)
        let obsVsBluff = try riverSpot(heroCards: hero, villainCards: [c(.ace, .hearts), c(.five, .hearts)], board: board, villainBet: 60)
        let a = try XCTUnwrap(HandAnalyzer.analyzeDecision(observation: obsVsValue, chosen: .call, decisionIndex: 0, bigBlind: 2))
        let b = try XCTUnwrap(HandAnalyzer.analyzeDecision(observation: obsVsBluff, chosen: .call, decisionIndex: 0, bigBlind: 2))
        XCTAssertEqual(a.grade, b.grade, "the villain's hidden cards must not affect the grade")
        XCTAssertEqual(a.evLossBB, b.evLossBB, accuracy: 1e-9)
        // Calling a large river bet with 7-high air is never praised.
        XCTAssertTrue([DecisionGrade.blunder, .significantMistake, .inaccuracy].contains(a.grade))
    }

    func testExplanationStatesTheMath() throws {
        let obs = try riverSpot(
            heroCards: [c(.eight, .hearts), c(.eight, .clubs)],
            villainCards: [c(.ace, .hearts), c(.queen, .diamonds)],
            board: [c(.king, .spades), c(.seven, .diamonds), c(.two, .clubs), c(.four, .hearts), c(.jack, .clubs)],
            villainBet: 30
        )
        let analysis = try XCTUnwrap(HandAnalyzer.analyzeDecision(observation: obs, chosen: .call, decisionIndex: 0, bigBlind: 2))
        XCTAssertTrue(analysis.explanation.contains("needed about"), "explanation must state the break-even requirement")
        XCTAssertTrue(analysis.explanation.contains("%"))
        XCTAssertFalse(analysis.tags.isEmpty)
        XCTAssertEqual(analysis.requiredEquity, 30.0 / Double(obs.pot + 30), accuracy: 0.001)
    }

    // MARK: - Full-hand analyzer (§32, §47)

    func testHandAnalyzerIsReproducibleAndIndexed() throws {
        // Play a real seeded hand with scripted hero actions.
        var session = CashSessionState(
            config: SessionConfig(handsTarget: 1, seed: 424242, bots: BotProfile.defaultLineup(difficulty: .intermediate)),
            startDate: Date(timeIntervalSince1970: 0)
        )
        let hand = PokerHand(config: session.nextHandConfig())
        let profile = BotProfile.solidRegular(name: "P", symbolName: "person", difficulty: .intermediate)
        while !hand.isComplete {
            guard let seat = hand.actionOn else { break }
            let decision = try XCTUnwrap(BotDecider.decide(hand: hand, seat: seat, profile: profile))
            try hand.apply(decision.action, by: seat)
        }
        session.complete(hand: hand)
        let history = HandHistory(date: Date(timeIntervalSince1970: 5), heroSeat: 0, playerNames: session.playerNames, hand: hand)

        let first = HandAnalyzer.analyze(history: history, iterations: 200)
        let second = HandAnalyzer.analyze(history: history, iterations: 200)
        XCTAssertEqual(first, second, "analysis must be reproducible (§47)")

        let heroDecisionIndices = history.decisions.enumerated().filter { $0.element.seat == 0 }.map { $0.offset }
        XCTAssertEqual(first.map { $0.decisionIndex }, heroDecisionIndices, "every hero decision gets exactly one analysis")
        for analysis in first {
            XCTAssertGreaterThanOrEqual(analysis.evLossBB, 0)
            XCTAssertFalse(analysis.explanation.isEmpty)
            XCTAssertEqual(analysis.analysisVersion, DecisionAnalysis.analysisVersion)
            XCTAssertEqual(analysis.strategyVersion, StrategyConfig.version)
        }
    }

    func testHistoryV2RoundTripAndV1Compatibility() throws {
        var rng = SeededRNG(seed: 30)
        let config = HandConfig(stacks: [100, 100], buttonIndex: 0, smallBlind: 1, bigBlind: 2, seed: 55)
        let hand = PokerHand(config: config)
        playRandomHand(hand, rng: &rng)
        var history = HandHistory(date: Date(timeIntervalSince1970: 0), heroSeat: 0, playerNames: ["You", "Bot"], hand: hand)
        history.analyses = HandAnalyzer.analyze(history: history, iterations: 120)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(history)
        let decoded = try decoder.decode(HandHistory.self, from: data)
        XCTAssertEqual(decoded, history)
        XCTAssertEqual(decoded.schemaVersion, 2)

        // A v1 file (no analyses key) still decodes, with an empty list.
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "analyses")
        json["schemaVersion"] = 1
        let v1Data = try JSONSerialization.data(withJSONObject: json)
        let v1 = try decoder.decode(HandHistory.self, from: v1Data)
        XCTAssertEqual(v1.schemaVersion, 1)
        XCTAssertTrue(v1.analyses.isEmpty)
        XCTAssertEqual(v1.events, history.events)
    }
}
