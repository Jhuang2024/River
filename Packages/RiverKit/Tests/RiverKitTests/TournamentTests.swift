import XCTest
@testable import RiverKit

/// Sit-and-Go state machine (§19–20): structures, blind levels, eliminations,
/// placings, prizes and persistence.
final class TournamentTests: XCTestCase {

    private func makeState(stacks: [Int]? = nil, structure: TournamentStructure = .standard) -> TournamentState {
        let bots = Array(BotProfile.defaultLineup(difficulty: .beginner).prefix((stacks?.count ?? 6) - 1))
        let config = TournamentConfig(structure: structure, seed: 99, bots: bots)
        var state = TournamentState(config: config, startDate: Date(timeIntervalSince1970: 0))
        if let stacks {
            state.stacks = stacks
        }
        return state
    }

    func testAllShippedStructuresValidate() {
        for structure in TournamentStructure.all {
            XCTAssertEqual(structure.validate(), [], "structure \(structure.id) failed validation")
        }
    }

    func testBlindLevelsAdvanceOnHandCountAndClampAtTheTop() {
        var state = makeState()
        XCTAssertEqual(state.currentLevelIndex, 0)
        XCTAssertEqual(state.handsUntilNextLevel, state.config.structure.handsPerLevel)

        state.handsPlayed = state.config.structure.handsPerLevel
        XCTAssertEqual(state.currentLevelIndex, 1)

        state.handsPlayed = 10_000
        XCTAssertEqual(state.currentLevelIndex, state.config.structure.levels.count - 1)
        XCTAssertNil(state.handsUntilNextLevel, "final level never announces a next level")
    }

    func testNextHandConfigCarriesTheCurrentLevelAndIsDeterministic() {
        var state = makeState()
        state.handsPlayed = state.config.structure.handsPerLevel // level 2
        let level = state.currentLevel
        guard let first = state.nextHandConfig(), let second = state.nextHandConfig() else {
            return XCTFail("expected a next hand")
        }
        XCTAssertEqual(first.smallBlind, level.smallBlind)
        XCTAssertEqual(first.bigBlind, level.bigBlind)
        XCTAssertEqual(first.ante, level.ante)
        XCTAssertEqual(first.seed, second.seed, "same state must produce the same deal seed")

        state.handsPlayed += 1
        XCTAssertNotEqual(state.nextHandConfig()?.seed, first.seed, "each hand gets a fresh seed")
    }

    /// Plays a real rigged hand in which the short stack is eliminated and
    /// checks every downstream consequence: stacks, elimination order, place,
    /// prize, bubble state and button movement.
    func testEliminationUpdatesPlacesPrizesAndBubble() throws {
        var state = makeState(stacks: [100, 40, 100])
        XCTAssertTrue(state.onBubble, "three left with two paid is the bubble")

        let stacks = state.stacks
        let board = [c(.two, .spades), c(.seven, .diamonds), c(.eight, .clubs), c(.three, .hearts), c(.four, .spades)]
        let deck = riggedDeck(
            holes: [
                0: [c(.nine, .clubs), c(.six, .diamonds)],
                1: [c(.queen, .clubs), c(.queen, .diamonds)],
                2: [c(.ace, .clubs), c(.ace, .diamonds)]
            ],
            board: board, stacks: stacks, button: state.buttonIndex
        )
        let config = HandConfig(stacks: stacks, buttonIndex: state.buttonIndex, smallBlind: 10, bigBlind: 20, seed: 1)
        let hand = PokerHand(config: config, riggedDeck: deck)
        try hand.apply(.fold, by: 0)
        try hand.apply(.raise(to: 40), by: 1) // short stack all-in with queens
        try hand.apply(.call, by: 2)          // aces call and hold
        XCTAssertTrue(hand.isComplete)

        state.complete(hand: hand)
        XCTAssertEqual(state.stacks[1], 0)
        XCTAssertEqual(state.eliminationOrder, [1])
        XCTAssertEqual(state.playersRemaining, 2)
        XCTAssertFalse(state.onBubble, "bubble bursts with the third-place bust")
        XCTAssertEqual(state.place(of: 1), 3)
        XCTAssertEqual(state.prize(of: 1), 0, "third of three is outside the payouts")
        XCTAssertFalse(state.isFinished)
        XCTAssertTrue(state.canContinue)
        XCTAssertGreaterThan(state.stacks[state.buttonIndex], 0, "button must land on a live seat")
    }

    func testHeroBustEndsTheTournamentImmediately() throws {
        var state = makeState(stacks: [30, 100, 100])
        let stacks = state.stacks
        let board = [c(.two, .spades), c(.seven, .diamonds), c(.eight, .clubs), c(.three, .hearts), c(.four, .spades)]
        let deck = riggedDeck(
            holes: [
                0: [c(.queen, .clubs), c(.queen, .diamonds)],
                1: [c(.ace, .clubs), c(.ace, .diamonds)],
                2: [c(.nine, .clubs), c(.six, .diamonds)]
            ],
            board: board, stacks: stacks, button: state.buttonIndex
        )
        let config = HandConfig(stacks: stacks, buttonIndex: state.buttonIndex, smallBlind: 10, bigBlind: 20, seed: 2)
        let hand = PokerHand(config: config, riggedDeck: deck)
        try hand.apply(.call, by: 0)           // hero flats with queens
        try hand.apply(.raise(to: 100), by: 1) // aces shove
        try hand.apply(.fold, by: 2)
        try hand.apply(.call, by: 0)           // hero calls off the last 10
        XCTAssertTrue(hand.isComplete)

        state.complete(hand: hand)
        XCTAssertTrue(state.heroEliminated)
        XCTAssertTrue(state.isFinished, "hero elimination fixes the hero's result")
        XCTAssertFalse(state.canContinue)
        XCTAssertEqual(state.place(of: heroSeatIndex), 3)
    }

    func testWinnerTakesFirstPlaceAndFirstPrize() {
        var state = makeState(stacks: [200, 0, 0])
        state.eliminationOrder = [2, 1]
        state.isFinished = true
        XCTAssertEqual(state.place(of: 0), 1)
        XCTAssertEqual(state.prize(of: 0), state.payoutsByPlace[0])
        XCTAssertEqual(state.place(of: 1), 2)
        XCTAssertEqual(state.prize(of: 1), state.payoutsByPlace[1])
        XCTAssertEqual(state.place(of: 2), 3)
    }

    func testHeroPrizeEquityStaysInsideThePrizePool() {
        let state = makeState(stacks: [2500, 1000, 1000, 1000, 1000, 2500])
        XCTAssertGreaterThan(state.heroPrizeEquity, 0)
        XCTAssertLessThan(state.heroPrizeEquity, Double(state.config.prizePool))
    }

    func testTournamentStateRoundTripsThroughCodable() throws {
        var state = makeState()
        state.handsPlayed = 13
        state.stacks = [3000, 0, 1200, 900, 1500, 2400]
        state.eliminationOrder = [1]
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(TournamentState.self, from: data)
        XCTAssertEqual(decoded, state)
    }

    func testTournamentContextMatchesState() {
        var state = makeState(stacks: [2000, 1000, 0, 900, 800, 1300])
        state.eliminationOrder = [2]
        let context = state.tournamentContext()
        XCTAssertEqual(context.playersRemaining, 5)
        XCTAssertEqual(context.stacks, state.stacks)
        XCTAssertEqual(context.payouts, state.payoutsByPlace)
        XCTAssertEqual(context.levelIndex, state.currentLevelIndex)
    }
}
