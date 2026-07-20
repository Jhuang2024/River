import XCTest
@testable import RiverKit

final class BettingRulesTests: XCTestCase {

    private func sixMaxConfig(seed: UInt64 = 1, button: Int = 0, stacks: [Int]? = nil) -> HandConfig {
        return HandConfig(
            stacks: stacks ?? Array(repeating: 200, count: 6),
            buttonIndex: button,
            smallBlind: 1,
            bigBlind: 2,
            seed: seed
        )
    }

    func testBlindsAndFirstToActSixMax() {
        let hand = PokerHand(config: sixMaxConfig(button: 0))
        // Button 0 → SB 1, BB 2, UTG (first to act) 3.
        XCTAssertEqual(hand.smallBlindSeat, 1)
        XCTAssertEqual(hand.bigBlindSeat, 2)
        XCTAssertEqual(hand.actionOn, 3)
        XCTAssertEqual(hand.seats[1].committedThisStreet, 1)
        XCTAssertEqual(hand.seats[2].committedThisStreet, 2)
        XCTAssertEqual(hand.pot, 3)
        XCTAssertEqual(hand.currentBet, 2)
    }

    func testHeadsUpButtonPostsSmallBlindAndActsFirstPreflop() throws {
        let hand = PokerHand(config: HandConfig(stacks: [100, 100], buttonIndex: 0, smallBlind: 1, bigBlind: 2, seed: 3))
        XCTAssertEqual(hand.smallBlindSeat, 0)
        XCTAssertEqual(hand.bigBlindSeat, 1)
        XCTAssertEqual(hand.actionOn, 0)
        // Button calls, BB checks → flop. Postflop the BB acts first.
        try hand.apply(.call, by: 0)
        XCTAssertEqual(hand.actionOn, 1)
        try hand.apply(.check, by: 1)
        XCTAssertEqual(hand.street, .flop)
        XCTAssertEqual(hand.actionOn, 1, "big blind acts first postflop heads-up")
    }

    func testBigBlindGetsOptionAfterCalls() throws {
        let hand = PokerHand(config: sixMaxConfig(button: 0))
        try hand.apply(.call, by: 3)
        try hand.apply(.call, by: 4)
        try hand.apply(.call, by: 5)
        try hand.apply(.call, by: 0)
        try hand.apply(.call, by: 1) // SB completes
        // BB must now have the option to check or raise.
        XCTAssertEqual(hand.actionOn, 2)
        let available = try XCTUnwrap(hand.availableActions(for: 2))
        XCTAssertTrue(available.canCheck)
        XCTAssertNotNil(available.betRaise)
        XCTAssertEqual(available.betRaise?.kind, .raise)
        try hand.apply(.check, by: 2)
        XCTAssertEqual(hand.street, .flop)
    }

    func testMinimumRaiseSizes() throws {
        let hand = PokerHand(config: sixMaxConfig(button: 0))
        // Facing the 2 blind: minimum raise is to 4.
        var available = try XCTUnwrap(hand.availableActions(for: 3))
        XCTAssertEqual(available.betRaise?.minFullTo, 4)
        // A raise to 3 must be rejected.
        XCTAssertThrowsError(try hand.apply(.raise(to: 3), by: 3))
        // Raise to 6 (increment 4): next minimum re-raise is to 10.
        try hand.apply(.raise(to: 6), by: 3)
        available = try XCTUnwrap(hand.availableActions(for: 4))
        XCTAssertEqual(available.betRaise?.minFullTo, 10)
        XCTAssertThrowsError(try hand.apply(.raise(to: 9), by: 4))
        try hand.apply(.raise(to: 10), by: 4)
        // Increment was 4 again: next minimum is 14.
        let next = try XCTUnwrap(hand.availableActions(for: 5))
        XCTAssertEqual(next.betRaise?.minFullTo, 14)
    }

