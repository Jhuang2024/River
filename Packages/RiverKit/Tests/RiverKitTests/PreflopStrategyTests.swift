import XCTest
@testable import RiverKit

/// Deterministic preflop scenario tests (§41). Intermediate difficulty uses
/// pure (unmixed) strategies, so expectations are exact; assertions describe
/// broad strategic behaviour, not single forced actions where several lines
/// are defensible.
final class PreflopStrategyTests: XCTestCase {

    /// Solid regular at Intermediate: pure strategies, disciplined baseline.
    private let solid = BotProfile.solidRegular(name: "S", symbolName: "person", difficulty: .intermediate)

    private func makeHand(holes: [Int: [Card]], button: Int = 0, stacks: [Int]? = nil, seed: UInt64 = 1) -> PokerHand {
        let allStacks = stacks ?? Array(repeating: 200, count: 6)
        let board = [c(.two, .clubs), c(.seven, .diamonds), c(.jack, .hearts), c(.four, .spades), c(.nine, .clubs)]
        var fullHoles = holes
        // Fixed filler cards, chosen to never collide with any test's hero
        // cards or the rigged board.
        let filler: [[Card]] = [
            [c(.three, .hearts), c(.eight, .spades)],
            [c(.three, .diamonds), c(.eight, .hearts)],
            [c(.six, .hearts), c(.ten, .clubs)],
            [c(.four, .hearts), c(.nine, .diamonds)],
            [c(.three, .clubs), c(.eight, .diamonds)],
            [c(.six, .diamonds), c(.ten, .spades)]
        ]
        var fillerIndex = 0
        for seat in 0..<allStacks.count where fullHoles[seat] == nil {
            fullHoles[seat] = filler[fillerIndex]
            fillerIndex += 1
        }
        return PokerHand(
            config: HandConfig(stacks: allStacks, buttonIndex: button, smallBlind: 1, bigBlind: 2, seed: seed),
            riggedDeck: riggedDeck(holes: fullHoles, board: board, stacks: allStacks, button: button)
        )
    }

    private func decision(_ hand: PokerHand, seat: Int, profile: BotProfile? = nil) -> PlayerAction {
        guard let full = BotDecider.decide(hand: hand, seat: seat, profile: profile ?? solid) else {
            XCTFail("no decision for seat \(seat)")
            return .fold
        }
        return full.action
    }

    // MARK: - Openings

    func testPremiumOpensFromUnderTheGun() {
        // Button 0 → UTG is seat 3, first to act.
        let hand = makeHand(holes: [3: [c(.ace, .spades), c(.ace, .hearts)]])
        let action = decision(hand, seat: 3)
        XCTAssertEqual(action.kind, .raise, "aces must open")
        // Standard open: ~2.3 BB at blinds 1/2 → to 4-6 chips.
        XCTAssertTrue((4...6).contains(action.toAmount), "open size \(action.toAmount) out of standard band")
    }

    func testTrashFoldsFromUnderTheGun() {
        let hand = makeHand(holes: [3: [c(.seven, .clubs), c(.two, .diamonds)]])
        XCTAssertEqual(decision(hand, seat: 3).kind, .fold)
    }

    func testPositionalAwareness() throws {
        // K9s: outside a disciplined UTG range, inside the button range.
        let k9s = [c(.king, .spades), c(.nine, .spades)]
        let utgHand = makeHand(holes: [3: k9s])
        XCTAssertEqual(decision(utgHand, seat: 3).kind, .fold, "K9s is an UTG fold for a solid regular")

        let buttonHand = makeHand(holes: [0: k9s])
        try buttonHand.apply(.fold, by: 3)
        try buttonHand.apply(.fold, by: 4)
        try buttonHand.apply(.fold, by: 5)
        XCTAssertEqual(buttonHand.actionOn, 0)
        XCTAssertEqual(decision(buttonHand, seat: 0).kind, .raise, "K9s is a button open")
    }

    // MARK: - Facing an open

    func testBigBlindDefendsReasonableHandAgainstOpen() throws {
        // Button (seat 0) opens; BB (seat 2) holds KQo: defend by calling.
        let hand = makeHand(holes: [2: [c(.king, .clubs), c(.queen, .diamonds)]])
        try hand.apply(.fold, by: 3)
        try hand.apply(.fold, by: 4)
        try hand.apply(.fold, by: 5)
        try hand.apply(.raise(to: 5), by: 0)
        try hand.apply(.fold, by: 1)
        XCTAssertEqual(hand.actionOn, 2)
        let action = decision(hand, seat: 2)
        XCTAssertEqual(action.kind, .call, "KQo defends the big blind against a button open")
    }

    func testBigBlindFoldsTrashAgainstOpen() throws {
        let hand = makeHand(holes: [2: [c(.seven, .clubs), c(.two, .diamonds)]])
        try hand.apply(.fold, by: 3)
        try hand.apply(.fold, by: 4)
        try hand.apply(.fold, by: 5)
        try hand.apply(.raise(to: 5), by: 0)
        try hand.apply(.fold, by: 1)
        XCTAssertEqual(decision(hand, seat: 2).kind, .fold)
    }

    func testThreeBetsWithValueHand() throws {
        // Hijack (seat 4) opens; button (seat 0) holds KK: three-bet.
        let hand = makeHand(holes: [0: [c(.king, .clubs), c(.king, .diamonds)]])
        try hand.apply(.fold, by: 3)
        try hand.apply(.raise(to: 5), by: 4)
        try hand.apply(.fold, by: 5)
        XCTAssertEqual(hand.actionOn, 0)
        let action = decision(hand, seat: 0)
        XCTAssertEqual(action.kind, .raise, "kings must three-bet")
        // In-position three-bet ≈ 3× the open.
        XCTAssertTrue((12...20).contains(action.toAmount), "3-bet size \(action.toAmount) unreasonable over an open to 5")
    }

