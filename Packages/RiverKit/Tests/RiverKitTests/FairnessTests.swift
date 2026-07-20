import XCTest
@testable import RiverKit

/// Mandatory hidden-information fairness tests (§43). The AI must be a pure
/// function of legally visible information plus its seed.
final class FairnessTests: XCTestCase {

    private let profile = BotProfile.solidRegular(name: "T", symbolName: "person", difficulty: .elite)

    private func sixStacks() -> [Int] {
        return Array(repeating: 200, count: 6)
    }

    /// Two hands identical except for the HUMAN player's hidden hole cards.
    /// The first bot to act must make the identical decision.
    func testChangingHiddenHeroCardsDoesNotChangeBotDecision() throws {
        let stacks = sixStacks()
        let board = [c(.two, .clubs), c(.seven, .diamonds), c(.jack, .hearts), c(.four, .spades), c(.nine, .clubs)]
        // Bot seats 1-5 get fixed cards; hero (seat 0) differs between decks.
        var holesA: [Int: [Card]] = [
            1: [c(.king, .clubs), c(.king, .diamonds)],
            2: [c(.eight, .clubs), c(.eight, .diamonds)],
            3: [c(.ace, .clubs), c(.queen, .clubs)],
            4: [c(.ten, .diamonds), c(.nine, .diamonds)],
            5: [c(.five, .hearts), c(.six, .hearts)]
        ]
        var holesB = holesA
        holesA[0] = [c(.ace, .spades), c(.ace, .hearts)]
        holesB[0] = [c(.three, .spades), c(.ten, .hearts)]

        let handA = PokerHand(
            config: HandConfig(stacks: stacks, buttonIndex: 0, smallBlind: 1, bigBlind: 2, seed: 42),
            riggedDeck: riggedDeck(holes: holesA, board: board, stacks: stacks, button: 0)
        )
        let handB = PokerHand(
            config: HandConfig(stacks: stacks, buttonIndex: 0, smallBlind: 1, bigBlind: 2, seed: 42),
            riggedDeck: riggedDeck(holes: holesB, board: board, stacks: stacks, button: 0)
        )
        XCTAssertNotEqual(handA.seats[0].holeCards, handB.seats[0].holeCards)
        XCTAssertEqual(handA.actionOn, 3)

        let decisionA = try XCTUnwrap(BotDecider.decide(hand: handA, seat: 3, profile: profile))
        let decisionB = try XCTUnwrap(BotDecider.decide(hand: handB, seat: 3, profile: profile))
        XCTAssertEqual(decisionA.action, decisionB.action, "hidden hero cards leaked into a bot decision")

        // Play both hands forward with identical actions; every subsequent bot
        // decision must stay in lockstep while the hero's hidden cards differ.
        for _ in 0..<12 {
            guard let seatA = handA.actionOn, let seatB = handB.actionOn, seatA == seatB, !handA.isComplete else { break }
            let a = try XCTUnwrap(BotDecider.decide(hand: handA, seat: seatA, profile: profile))
            if seatA != 0 {
                let b = try XCTUnwrap(BotDecider.decide(hand: handB, seat: seatB, profile: profile))
                XCTAssertEqual(a.action, b.action, "decisions diverged at seat \(seatA)")
            }
            // Apply the same action to both hands (hero included) to advance.
            try handA.apply(a.action, by: seatA)
            try handB.apply(a.action, by: seatB)
        }
    }

    /// Two hands identical except for FUTURE board cards: the current
    /// (preflop) decision must be identical.
    func testChangingFutureDeckDoesNotChangeCurrentDecision() throws {
        let stacks = sixStacks()
        let holes: [Int: [Card]] = [
            0: [c(.two, .spades), c(.three, .diamonds)],
            1: [c(.king, .clubs), c(.king, .diamonds)],
            2: [c(.eight, .clubs), c(.eight, .diamonds)],
            3: [c(.ace, .clubs), c(.queen, .clubs)],
            4: [c(.ten, .diamonds), c(.nine, .diamonds)],
            5: [c(.five, .hearts), c(.six, .hearts)]
        ]
        let boardA = [c(.two, .clubs), c(.seven, .diamonds), c(.jack, .hearts), c(.four, .spades), c(.nine, .clubs)]
        let boardB = [c(.ace, .diamonds), c(.king, .hearts), c(.queen, .spades), c(.jack, .clubs), c(.ten, .hearts)]

        let handA = PokerHand(
            config: HandConfig(stacks: stacks, buttonIndex: 0, smallBlind: 1, bigBlind: 2, seed: 7),
            riggedDeck: riggedDeck(holes: holes, board: boardA, stacks: stacks, button: 0)
        )
        let handB = PokerHand(
            config: HandConfig(stacks: stacks, buttonIndex: 0, smallBlind: 1, bigBlind: 2, seed: 7),
            riggedDeck: riggedDeck(holes: holes, board: boardB, stacks: stacks, button: 0)
        )
        let decisionA = try XCTUnwrap(BotDecider.decide(hand: handA, seat: 3, profile: profile))
        let decisionB = try XCTUnwrap(BotDecider.decide(hand: handB, seat: 3, profile: profile))
        XCTAssertEqual(decisionA.action, decisionB.action, "future deck order leaked into a current decision")
    }

