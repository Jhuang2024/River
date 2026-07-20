import XCTest
@testable import RiverKit

/// Combination-level range model tests (§45).
final class RangeModelTests: XCTestCase {

    func testAllCombinationsCount() {
        XCTAssertEqual(HoleCombo.all.count, 1326)
        XCTAssertEqual(Set(HoleCombo.all).count, 1326)
    }

    func testCanonicalComboCounts() {
        XCTAssertEqual(HoleCombo.combos(forLabel: "AA").count, 6)
        XCTAssertEqual(HoleCombo.combos(forLabel: "AKs").count, 4)
        XCTAssertEqual(HoleCombo.combos(forLabel: "AKo").count, 12)
        XCTAssertEqual(HoleCombo.combos(forLabel: "T9s").count, 4)
        XCTAssertEqual(HoleCombo.combos(forLabel: "22").count, 6)
        XCTAssertTrue(HoleCombo.combos(forLabel: "XX").isEmpty)
        XCTAssertTrue(HoleCombo.combos(forLabel: "AAs").isEmpty)
    }

    func testLabelRoundTrip() {
        XCTAssertEqual(HoleCombo(c(.ace, .spades), c(.king, .spades)).label, "AKs")
        XCTAssertEqual(HoleCombo(c(.king, .hearts), c(.ace, .spades)).label, "AKo")
        XCTAssertEqual(HoleCombo(c(.ten, .hearts), c(.ten, .spades)).label, "TT")
        // Every label in the ordering parses to a nonempty combo set, and the
        // full ordering covers all 1326 combinations exactly once.
        var total = 0
        var seen = Set<HoleCombo>()
        for label in HandOrdering.byEquityVsRandom {
            let combos = HoleCombo.combos(forLabel: label)
            XCTAssertFalse(combos.isEmpty, "label \(label) failed to parse")
            total += combos.count
            for combo in combos {
                XCTAssertTrue(seen.insert(combo).inserted, "duplicate combo in \(label)")
            }
        }
        XCTAssertEqual(total, 1326)
        XCTAssertEqual(HandOrdering.byEquityVsRandom.count, 169)
    }

    func testDeadCardRemoval() {
        var range = HandRange.uniform()
        XCTAssertEqual(range.weights.count, 1326)
        let dead: Set<Card> = [c(.ace, .spades), c(.king, .diamonds)]
        range.removeCombos(containing: dead)
        // Each dead card kills 51 combos, minus the 1 shared combo.
        XCTAssertEqual(range.weights.count, 1326 - 51 - 51 + 1)
        for combo in range.weights.keys {
            XCTAssertFalse(combo.contains(any: dead))
        }
    }

    func testTopPercentRangeSizes() {
        let top10 = HandOrdering.topPercentRange(0.10)
        XCTAssertEqual(top10.comboCount, 132.6, accuracy: 1.5)
        let top50 = HandOrdering.topPercentRange(0.50)
        XCTAssertEqual(top50.comboCount, 663, accuracy: 2)
        // Strongest hands always included.
        for combo in HoleCombo.combos(forLabel: "AA") {
            XCTAssertEqual(top10.weight(of: combo), 1)
        }
        XCTAssertTrue(HandOrdering.topPercentRange(0).isEmpty)
    }

    func testPercentileOrdering() {
        XCTAssertLessThan(HandOrdering.percentile(of: "AA"), HandOrdering.percentile(of: "AKs"))
        XCTAssertLessThan(HandOrdering.percentile(of: "AKs"), HandOrdering.percentile(of: "72o"))
        XCTAssertLessThan(HandOrdering.percentile(of: "AA"), 0.01)
        XCTAssertGreaterThan(HandOrdering.percentile(of: "32o"), 0.95)
    }

    func testNormalizationAndFloor() {
        var range = HandRange.fromLabels(["AA": 0.5, "KK": 0.25])
        range.normalize()
        for combo in HoleCombo.combos(forLabel: "AA") {
            XCTAssertEqual(range.weight(of: combo), 1.0, accuracy: 1e-9)
        }
        for combo in HoleCombo.combos(forLabel: "KK") {
            XCTAssertEqual(range.weight(of: combo), 0.5, accuracy: 1e-9)
        }
        var floored = HandRange.fromLabels(["AA": 1.0, "72o": 0.0001])
        floored.applyFloor(0.05)
        for combo in HoleCombo.combos(forLabel: "72o") {
            XCTAssertGreaterThanOrEqual(floored.weight(of: combo), 0.05 - 1e-9)
        }
    }

    func testSamplingIsDeterministicAndRespectsDeadCards() {
        let range = HandRange.fromLabels(["AA": 1.0, "KK": 1.0])
        let dead: Set<Card> = [c(.ace, .spades)]
        var rngA = SeededRNG(seed: 5)
        var rngB = SeededRNG(seed: 5)
        for _ in 0..<50 {
            let a = range.sample(excluding: dead, rng: &rngA)
            let b = range.sample(excluding: dead, rng: &rngB)
            XCTAssertEqual(a, b)
            XCTAssertNotNil(a)
            XCTAssertFalse(a!.contains(c(.ace, .spades)))
        }
        // Fully blocked range samples nothing.
        let tiny = HandRange.fromLabels(["AA": 1.0])
        let allAces: Set<Card> = [c(.ace, .spades), c(.ace, .hearts), c(.ace, .diamonds), c(.ace, .clubs)]
        var rng = SeededRNG(seed: 9)
        XCTAssertNil(tiny.sample(excluding: allAces, rng: &rng))
    }