    // MARK: - Facing a four-bet

    func testAcesContinueVersusFourBet() throws {
        // Seat 3 opens, button 3-bets, seat 3 four-bets; back on the button
        // holding aces: never fold (shove or call are both acceptable).
        let hand = makeHand(holes: [0: [c(.ace, .spades), c(.ace, .hearts)]])
        try hand.apply(.raise(to: 5), by: 3)
        try hand.apply(.fold, by: 4)
        try hand.apply(.fold, by: 5)
        try hand.apply(.raise(to: 15), by: 0)   // hero three-bets
        try hand.apply(.fold, by: 1)
        try hand.apply(.fold, by: 2)
        try hand.apply(.raise(to: 40), by: 3)   // opener four-bets
        XCTAssertEqual(hand.actionOn, 0)
        let action = decision(hand, seat: 0)
        XCTAssertNotEqual(action.kind, .fold, "aces never fold to a four-bet")
    }

    // MARK: - Short stacks (§26)

    func testShortStackShovesInsteadOfMiniRaising() throws {
        // 20-chip stacks at 1/2 = 10 BB effective: push/fold mode. Button
        // holds A5s - a standard shove.
        let stacks = Array(repeating: 20, count: 6)
        let hand = makeHand(holes: [0: [c(.ace, .spades), c(.five, .spades)]], stacks: stacks)
        try hand.apply(.fold, by: 3)
        try hand.apply(.fold, by: 4)
        try hand.apply(.fold, by: 5)
        XCTAssertEqual(hand.actionOn, 0)
        let action = decision(hand, seat: 0)
        XCTAssertEqual(action.kind, .raise)
        XCTAssertEqual(action.toAmount, 20, "short-stack raise must be the full shove")
    }

    func testShortStackFoldsTrashDespiteButton() throws {
        let stacks = Array(repeating: 20, count: 6)
        let hand = makeHand(holes: [0: [c(.seven, .clubs), c(.two, .diamonds)]], stacks: stacks)
        try hand.apply(.fold, by: 3)
        try hand.apply(.fold, by: 4)
        try hand.apply(.fold, by: 5)
        XCTAssertEqual(decision(hand, seat: 0).kind, .fold)
    }

    func testDeepAndShortStrategiesDiffer() throws {
        // The same speculative button hand min-opens deep but is a shove/fold
        // decision short - sizes must differ drastically (§26-27).
        let hole = [c(.ace, .spades), c(.five, .spades)]
        let deep = makeHand(holes: [0: hole])
        try deep.apply(.fold, by: 3)
        try deep.apply(.fold, by: 4)
        try deep.apply(.fold, by: 5)
        let deepAction = decision(deep, seat: 0)
        XCTAssertEqual(deepAction.kind, .raise)
        XCTAssertLessThan(deepAction.toAmount, 10, "deep-stack open is a normal size, not a shove")

        let short = makeHand(holes: [0: hole], stacks: Array(repeating: 16, count: 6))
        try short.apply(.fold, by: 3)
        try short.apply(.fold, by: 4)
        try short.apply(.fold, by: 5)
        let shortAction = decision(short, seat: 0)
        XCTAssertEqual(shortAction.toAmount, 16, "short-stack strategy shoves")
    }

    // MARK: - Positions (§5)

    func testPositionMapping() {
        // 6-max: offsets from button.
        XCTAssertEqual(TablePosition.position(offsetFromButton: 0, playerCount: 6), .button)
        XCTAssertEqual(TablePosition.position(offsetFromButton: 1, playerCount: 6), .smallBlind)
        XCTAssertEqual(TablePosition.position(offsetFromButton: 2, playerCount: 6), .bigBlind)
        XCTAssertEqual(TablePosition.position(offsetFromButton: 3, playerCount: 6), .underTheGun)
        XCTAssertEqual(TablePosition.position(offsetFromButton: 4, playerCount: 6), .hijack)
        XCTAssertEqual(TablePosition.position(offsetFromButton: 5, playerCount: 6), .cutoff)
        // 4-handed: UTG disappears last.
        XCTAssertEqual(TablePosition.position(offsetFromButton: 3, playerCount: 4), .cutoff)
        // Heads-up.
        XCTAssertEqual(TablePosition.position(offsetFromButton: 0, playerCount: 2), .button)
        XCTAssertEqual(TablePosition.position(offsetFromButton: 1, playerCount: 2), .bigBlind)
    }

    func testArchetypeRangesDiffer() {
        // The same marginal hand from the hijack: a nit folds, a maniac raises.
        let hole = [c(.queen, .diamonds), c(.ten, .diamonds)] // QTs
        let nit = BotProfile.nit(name: "N", symbolName: "person", difficulty: .intermediate)
        let maniac = BotProfile.maniac(name: "M", symbolName: "person", difficulty: .intermediate)

        let handForNit = makeHand(holes: [4: hole])
        try? handForNit.apply(.fold, by: 3)
        XCTAssertEqual(handForNit.actionOn, 4)
        let nitAction = decision(handForNit, seat: 4, profile: nit)

        let handForManiac = makeHand(holes: [4: hole])
        try? handForManiac.apply(.fold, by: 3)
        let maniacAction = decision(handForManiac, seat: 4, profile: maniac)

        XCTAssertEqual(nitAction.kind, .fold, "QTs from the hijack is outside a nit's range")
        XCTAssertEqual(maniacAction.kind, .raise, "a maniac opens QTs without hesitation")
    }
}
