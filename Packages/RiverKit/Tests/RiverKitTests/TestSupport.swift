import XCTest
@testable import RiverKit

/// Shorthand card constructor for tests: c(.ace, .spades).
func c(_ rank: Rank, _ suit: Suit) -> Card {
    return Card(rank, suit)
}

/// Builds a full 52-card rigged deck that deals the given hole cards and board
/// exactly, mirroring the engine's deal order (one card at a time starting left
/// of the button, two rounds, then burn-flop-burn-turn-burn-river).
func riggedDeck(holes: [Int: [Card]], board: [Card], stacks: [Int], button: Int) -> [Card] {
    precondition(board.count == 5, "rigged board must contain 5 cards")
    let n = stacks.count
    var order: [Int] = []
    var i = button
    for _ in 0..<n {
        i = (i + 1) % n
        if stacks[i] > 0 {
            order.append(i)
        }
    }
    var deck: [Card] = []
    for round in 0..<2 {
        for seat in order {
            guard let cards = holes[seat], cards.count == 2 else {
                preconditionFailure("missing rigged hole cards for seat \(seat)")
            }
            deck.append(cards[round])
        }
    }
    let used = Set(deck + board)
    var rest = Deck.standard().filter { !used.contains($0) }
    deck.append(rest.removeFirst()) // burn
    deck.append(board[0])
    deck.append(board[1])
    deck.append(board[2])
    deck.append(rest.removeFirst()) // burn
    deck.append(board[3])
    deck.append(rest.removeFirst()) // burn
    deck.append(board[4])
    deck.append(contentsOf: rest)
    return deck
}

/// Picks a uniformly random legal action, including odd but legal raise sizes.
/// Used by chip-conservation chaos tests.
func randomLegalAction(_ available: AvailableActions, rng: inout SeededRNG) -> PlayerAction {
    var choices: [PlayerAction] = [.fold]
    if available.canCheck {
        choices.append(.check)
    }
    if available.canCall {
        choices.append(.call)
    }
    if let options = available.betRaise {
        choices.append(PlayerAction(kind: options.kind, toAmount: options.minTo))
        choices.append(PlayerAction(kind: options.kind, toAmount: options.maxTo))
        if options.maxTo > options.minFullTo {
            let amount = rng.int(in: options.minFullTo...options.maxTo)
            choices.append(PlayerAction(kind: options.kind, toAmount: amount))
        }
    }
    return choices[rng.int(upperBound: choices.count)]
}

/// Plays a hand to completion using the chaos agent; returns actions taken.
@discardableResult
func playRandomHand(_ hand: PokerHand, rng: inout SeededRNG, maxActions: Int = 500) -> [(seat: Int, action: PlayerAction)] {
    var taken: [(seat: Int, action: PlayerAction)] = []
    var guardCount = 0
    while !hand.isComplete {
        guard let seat = hand.actionOn, let available = hand.availableActions(for: seat) else {
            XCTFail("hand not complete but nobody to act")
            break
        }
        let action = randomLegalAction(available, rng: &rng)
        do {
            try hand.apply(action, by: seat)
        } catch {
            XCTFail("legal action rejected: \(action) for seat \(seat): \(error)")
            break
        }
        taken.append((seat, action))
        guardCount += 1
        if guardCount > maxActions {
            XCTFail("hand exceeded \(maxActions) actions — possible deadlock")
            break
        }
    }
    return taken
}
