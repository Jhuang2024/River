import XCTest
@testable import RiverKit

final class BoardTextureTests: XCTestCase {

    func testDryRainbowFlop() {
        let c = BoardTexture.classify([c2(.king, .spades), c2(.eight, .diamonds), c2(.two, .clubs)])
        XCTAssertFalse(c.paired)
        XCTAssertFalse(c.monotone)
        XCTAssertFalse(c.twoTone)
        XCTAssertFalse(c.connected)
        XCTAssertTrue(c.dry)
    }

    func testPairedBoard() {
        let c = BoardTexture.classify([c2(.nine, .spades), c2(.nine, .diamonds), c2(.two, .clubs)])
        XCTAssertTrue(c.paired)
    }

    func testMonotoneFlop() {
        let c = BoardTexture.classify([c2(.king, .hearts), c2(.eight, .hearts), c2(.two, .hearts)])
        XCTAssertTrue(c.monotone)
        XCTAssertFalse(c.twoTone)
    }

    func testTwoToneFlop() {
        let c = BoardTexture.classify([c2(.king, .hearts), c2(.eight, .hearts), c2(.two, .spades)])
        XCTAssertTrue(c.twoTone)
        XCTAssertFalse(c.monotone)
    }

    func testConnectedFlop() {
        let c = BoardTexture.classify([c2(.nine, .spades), c2(.eight, .diamonds), c2(.six, .clubs)])
        XCTAssertTrue(c.connected)
    }

    func testAceLowConnection() {
        let c = BoardTexture.classify([c2(.ace, .spades), c2(.three, .diamonds), c2(.four, .clubs)])
        XCTAssertTrue(c.connected, "wheel coordination counts as connected")
    }

    func testShortBoardHasNoLabels() {
        XCTAssertTrue(BoardTexture.labels(for: []).isEmpty)
        XCTAssertTrue(BoardTexture.labels(for: [c2(.ace, .spades)]).isEmpty)
    }

    func testLabelsCombine() {
        let labels = BoardTexture.labels(for: [c2(.nine, .hearts), c2(.eight, .hearts), c2(.seven, .spades)])
        XCTAssertTrue(labels.contains("Two-tone"))
        XCTAssertTrue(labels.contains("Connected"))
        XCTAssertFalse(labels.contains("Dry"))
    }

    private func c2(_ rank: Rank, _ suit: Suit) -> Card {
        return Card(rank, suit)
    }
}