    func testPostflopMinimumBetIsBigBlind() throws {
        let hand = PokerHand(config: sixMaxConfig(button: 0))
        // Everyone folds to the blinds; SB calls, BB checks.
        try hand.apply(.fold, by: 3)
        try hand.apply(.fold, by: 4)
        try hand.apply(.fold, by: 5)
        try hand.apply(.fold, by: 0)
        try hand.apply(.call, by: 1)
        try hand.apply(.check, by: 2)
        XCTAssertEqual(hand.street, .flop)
        XCTAssertEqual(hand.actionOn, 1, "first live seat left of button acts first postflop")
        let available = try XCTUnwrap(hand.availableActions(for: 1))
        XCTAssertEqual(available.betRaise?.kind, .bet)
        XCTAssertEqual(available.betRaise?.minFullTo, 2)
        XCTAssertThrowsError(try hand.apply(.bet(to: 1), by: 1))
        // Bet 10: minimum raise is to 20.
        try hand.apply(.bet(to: 10), by: 1)
        let facing = try XCTUnwrap(hand.availableActions(for: 2))
        XCTAssertEqual(facing.betRaise?.minFullTo, 20)
    }

    func testIllegalActionsAreRejected() throws {
        let hand = PokerHand(config: sixMaxConfig(button: 0))
        // Out of turn.
        XCTAssertThrowsError(try hand.apply(.fold, by: 4)) { error in
            XCTAssertEqual(error as? EngineError, EngineError.notPlayersTurn(seat: 4))
        }
        // Check while facing the big blind.
        XCTAssertThrowsError(try hand.apply(.check, by: 3)) { error in
            XCTAssertEqual(error as? EngineError, EngineError.checkNotAllowed)
        }
        // Using .bet while facing a bet.
        XCTAssertThrowsError(try hand.apply(.bet(to: 6), by: 3)) { error in
            XCTAssertEqual(error as? EngineError, EngineError.mustUseRaiseWhenFacingBet)
        }
        // Raising beyond the stack.
        XCTAssertThrowsError(try hand.apply(.raise(to: 500), by: 3))
        // Calling when there is nothing to call.
        try hand.apply(.call, by: 3)
        try hand.apply(.fold, by: 4)
        try hand.apply(.fold, by: 5)
        try hand.apply(.fold, by: 0)
        try hand.apply(.call, by: 1)
        try hand.apply(.check, by: 2)
        XCTAssertEqual(hand.street, .flop)
        XCTAssertThrowsError(try hand.apply(.call, by: 1)) { error in
            XCTAssertEqual(error as? EngineError, EngineError.nothingToCall)
        }
    }

    func testShortAllInRaiseDoesNotReopenAction() throws {
        // Seat 2 is short: after calling 2 preflop it has 48 behind.
        let hand = PokerHand(config: sixMaxConfig(button: 0, stacks: [200, 200, 50, 200, 200, 200]))
        try hand.apply(.fold, by: 3)
        try hand.apply(.fold, by: 4)
        try hand.apply(.fold, by: 5)
        try hand.apply(.call, by: 0)  // button calls 2
        try hand.apply(.call, by: 1)  // SB completes
        try hand.apply(.check, by: 2) // BB (short stack) checks
        XCTAssertEqual(hand.street, .flop)
        // Flop: SB bets 40, BB raises all-in to 48 (increment 8 < 40: short).
        try hand.apply(.bet(to: 40), by: 1)
        let shortStack = try XCTUnwrap(hand.availableActions(for: 2))
        XCTAssertEqual(shortStack.betRaise?.maxTo, 48)
        try hand.apply(.raise(to: 48), by: 2)
        // Button has NOT acted this street: it may re-raise, and a full raise
        // must be at least 48 + 40 = 88.
        let buttonActions = try XCTUnwrap(hand.availableActions(for: 0))
        XCTAssertNotNil(buttonActions.betRaise)
        XCTAssertEqual(buttonActions.betRaise?.minFullTo, 88)
        try hand.apply(.call, by: 0)
        // SB already acted and the raise was short: only call or fold.
        let sbActions = try XCTUnwrap(hand.availableActions(for: 1))
        XCTAssertNil(sbActions.betRaise, "short all-in must not reopen betting for a player who already acted")
        XCTAssertEqual(sbActions.callCost, 8)
        try hand.apply(.call, by: 1)
        XCTAssertEqual(hand.street, .turn)
    }