    func testMergeKeepsMaximumWeight() {
        let a = HandRange.fromLabels(["AA": 0.5])
        let b = HandRange.fromLabels(["AA": 0.9, "KK": 0.3])
        let merged = a.merged(with: b)
        for combo in HoleCombo.combos(forLabel: "AA") {
            XCTAssertEqual(merged.weight(of: combo), 0.9, accuracy: 1e-9)
        }
        XCTAssertEqual(merged.comboCount, 0.9 * 6 + 0.3 * 6, accuracy: 1e-6)
    }

    func testStrategyConfigValidates() {
        XCTAssertTrue(StrategyConfig.baseline.validate().isEmpty, "baseline must be valid: \(StrategyConfig.baseline.validate())")
        // Every archetype/difficulty combination stays valid after modifiers.
        for archetype in BotArchetype.allCases {
            for difficulty in BotDifficulty.allCases {
                let profile = profileFor(archetype: archetype, difficulty: difficulty)
                let applied = StrategyConfig.baseline.applying(profile: profile)
                XCTAssertTrue(applied.validate().isEmpty, "\(archetype)/\(difficulty) produced invalid config: \(applied.validate())")
            }
        }
        // Corrupt configs are caught.
        var broken = StrategyConfig.baseline
        broken.bbDefendCallPercent = 1.4
        XCTAssertFalse(broken.validate().isEmpty)
    }

    func testRangeTrackerNarrowsAndRemovesKnownCards() throws {
        // UTG opens, hero (seat 0, button) observes: UTG's range must shrink
        // far below uniform and exclude hero's own cards.
        let stacks = Array(repeating: 200, count: 6)
        let board = [c(.two, .clubs), c(.seven, .diamonds), c(.jack, .hearts), c(.four, .spades), c(.nine, .clubs)]
        let holes: [Int: [Card]] = [
            0: [c(.ace, .spades), c(.king, .spades)],
            1: [c(.two, .hearts), c(.three, .hearts)],
            2: [c(.five, .diamonds), c(.six, .clubs)],
            3: [c(.queen, .clubs), c(.queen, .diamonds)],
            4: [c(.eight, .spades), c(.nine, .spades)],
            5: [c(.ten, .clubs), c(.jack, .clubs)]
        ]
        let hand = PokerHand(
            config: HandConfig(stacks: stacks, buttonIndex: 0, smallBlind: 1, bigBlind: 2, seed: 3),
            riggedDeck: riggedDeck(holes: holes, board: board, stacks: stacks, button: 0)
        )
        try hand.apply(.raise(to: 5), by: 3)
        try hand.apply(.fold, by: 4)
        try hand.apply(.fold, by: 5)

        let obs = try XCTUnwrap(hand.observation(for: 0))
        let tracker = RangeTracker.build(events: obs.visibleEvents, viewpointSeat: 0, viewpointCards: obs.holeCards)
        let utgRange = try XCTUnwrap(tracker.ranges[3])
        // Weighted combos far below uniform after an UTG open.
        XCTAssertLessThan(utgRange.comboCount, 700)
        XCTAssertFalse(utgRange.isEmpty)
        // Hero's own cards are dead in every tracked range.
        for combo in utgRange.weights.keys {
            XCTAssertFalse(combo.contains(c(.ace, .spades)))
            XCTAssertFalse(combo.contains(c(.king, .spades)))
        }
        // Premium hands remain at full relative weight; trash is floored low.
        let aa = HoleCombo(c(.ace, .hearts), c(.ace, .diamonds))
        let trash = HoleCombo(c(.seven, .hearts), c(.two, .spades))
        XCTAssertGreaterThan(utgRange.weight(of: aa), utgRange.weight(of: trash))
        XCTAssertGreaterThan(utgRange.weight(of: trash), 0, "floors keep unexpected hands possible")
        // Folded seats are not tracked.
        XCTAssertNil(tracker.ranges[4])
        XCTAssertNil(tracker.ranges[5])
    }

    func testRangeTrackerCollapsesOnShowdownReveal() throws {
        var rng = SeededRNG(seed: 15)
        let config = HandConfig(stacks: [100, 100], buttonIndex: 0, smallBlind: 1, bigBlind: 2, seed: 88)
        let hand = PokerHand(config: config)
        while !hand.isComplete {
            guard let seat = hand.actionOn, let available = hand.availableActions(for: seat) else { break }
            if available.canCheck {
                try hand.apply(.check, by: seat)
            } else {
                try hand.apply(.call, by: seat)
            }
        }
        _ = rng
        guard hand.events.contains(where: { if case .showedHand = $0 { return true }; return false }) else {
            return XCTFail("expected a showdown")
        }
        let tracker = RangeTracker.build(events: hand.events, viewpointSeat: 0, viewpointCards: hand.seats[0].holeCards)
        if let revealed = tracker.ranges[1] {
            XCTAssertEqual(revealed.weights.count, 1, "revealed hand collapses the range to the exact combo")
            XCTAssertEqual(revealed.weights.keys.first?.cards.sorted(), hand.seats[1].holeCards.sorted())
        } else {
            XCTFail("opponent range missing")
        }
    }

    private func profileFor(archetype: BotArchetype, difficulty: BotDifficulty) -> BotProfile {
        switch archetype {
        case .nit: return .nit(name: "n", symbolName: "person", difficulty: difficulty)
        case .callingStation: return .callingStation(name: "c", symbolName: "person", difficulty: difficulty)
        case .looseAggressive: return .looseAggressive(name: "l", symbolName: "person", difficulty: difficulty)
        case .maniac: return .maniac(name: "m", symbolName: "person", difficulty: difficulty)
        case .solidRegular: return .solidRegular(name: "s", symbolName: "person", difficulty: difficulty)
        case .trapper: return .trapper(name: "t", symbolName: "person", difficulty: difficulty)
        }
    }
}