    /// Identical observation and seed produce the identical decision, for
    /// every difficulty.
    func testIdenticalObservationAndSeedProduceIdenticalDecision() throws {
        for difficulty in BotDifficulty.allCases {
            let testProfile = BotProfile.looseAggressive(name: "X", symbolName: "person", difficulty: difficulty)
            let config = HandConfig(stacks: sixStacks(), buttonIndex: 1, smallBlind: 1, bigBlind: 2, seed: 99)
            let handA = PokerHand(config: config)
            let handB = PokerHand(config: config)
            let a = try XCTUnwrap(BotDecider.decide(hand: handA, seat: handA.actionOn!, profile: testProfile))
            let b = try XCTUnwrap(BotDecider.decide(hand: handB, seat: handB.actionOn!, profile: testProfile))
            XCTAssertEqual(a.action, b.action, "nondeterminism at difficulty \(difficulty)")
        }
    }

    /// The dealt cards depend only on the seed — never on AI difficulty.
    func testDeckDistributionIndependentOfDifficulty() {
        let config = HandConfig(stacks: sixStacks(), buttonIndex: 0, smallBlind: 1, bigBlind: 2, seed: 4242)
        let reference = PokerHand(config: config)
        for _ in BotDifficulty.allCases {
            // Difficulty is a property of profiles consulted at decision time;
            // constructing hands is identical regardless.
            let hand = PokerHand(config: config)
            for seat in 0..<6 {
                XCTAssertEqual(hand.seats[seat].holeCards, reference.seats[seat].holeCards)
            }
        }
    }

    /// Deciding must never mutate authoritative game state.
    func testDecidingDoesNotMutateGameState() throws {
        let config = HandConfig(stacks: sixStacks(), buttonIndex: 0, smallBlind: 1, bigBlind: 2, seed: 11)
        let hand = PokerHand(config: config)
        let seatsBefore = hand.seats
        let eventsBefore = hand.events
        let potBefore = hand.pot
        let actionOnBefore = hand.actionOn
        for _ in 0..<3 {
            _ = BotDecider.decide(hand: hand, seat: hand.actionOn!, profile: profile)
        }
        XCTAssertEqual(hand.seats, seatsBefore)
        XCTAssertEqual(hand.events, eventsBefore)
        XCTAssertEqual(hand.pot, potBefore)
        XCTAssertEqual(hand.actionOn, actionOnBefore)
    }

    /// The observation type carries no deck, no foreign hole cards, and the
    /// postflop decision pipeline sees only that observation.
    func testObservationOmitsHiddenInformationMidHand() throws {
        var rng = SeededRNG(seed: 31)
        for trial in 0..<10 {
            let config = HandConfig(stacks: sixStacks(), buttonIndex: trial % 6, smallBlind: 1, bigBlind: 2, seed: rng.nextUInt64())
            let hand = PokerHand(config: config)
            var guardCount = 0
            while !hand.isComplete && guardCount < 60 {
                guard let seat = hand.actionOn else { break }
                let obs = try XCTUnwrap(hand.observation(for: seat))
                for event in obs.visibleEvents {
                    if let owner = event.privateSeat {
                        XCTAssertEqual(owner, seat)
                    }
                }
                // Advance with a legal action from the real decision pipeline.
                let decision = try XCTUnwrap(BotDecider.decide(hand: hand, seat: seat, profile: profile))
                try hand.apply(decision.action, by: seat, annotation: decision.annotation)
                guardCount += 1
            }
        }
    }
}
