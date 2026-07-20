import XCTest
@testable import RiverKit

/// Full-hand scenarios with rigged decks so exact showdown outcomes are known.
final class EngineFlowTests: XCTestCase {

    func testMultiWayAllInProducesCorrectSidePots() throws {
        // Seats: 0 = A (100), 1 = B (60, SB), 2 = C (30, BB), 3 = D (100).
        // D folds; A shoves 100; B calls all-in 60; C calls all-in 30.
        // C holds aces (wins main), B kings (wins side 1), A queens.
        let stacks = [100, 60, 30, 100]
        let board = [c(.two, .spades), c(.seven, .diamonds), c(.eight, .clubs), c(.three, .hearts), c(.four, .spades)]
        let deck = riggedDeck(
            holes: [
                0: [c(.queen, .clubs), c(.queen, .diamonds)],
                1: [c(.king, .clubs), c(.king, .diamonds)],
                2: [c(.ace, .clubs), c(.ace, .diamonds)],
                3: [c(.nine, .clubs), c(.six, .diamonds)]
            ],
            board: board,
            stacks: stacks,
            button: 0
        )
        let hand = PokerHand(config: HandConfig(stacks: stacks, buttonIndex: 0, smallBlind: 1, bigBlind: 2, seed: 0), riggedDeck: deck)
        XCTAssertEqual(hand.actionOn, 3)
        try hand.apply(.fold, by: 3)
        try hand.apply(.raise(to: 100), by: 0)
        try hand.apply(.call, by: 1) // all-in for 60 total
        try hand.apply(.call, by: 2) // all-in for 30 total
        XCTAssertTrue(hand.isComplete)
        XCTAssertEqual(hand.board, board)

        // Pots: main 90 (30 × 3), side 60 (30 more from A and B). A refunds 40.
        XCTAssertEqual(hand.finalPots.count, 2)
        XCTAssertEqual(hand.finalPots[0].amount, 90)
        XCTAssertEqual(hand.finalPots[0].eligibleSeats, [0, 1, 2])
        XCTAssertEqual(hand.finalPots[1].amount, 60)
        XCTAssertEqual(hand.finalPots[1].eligibleSeats, [0, 1])

        XCTAssertEqual(hand.seats[0].stack, 40, "A gets only the 40 refund")
        XCTAssertEqual(hand.seats[1].stack, 60, "B wins the 60 side pot")
        XCTAssertEqual(hand.seats[2].stack, 90, "C wins the 90 main pot")
        XCTAssertEqual(hand.seats[3].stack, 100)
        XCTAssertEqual(hand.seats.reduce(0) { $0 + $1.stack }, 290)
    }

    func testFoldedPlayerCanNeverWin() throws {
        // Seat 3 folds the best hand preflop; board pairs it anyway.
        let stacks = [100, 100, 100, 100]
        let board = [c(.ace, .spades), c(.ace, .diamonds), c(.seven, .clubs), c(.two, .hearts), c(.three, .spades)]
        let deck = riggedDeck(
            holes: [
                0: [c(.king, .clubs), c(.king, .diamonds)],
                1: [c(.queen, .clubs), c(.queen, .diamonds)],
                2: [c(.jack, .clubs), c(.jack, .diamonds)],
                3: [c(.ace, .clubs), c(.ace, .hearts)]
            ],
            board: board,
            stacks: stacks,
            button: 0
        )
        let hand = PokerHand(config: HandConfig(stacks: stacks, buttonIndex: 0, smallBlind: 1, bigBlind: 2, seed: 0), riggedDeck: deck)
        try hand.apply(.fold, by: 3)
        try hand.apply(.call, by: 0)
        try hand.apply(.call, by: 1)
        try hand.apply(.check, by: 2)
        while !hand.isComplete {
            guard let seat = hand.actionOn else { break }
            try hand.apply(.check, by: seat)
        }
        XCTAssertTrue(hand.isComplete)
        XCTAssertEqual(hand.seats[3].stack, 100, "folded seat neither wins nor loses beyond blinds")
        // KK wins with kings and aces.
        XCTAssertEqual(hand.seats[0].stack, 104)
        for event in hand.events {
            if case .wonPot(let seat, _, _, _) = event {
                XCTAssertNotEqual(seat, 3)
            }
        }
    }