    func testFullRaiseAllInReopensAction() throws {
        let hand = PokerHand(config: sixMaxConfig(button: 0, stacks: [200, 200, 90, 200, 200, 200]))
        try hand.apply(.fold, by: 3)
        try hand.apply(.fold, by: 4)
        try hand.apply(.fold, by: 5)
        try hand.apply(.call, by: 0)
        try hand.apply(.call, by: 1)
        try hand.apply(.check, by: 2)
        // Flop: SB bets 40, BB raises all-in to 88 (increment 48 >= 40: full).
        try hand.apply(.bet(to: 40), by: 1)
        try hand.apply(.raise(to: 88), by: 2)
        try hand.apply(.call, by: 0)
        // SB may now re-raise because the all-in was a full raise.
        let sbActions = try XCTUnwrap(hand.availableActions(for: 1))
        XCTAssertNotNil(sbActions.betRaise)
        XCTAssertEqual(sbActions.betRaise?.minFullTo, 88 + 48)
    }

    func testFoldingEveryoneAwardsPotWithoutShowdown() throws {
        let hand = PokerHand(config: sixMaxConfig(button: 0))
        try hand.apply(.raise(to: 6), by: 3)
        try hand.apply(.fold, by: 4)
        try hand.apply(.fold, by: 5)
        try hand.apply(.fold, by: 0)
        try hand.apply(.fold, by: 1)
        try hand.apply(.fold, by: 2)
        XCTAssertTrue(hand.isComplete)
        // Raiser wins blinds (1 + 2); its own raise money comes back.
        XCTAssertEqual(hand.seats[3].stack, 203)
        XCTAssertEqual(hand.seats[1].stack, 199)
        XCTAssertEqual(hand.seats[2].stack, 198)
        let showdowns = hand.events.filter { event in
            if case .showedHand = event { return true }
            return false
        }
        XCTAssertTrue(showdowns.isEmpty, "no cards are revealed when everyone folds")
        // Chip conservation.
        XCTAssertEqual(hand.seats.reduce(0) { $0 + $1.stack }, 1200)
    }

    func testWalkForBigBlind() throws {
        let hand = PokerHand(config: sixMaxConfig(button: 0))
        try hand.apply(.fold, by: 3)
        try hand.apply(.fold, by: 4)
        try hand.apply(.fold, by: 5)
        try hand.apply(.fold, by: 0)
        try hand.apply(.fold, by: 1)
        XCTAssertTrue(hand.isComplete)
        XCTAssertEqual(hand.seats[2].stack, 201, "BB wins the small blind")
        XCTAssertEqual(hand.seats[1].stack, 199)
    }

    func testBigBlindAllInForLessThanFullBlind() throws {
        // BB has only 1 chip; the amount to call remains the full big blind.
        let hand = PokerHand(config: sixMaxConfig(button: 0, stacks: [200, 200, 1, 200, 200, 200]))
        XCTAssertEqual(hand.currentBet, 2)
        let utg = try XCTUnwrap(hand.availableActions(for: 3))
        XCTAssertEqual(utg.callCost, 2)
        try hand.apply(.call, by: 3)
        try hand.apply(.fold, by: 4)
        try hand.apply(.fold, by: 5)
        try hand.apply(.fold, by: 0)
        try hand.apply(.fold, by: 1)
        // BB is all-in: no action possible, board runs out to showdown.
        XCTAssertTrue(hand.isComplete)
        XCTAssertTrue(hand.board.count == 5)
        // UTG's uncalled extra chip above the BB's 1 goes back to UTG:
        // main pot = 1 (BB) + 1 (UTG match) + 1 (dead SB) = 3, refund 1.
        let refunds = hand.events.contains { event in
            if case .refundedUncalledBet(let seat, let amount) = event {
                return seat == 3 && amount == 1
            }
            return false
        }
        XCTAssertTrue(refunds)
        XCTAssertEqual(hand.finalPots.count, 1)
        XCTAssertEqual(hand.finalPots[0].amount, 3)
        XCTAssertEqual(hand.seats.reduce(0) { $0 + $1.stack }, 1001)
    }

    func testFoldWhenCheckingIsFreeIsLegal() throws {
        let hand = PokerHand(config: sixMaxConfig(button: 0))
        try hand.apply(.call, by: 3)
        try hand.apply(.fold, by: 4)
        try hand.apply(.fold, by: 5)
        try hand.apply(.fold, by: 0)
        try hand.apply(.call, by: 1)
        try hand.apply(.check, by: 2)
        // Open-folding on the flop is legal (if unwise).
        XCTAssertEqual(hand.actionOn, 1)
        try hand.apply(.fold, by: 1)
        XCTAssertFalse(hand.isComplete)
        XCTAssertEqual(hand.liveSeatIndices, [2, 3])
    }
}
