import XCTest
@testable import RiverKit

final class DeckTests: XCTestCase {

    func testStandardDeckHas52UniqueCards() {
        let cards = Deck.standard()
        XCTAssertEqual(cards.count, 52)
        XCTAssertEqual(Set(cards).count, 52)
    }

    func testSeededShuffleIsDeterministic() {
        let a = Deck(seed: 12345)
        let b = Deck(seed: 12345)
        XCTAssertEqual(a.cards, b.cards)
        XCTAssertEqual(Set(a.cards).count, 52)
    }

    func testDifferentSeedsProduceDifferentOrders() {
        let a = Deck(seed: 1)
        let b = Deck(seed: 2)
        XCTAssertNotEqual(a.cards, b.cards)
    }

    func testRNGDeterminismAndRange() {
        var a = SeededRNG(seed: 99)
        var b = SeededRNG(seed: 99)
        for _ in 0..<1000 {
            XCTAssertEqual(a.nextUInt64(), b.nextUInt64())
        }
        var rng = SeededRNG(seed: 7)
        for _ in 0..<1000 {
            let value = rng.int(upperBound: 13)
            XCTAssertTrue(value >= 0 && value < 13)
            let ranged = rng.int(in: 5...9)
            XCTAssertTrue(ranged >= 5 && ranged <= 9)
            let d = rng.double01()
            XCTAssertTrue(d >= 0 && d < 1)
        }
    }

    func testDerivedStreamsDiffer() {
        var a = SeededRNG.derive(seed: 42, stream: 1)
        var b = SeededRNG.derive(seed: 42, stream: 2)
        XCTAssertNotEqual(a.nextUInt64(), b.nextUInt64())
    }

    func testDealAndBurnConsumeCards() {
        var deck = Deck(seed: 5)
        let first = deck.cards[0]
        XCTAssertEqual(deck.deal(), first)
        XCTAssertEqual(deck.count, 51)
        deck.burn()
        XCTAssertEqual(deck.count, 50)
    }
}