    func testSplitPotWithOddChipGoesLeftOfButton() throws {
        // Seats 1 and 2 tie with the same two-pair hand; seat 0 loses.
        // Pot is 15 (5 each): winners split 7/7 with the odd chip to the first
        // winner left of the button (seat 1).
        let stacks = [100, 100, 100]
        let board = [c(.ace, .spades), c(.ace, .hearts), c(.king, .diamonds), c(.king, .clubs), c(.two, .spades)]
        let deck = riggedDeck(
            holes: [
                0: [c(.three, .diamonds), c(.four, .diamonds)],
                1: [c(.queen, .diamonds), c(.jack, .diamonds)],
                2: [c(.queen, .clubs), c(.jack, .clubs)]
            ],
            board: board,
            stacks: stacks,
            button: 0
        )
        let hand = PokerHand(config: HandConfig(stacks: stacks, buttonIndex: 0, smallBlind: 1, bigBlind: 2, seed: 0), riggedDeck: deck)
        try hand.apply(.raise(to: 5), by: 0)
        try hand.apply(.call, by: 1)
        try hand.apply(.call, by: 2)
        while !hand.isComplete {
            guard let seat = hand.actionOn else { break }
            try hand.apply(.check, by: seat)
        }
        XCTAssertEqual(hand.seats[1].stack, 103, "seat 1 gets 8 of the 15 pot (odd chip)")
        XCTAssertEqual(hand.seats[2].stack, 102, "seat 2 gets 7")
        XCTAssertEqual(hand.seats[0].stack, 95)
        XCTAssertEqual(hand.seats.reduce(0) { $0 + $1.stack }, 300)
    }

    func testBoardRunsOutWhenEveryoneIsAllInPreflop() throws {
        let stacks = [50, 50]
        let board = [c(.two, .spades), c(.seven, .diamonds), c(.eight, .clubs), c(.three, .hearts), c(.four, .spades)]
        let deck = riggedDeck(
            holes: [
                0: [c(.ace, .clubs), c(.ace, .diamonds)],
                1: [c(.king, .clubs), c(.king, .diamonds)]
            ],
            board: board,
            stacks: stacks,
            button: 0
        )
        let hand = PokerHand(config: HandConfig(stacks: stacks, buttonIndex: 0, smallBlind: 1, bigBlind: 2, seed: 0), riggedDeck: deck)
        try hand.apply(.raise(to: 50), by: 0)
        try hand.apply(.call, by: 1)
        XCTAssertTrue(hand.isComplete)
        XCTAssertEqual(hand.board.count, 5)
        XCTAssertEqual(hand.seats[0].stack, 100, "aces hold on a dry board")
        XCTAssertEqual(hand.seats[1].stack, 0)
    }

    func testNoDuplicateCardsInPlay() throws {
        for seed in 1...30 {
            let hand = PokerHand(config: HandConfig(stacks: Array(repeating: 200, count: 6), buttonIndex: seed % 6, smallBlind: 1, bigBlind: 2, seed: UInt64(seed)))
            var seen = Set<Card>()
            while !hand.isComplete {
                guard let seat = hand.actionOn, let available = hand.availableActions(for: seat) else { break }
                if available.canCheck {
                    try hand.apply(.check, by: seat)
                } else {
                    try hand.apply(.call, by: seat)
                }
            }
            for seat in hand.seats where seat.isParticipating {
                for card in seat.holeCards {
                    XCTAssertTrue(seen.insert(card).inserted, "duplicate card \(card)")
                }
            }
            for card in hand.board {
                XCTAssertTrue(seen.insert(card).inserted, "duplicate board card \(card)")
            }
            XCTAssertEqual(seen.count, 12 + 5)
        }
    }

    func testSameSeedSameDeal() {
        let config = HandConfig(stacks: Array(repeating: 200, count: 6), buttonIndex: 2, smallBlind: 1, bigBlind: 2, seed: 777)
        let a = PokerHand(config: config)
        let b = PokerHand(config: config)
        XCTAssertEqual(a.events, b.events)
        for i in 0..<6 {
            XCTAssertEqual(a.seats[i].holeCards, b.seats[i].holeCards)
        }
    }

    func testAntesAreCollectedAndConserved() throws {
        let config = HandConfig(stacks: Array(repeating: 100, count: 4), buttonIndex: 0, smallBlind: 1, bigBlind: 2, ante: 1, seed: 42)
        let hand = PokerHand(config: config)
        XCTAssertEqual(hand.pot, 3 + 4, "blinds plus four antes")
        // Antes are dead: UTG still owes exactly the big blind to call.
        let utg = try XCTUnwrap(hand.availableActions(for: 3))
        XCTAssertEqual(utg.callCost, 2)
        var rng = SeededRNG(seed: 9)
        playRandomHand(hand, rng: &rng)
        XCTAssertEqual(hand.seats.reduce(0) { $0 + $1.stack }, 400)
    }
}
