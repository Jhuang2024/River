import XCTest
@testable import RiverKit

/// Property-style randomized tests: hundreds of hands with a chaos agent that
/// picks uniformly among legal actions (including odd raise sizes and folds in
/// weird spots). After every hand, chips must be exactly conserved, the hand
/// must complete without deadlock, and replaying the same seed + actions must
/// reproduce identical events.
final class ChipConservationTests: XCTestCase {

    func testChipsAreConservedAcrossRandomHands() throws {
        var rng = SeededRNG(seed: 0xC0FFEE)
        for trial in 0..<300 {
            let seatCount = rng.int(in: 2...6)
            var stacks: [Int] = []
            for _ in 0..<seatCount {
                stacks.append(rng.int(in: 2...400))
            }
            let button = rng.int(upperBound: seatCount)
            let config = HandConfig(
                stacks: stacks,
                buttonIndex: button,
                smallBlind: 1,
                bigBlind: 2,
                ante: trial % 5 == 0 ? 1 : 0,
                seed: rng.nextUInt64(),
                handNumber: trial
            )
            let hand = PokerHand(config: config)
            let actions = playRandomHand(hand, rng: &rng)
            XCTAssertTrue(hand.isComplete, "hand \(trial) did not complete")

            let totalBefore = stacks.reduce(0, +)
            let totalAfter = hand.seats.reduce(0) { $0 + $1.stack }
            XCTAssertEqual(totalAfter, totalBefore, "chips not conserved in trial \(trial)")

            // Committed chips are fully paid out: pots + refunds == sum committed.
            var awarded = 0
            var refunded = 0
            var committed = 0
            for event in hand.events {
                switch event {
                case .wonPot(_, let amount, _, _): awarded += amount
                case .wonWithoutShowdown(_, let amount): awarded += amount
                case .refundedUncalledBet(_, let amount): refunded += amount
                case .postedAnte(_, let amount): committed += amount
                case .postedSmallBlind(_, let amount): committed += amount
                case .postedBigBlind(_, let amount): committed += amount
                case .action(_, _, _, let added, _, _): committed += added
                default: break
                }
            }
            XCTAssertEqual(awarded + refunded, committed, "pot accounting broken in trial \(trial)")

            // Determinism: replaying the exact action sequence reproduces the hand.
            let replay = PokerHand(config: config)
            for (seat, action) in actions {
                try replay.apply(action, by: seat)
            }
            XCTAssertEqual(replay.events, hand.events, "replay diverged in trial \(trial)")

            // The replayer reconstruction must agree with the engine's stacks.
            let history = HandHistory(date: Date(timeIntervalSince1970: 0), heroSeat: 0, playerNames: (0..<seatCount).map { "P\($0)" }, hand: hand)
            let replayer = HandReplayer(history: history)
            let final = replayer.snapshot(afterStep: replayer.stepCount - 1, revealAll: true)
            for i in 0..<seatCount {
                XCTAssertEqual(final.seats[i].stack, hand.seats[i].stack, "replayer stack mismatch seat \(i) trial \(trial)")
            }
            XCTAssertEqual(final.pot, 0, "pot must fully drain after distribution")
        }
    }

    func testNoNegativeStacksOrCommitments() {
        var rng = SeededRNG(seed: 424242)
        for trial in 0..<100 {
            let config = HandConfig(
                stacks: [3, 150, 47, 200, 8, 391],
                buttonIndex: trial % 6,
                smallBlind: 1,
                bigBlind: 2,
                seed: rng.nextUInt64(),
                handNumber: trial
            )
            let hand = PokerHand(config: config)
            while !hand.isComplete {
                guard let seat = hand.actionOn, let available = hand.availableActions(for: seat) else {
                    XCTFail("stalled")
                    return
                }
                let action = randomLegalAction(available, rng: &rng)
                do {
                    try hand.apply(action, by: seat)
                } catch {
                    XCTFail("rejected legal action: \(error)")
                    return
                }
                for seat in hand.seats {
                    XCTAssertGreaterThanOrEqual(seat.stack, 0)
                    XCTAssertGreaterThanOrEqual(seat.committedThisStreet, 0)
                    XCTAssertGreaterThanOrEqual(seat.committedTotal, 0)
                }
            }
        }
    }
}
