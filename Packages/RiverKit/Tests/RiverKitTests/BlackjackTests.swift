import XCTest
@testable import RiverKit

/// Blackjack rules engine (§6, §13): shoe, totals, every action path,
/// settlement exactness and determinism.
final class BlackjackTests: XCTestCase {

    private func bjCard(_ rank: Rank, _ suit: Suit = .spades) -> BlackjackCard {
        return BlackjackCard(rank, suit)
    }

    /// Deal order is player, dealer-up, player, dealer-hole.
    private func round(playerCards: [Rank], dealerCards: [Rank], next: [Rank] = [],
                       rules: BlackjackRules = .standard, bet: Int = 10) throws -> BlackjackRound {
        // Vary suits so identical ranks stay distinct cards in the shoe.
        let suits: [Suit] = [.spades, .hearts, .diamonds, .clubs]
        var used: [Rank: Int] = [:]
        func make(_ rank: Rank) -> BlackjackCard {
            let count = used[rank, default: 0]
            used[rank] = count + 1
            return BlackjackCard(rank, suits[count % 4])
        }
        let order = [make(playerCards[0]), make(dealerCards[0]), make(playerCards[1]), make(dealerCards[1])]
            + next.map { make($0) }
        let shoe = BlackjackShoe(riggedPrefix: order, decks: rules.decks, penetration: rules.penetration)
        var round = BlackjackRound(rules: rules, shoe: shoe)
        try round.deal(bet: bet)
        return round
    }

    // MARK: - Shoe

    func testShoeContainsExactlyTheRightCards() {
        let shoe = BlackjackShoe(decks: 6, penetration: 0.75, seed: 42)
        XCTAssertEqual(shoe.cards.count, 6 * 52)
        var counts: [BlackjackCard: Int] = [:]
        for card in shoe.cards { counts[card, default: 0] += 1 }
        XCTAssertTrue(counts.values.allSatisfy { $0 == 6 }, "every card appears once per deck")
    }

    func testShoeIsDeterministicPerSeedAndReshufflesAtPenetration() {
        var first = BlackjackShoe(decks: 6, penetration: 0.5, seed: 9)
        let second = BlackjackShoe(decks: 6, penetration: 0.5, seed: 9)
        XCTAssertEqual(first.cards, second.cards, "same seed, same shoe")
        XCTAssertNotEqual(first.cards, BlackjackShoe(decks: 6, penetration: 0.5, seed: 10).cards)

        XCTAssertFalse(first.needsReshuffle)
        for _ in 0..<(first.cards.count / 2) { _ = first.deal() }
        XCTAssertTrue(first.needsReshuffle, "cut card at 50% penetration")
    }

    // MARK: - Totals

    func testHandTotalsHardSoftAndBust() {
        XCTAssertEqual(BlackjackTotal.evaluate([bjCard(.ace), bjCard(.six, .hearts)]).total, 17)
        XCTAssertTrue(BlackjackTotal.evaluate([bjCard(.ace), bjCard(.six, .hearts)]).isSoft)
        // Two aces: one promotes to 11.
        XCTAssertEqual(BlackjackTotal.evaluate([bjCard(.ace), bjCard(.ace, .hearts)]).total, 12)
        // Ace demotes to 1 when 11 would bust.
        let demoted = BlackjackTotal.evaluate([bjCard(.ace), bjCard(.nine, .hearts), bjCard(.five, .clubs)])
        XCTAssertEqual(demoted.total, 15)
        XCTAssertFalse(demoted.isSoft)
        XCTAssertTrue(BlackjackTotal.isBust([bjCard(.king), bjCard(.queen, .hearts), bjCard(.two, .clubs)]))
        XCTAssertTrue(BlackjackTotal.isBlackjack([bjCard(.ace), bjCard(.king, .hearts)]))
        XCTAssertFalse(BlackjackTotal.isBlackjack([bjCard(.seven), bjCard(.seven, .hearts), bjCard(.seven, .clubs)]))
    }

    // MARK: - Naturals and 3:2

    func testPlayerBlackjackPaysThreeToTwoExactly() throws {
        let round = try round(playerCards: [.ace, .king], dealerCards: [.nine, .seven], bet: 10)
        guard case .settled = round.phase, let settlement = round.settlement else {
            return XCTFail("natural should settle immediately")
        }
        XCTAssertEqual(settlement.hands[0].outcome, .blackjack)
        XCTAssertEqual(settlement.hands[0].returned, 25, "10 stake + 15 winnings")
        XCTAssertEqual(settlement.net, 15)
    }

    func testDealerPeekEndsRoundOnDealerNatural() throws {
        let round = try round(playerCards: [.ten, .nine], dealerCards: [.king, .ace])
        guard case .settled = round.phase, let settlement = round.settlement else {
            return XCTFail("peeked dealer natural should settle immediately")
        }
        XCTAssertEqual(settlement.hands[0].outcome, .dealerBlackjack)
        XCTAssertEqual(settlement.hands[0].returned, 0)
    }

    func testBlackjackVersusBlackjackPushes() throws {
        var rules = BlackjackRules.standard
        rules.insuranceAllowed = false // dealer shows an ace below
        let round = try round(playerCards: [.ace, .queen], dealerCards: [.ace, .king], rules: rules)
        XCTAssertEqual(round.settlement?.hands[0].outcome, .push)
        XCTAssertEqual(round.settlement?.hands[0].returned, 10)
    }

    // MARK: - Insurance

    func testInsurancePaysTwoToOneAgainstDealerNatural() throws {
        var round = try round(playerCards: [.ten, .nine], dealerCards: [.ace, .king])
        guard case .insuranceOffer = round.phase else { return XCTFail("ace up must offer insurance") }
        try round.decideInsurance(take: true)
        guard let settlement = round.settlement else { return XCTFail() }
        XCTAssertEqual(settlement.insuranceBet, 5)
        XCTAssertEqual(settlement.insuranceReturned, 15, "5 stake + 10 winnings")
        // Hand loses 10, insurance nets +10: whole round breaks even.
        XCTAssertEqual(settlement.net, -10 + 10)
    }

    func testDeclinedInsuranceCostsNothing() throws {
        var round = try round(playerCards: [.ten, .nine], dealerCards: [.ace, .king])
        try round.decideInsurance(take: false)
        XCTAssertEqual(round.settlement?.insuranceBet, 0)
        XCTAssertEqual(round.settlement?.net, -10)
    }

    // MARK: - Dealer drawing

    func testDealerStandsOnSoft17ByDefault() throws {
        var round = try round(playerCards: [.ten, .eight], dealerCards: [.ace, .six])
        // Insurance offer first (ace up).
        try round.decideInsurance(take: false)
        try round.apply(.stand, handIndex: 0)
        XCTAssertEqual(round.dealerCards.count, 2, "S17: dealer keeps soft 17")
        XCTAssertEqual(round.settlement?.hands[0].outcome, .win, "18 beats 17")
    }

    func testDealerHitsSoft17WhenConfigured() throws {
        var rules = BlackjackRules.standard
        rules.dealerHitsSoft17 = true
        rules.insuranceAllowed = false
        var round = try round(playerCards: [.ten, .eight], dealerCards: [.ace, .six], next: [.ten], rules: rules)
        try round.apply(.stand, handIndex: 0)
        XCTAssertEqual(round.dealerCards.count, 3, "H17: dealer draws on soft 17")
        XCTAssertEqual(round.dealerTotal, 17, "A+6+10 = hard 17")
        XCTAssertEqual(round.settlement?.hands[0].outcome, .win)
    }

    func testDealerDrawsToSeventeenAndCanBust() throws {
        var round = try round(playerCards: [.ten, .eight], dealerCards: [.six, .ten], next: [.ten])
        try round.apply(.stand, handIndex: 0)
        XCTAssertTrue(round.dealerTotal > 21)
        XCTAssertEqual(round.settlement?.hands[0].outcome, .win)
        XCTAssertEqual(round.settlement?.hands[0].returned, 20)
    }

    // MARK: - Player actions

    func testHitBustLosesImmediately() throws {
        var round = try round(playerCards: [.ten, .six], dealerCards: [.seven, .ten], next: [.king])
        try round.apply(.hit, handIndex: 0)
        XCTAssertEqual(round.settlement?.hands[0].outcome, .bust)
        XCTAssertEqual(round.settlement?.hands[0].returned, 0)
        XCTAssertEqual(round.dealerCards.count, 2, "dealer does not draw when everyone busted")
    }

    func testDoubleTakesExactlyOneCardAndDoublesTheStake() throws {
        var round = try round(playerCards: [.six, .five], dealerCards: [.six, .ten],
                              next: [.ten, .ten, .ten])
        try round.apply(.double, handIndex: 0)
        guard let settlement = round.settlement else { return XCTFail() }
        XCTAssertEqual(round.hands[0].cards.count, 3)
        XCTAssertTrue(round.hands[0].isDoubled)
        XCTAssertEqual(settlement.hands[0].bet, 20)
        XCTAssertEqual(settlement.hands[0].outcome, .win, "21 vs dealer 26 bust")
        XCTAssertEqual(settlement.hands[0].returned, 40)
    }

    func testSplitPlaysBothHandsIndependently() throws {
        // 8,8 vs 10; first hand draws 10 then stands on 18; second draws 5
        // then a 6 for 19. Dealer 10+9 = 19: one push, one loss... play it.
        var round = try round(playerCards: [.eight, .eight], dealerCards: [.ten, .nine],
                              next: [.ten, .five, .six])
        try round.apply(.split, handIndex: 0)
        XCTAssertEqual(round.hands.count, 2)
        XCTAssertTrue(round.hands.allSatisfy { $0.isFromSplit })
        // Hand 0: 8+10 = 18, stand.
        XCTAssertEqual(round.hands[0].total, 18)
        try round.apply(.stand, handIndex: 0)
        // Hand 1: 8+5 = 13, hit → 19, stand.
        guard case .playerTurn(let index) = round.phase, index == 1 else { return XCTFail("turn moves to split hand") }
        try round.apply(.hit, handIndex: 1)
        XCTAssertEqual(round.hands[1].total, 19)
        try round.apply(.stand, handIndex: 1)
        guard let settlement = round.settlement else { return XCTFail() }
        XCTAssertEqual(settlement.hands[0].outcome, .loss, "18 loses to dealer 19")
        XCTAssertEqual(settlement.hands[1].outcome, .push, "19 pushes dealer 19")
        XCTAssertEqual(settlement.net, -10)
    }

    func testResplitUpToFourHandsAndNoFurther() throws {
        // Keep receiving eights: 8,8 → split → each gets an 8 → resplit twice
        // more to reach four hands, then the split option must disappear.
        var round = try round(playerCards: [.eight, .eight], dealerCards: [.ten, .nine],
                              next: [.eight, .eight, .two, .three, .four, .five])
        try round.apply(.split, handIndex: 0)   // hands: [8+8, 8+8]
        XCTAssertTrue(round.legalActions(handIndex: 0).contains(.split))
        try round.apply(.split, handIndex: 0)   // hands: [8+2, 8+3, 8+8]
        XCTAssertEqual(round.hands.count, 3)
        // Find the remaining pair hand and split it for the fourth hand.
        try round.apply(.stand, handIndex: 0)
        try round.apply(.stand, handIndex: 1)
        XCTAssertTrue(round.legalActions(handIndex: 2).contains(.split))
        try round.apply(.split, handIndex: 2)   // four hands
        XCTAssertEqual(round.hands.count, 4)
        XCTAssertFalse(round.legalActions(handIndex: 2).contains(.split), "resplit capped at four hands")
        try round.apply(.stand, handIndex: 2)
        try round.apply(.stand, handIndex: 3)
        XCTAssertNotNil(round.settlement)
    }

    func testSplitAcesReceiveExactlyOneCardEach() throws {
        var round = try round(playerCards: [.ace, .ace], dealerCards: [.ten, .nine],
                              next: [.king, .queen])
        try round.apply(.split, handIndex: 0)
        XCTAssertEqual(round.hands.count, 2)
        XCTAssertTrue(round.hands.allSatisfy { $0.cards.count == 2 && $0.isFinished })
        guard let settlement = round.settlement else { return XCTFail("split aces settle without further input") }
        // A+K after split is 21 but NOT blackjack.
        XCTAssertEqual(settlement.hands[0].outcome, .win)
        XCTAssertEqual(settlement.hands[0].returned, 20, "paid 1:1, not 3:2")
    }

    func testSurrenderReturnsExactlyHalf() throws {
        var rules = BlackjackRules.standard
        rules.surrenderAllowed = true
        var round = try round(playerCards: [.ten, .six], dealerCards: [.ten, .seven], rules: rules)
        XCTAssertTrue(round.legalActions(handIndex: 0).contains(.surrender))
        try round.apply(.surrender, handIndex: 0)
        XCTAssertEqual(round.settlement?.hands[0].outcome, .surrender)
        XCTAssertEqual(round.settlement?.hands[0].returned, 5)
        XCTAssertEqual(round.settlement?.net, -5)
    }

    func testPushReturnsTheStake() throws {
        var round = try round(playerCards: [.ten, .nine], dealerCards: [.ten, .nine])
        try round.apply(.stand, handIndex: 0)
        XCTAssertEqual(round.settlement?.hands[0].outcome, .push)
        XCTAssertEqual(round.settlement?.net, 0)
    }

    // MARK: - Legality

    func testIllegalActionsThrowAndDoNotMutate(){
        var shoe = BlackjackShoe(decks: 6, penetration: 0.75, seed: 3)
        _ = shoe.deal()
        var round = BlackjackRound(rules: .standard, shoe: BlackjackShoe(decks: 6, penetration: 0.75, seed: 3))
        XCTAssertThrowsError(try round.apply(.hit, handIndex: 0), "no acting before dealing")
        XCTAssertThrowsError(try round.deal(bet: 0))
        XCTAssertThrowsError(try round.deal(bet: 7), "odd bets break 3:2 exactness")
        XCTAssertNoThrow(try round.deal(bet: 10))
    }

    func testDoubleUnavailableAfterHitting() throws {
        var round = try round(playerCards: [.two, .three], dealerCards: [.seven, .ten],
                              next: [.four, .five, .ten, .ten])
        XCTAssertTrue(round.legalActions(handIndex: 0).contains(.double))
        try round.apply(.hit, handIndex: 0)
        XCTAssertFalse(round.legalActions(handIndex: 0).contains(.double), "double is two-cards only")
    }

    // MARK: - Conservation and determinism

    func testChipConservationOverARandomSession() throws {
        // Play many rounds with scripted always-stand and check that
        // (bankroll change) == (sum of settlements).
        var shoe = BlackjackShoe(decks: 6, penetration: 0.75, seed: 77)
        var bankroll = 10_000
        var expectedNet = 0
        for _ in 0..<60 {
            if shoe.needsReshuffle { shoe = BlackjackShoe(decks: 6, penetration: 0.75, seed: 78) }
            var round = BlackjackRound(rules: .standard, shoe: shoe)
            try round.deal(bet: 10)
            if case .insuranceOffer = round.phase {
                try round.decideInsurance(take: false)
            }
            while case .playerTurn(let index) = round.phase {
                try round.apply(.stand, handIndex: index)
            }
            guard let settlement = round.settlement else { return XCTFail() }
            bankroll += settlement.net
            expectedNet += settlement.net
            shoe = round.shoe
        }
        XCTAssertEqual(bankroll, 10_000 + expectedNet)
    }

    func testIdenticalSeedAndActionsReproduceTheRound() throws {
        func play(seed: UInt64) throws -> BlackjackSettlement? {
            var round = BlackjackRound(rules: .standard, shoe: BlackjackShoe(decks: 6, penetration: 0.75, seed: seed))
            try round.deal(bet: 10)
            if case .insuranceOffer = round.phase { try round.decideInsurance(take: false) }
            while case .playerTurn(let index) = round.phase {
                if round.legalActions(handIndex: index).contains(.hit) && round.hands[index].total < 15 {
                    try round.apply(.hit, handIndex: index)
                } else {
                    try round.apply(.stand, handIndex: index)
                }
            }
            return round.settlement
        }
        XCTAssertEqual(try play(seed: 314), try play(seed: 314))
        // And save/resume mid-round keeps identical state (§15).
        var round = BlackjackRound(rules: .standard, shoe: BlackjackShoe(decks: 6, penetration: 0.75, seed: 314))
        try round.deal(bet: 10)
        let data = try JSONEncoder().encode(round)
        let restored = try JSONDecoder().decode(BlackjackRound.self, from: data)
        XCTAssertEqual(restored, round)
    }

    // MARK: - Basic strategy (§6): spot checks across every category.

    private func recommendation(player: [Rank], dealerUp: Rank,
                                rules: BlackjackRules = .standard,
                                legal: [BlackjackAction] = [.hit, .stand, .double, .split]) -> BlackjackAction {
        let hand = BlackjackHand(cards: [bjCard(player[0]), BlackjackCard(player[1], .hearts)], bet: 10)
        return BlackjackStrategy.recommend(
            hand: hand, dealerUpcard: bjCard(dealerUp), rules: rules, legalActions: legal
        ).action
    }

    func testBasicStrategyHardTotals() {
        XCTAssertEqual(recommendation(player: [.ten, .six], dealerUp: .ten, legal: [.hit, .stand]), .hit)
        XCTAssertEqual(recommendation(player: [.ten, .six], dealerUp: .six, legal: [.hit, .stand]), .stand)
        XCTAssertEqual(recommendation(player: [.ten, .two], dealerUp: .four, legal: [.hit, .stand]), .stand)
        XCTAssertEqual(recommendation(player: [.ten, .two], dealerUp: .two, legal: [.hit, .stand]), .hit)
        XCTAssertEqual(recommendation(player: [.six, .five], dealerUp: .ten), .double)
        XCTAssertEqual(recommendation(player: [.six, .five], dealerUp: .ace), .hit, "S17: 11 vs A hits")
        XCTAssertEqual(recommendation(player: [.six, .four], dealerUp: .nine), .double)
        XCTAssertEqual(recommendation(player: [.six, .four], dealerUp: .ten), .hit)
        XCTAssertEqual(recommendation(player: [.five, .four], dealerUp: .three), .double)
        XCTAssertEqual(recommendation(player: [.ten, .seven], dealerUp: .ace, legal: [.hit, .stand]), .stand)
    }

    func testBasicStrategyHardElevenVersusAceUnderH17() {
        var rules = BlackjackRules.standard
        rules.dealerHitsSoft17 = true
        XCTAssertEqual(recommendation(player: [.six, .five], dealerUp: .ace, rules: rules), .double)
    }

    func testBasicStrategySoftTotals() {
        XCTAssertEqual(recommendation(player: [.ace, .six], dealerUp: .four), .double)
        XCTAssertEqual(recommendation(player: [.ace, .six], dealerUp: .two, legal: [.hit, .stand]), .hit)
        XCTAssertEqual(recommendation(player: [.ace, .seven], dealerUp: .five), .double)
        XCTAssertEqual(recommendation(player: [.ace, .seven], dealerUp: .eight, legal: [.hit, .stand]), .stand)
        XCTAssertEqual(recommendation(player: [.ace, .seven], dealerUp: .ten, legal: [.hit, .stand]), .hit)
        XCTAssertEqual(recommendation(player: [.ace, .eight], dealerUp: .six, legal: [.hit, .stand]), .stand)
        XCTAssertEqual(recommendation(player: [.ace, .two], dealerUp: .five), .double)
        XCTAssertEqual(recommendation(player: [.ace, .two], dealerUp: .four, legal: [.hit, .stand]), .hit)
    }

    func testBasicStrategyPairs() {
        XCTAssertEqual(recommendation(player: [.ace, .ace], dealerUp: .ten), .split)
        XCTAssertEqual(recommendation(player: [.eight, .eight], dealerUp: .ten), .split)
        XCTAssertEqual(recommendation(player: [.ten, .ten], dealerUp: .six), .stand)
        XCTAssertEqual(recommendation(player: [.nine, .nine], dealerUp: .seven), .stand)
        XCTAssertEqual(recommendation(player: [.nine, .nine], dealerUp: .six), .split)
        XCTAssertEqual(recommendation(player: [.five, .five], dealerUp: .six), .double, "5,5 plays as hard 10")
        XCTAssertEqual(recommendation(player: [.four, .four], dealerUp: .five), .split, "DAS splits 4,4 vs 5")
        XCTAssertEqual(recommendation(player: [.seven, .seven], dealerUp: .eight, legal: [.hit, .stand, .split]), .hit)
        XCTAssertEqual(recommendation(player: [.two, .two], dealerUp: .three), .split, "DAS splits 2,2 vs 3")
    }

    func testBasicStrategyPairsWithoutDAS() {
        var rules = BlackjackRules.standard
        rules.doubleAfterSplitAllowed = false
        XCTAssertEqual(recommendation(player: [.four, .four], dealerUp: .five, rules: rules), .hit)
        XCTAssertEqual(recommendation(player: [.two, .two], dealerUp: .three, rules: rules), .hit)
        XCTAssertEqual(recommendation(player: [.six, .six], dealerUp: .two, rules: rules, legal: [.hit, .stand, .split]), .hit)
    }

    func testBasicStrategySurrender() {
        var rules = BlackjackRules.standard
        rules.surrenderAllowed = true
        let legal: [BlackjackAction] = [.hit, .stand, .surrender]
        XCTAssertEqual(recommendation(player: [.ten, .six], dealerUp: .ten, rules: rules, legal: legal), .surrender)
        XCTAssertEqual(recommendation(player: [.ten, .five], dealerUp: .ten, rules: rules, legal: legal), .surrender)
        XCTAssertEqual(recommendation(player: [.ten, .five], dealerUp: .nine, rules: rules, legal: legal), .hit)
        XCTAssertEqual(recommendation(player: [.eight, .eight], dealerUp: .ten, rules: rules,
                                      legal: [.hit, .stand, .split, .surrender]), .split, "8,8 splits before surrendering")
    }

    // MARK: - Counting (§6)

    func testHiLoValuesAndFullShoeBalance() {
        XCTAssertEqual(bjCard(.two).hiLoValue, 1)
        XCTAssertEqual(bjCard(.six).hiLoValue, 1)
        XCTAssertEqual(bjCard(.seven).hiLoValue, 0)
        XCTAssertEqual(bjCard(.nine).hiLoValue, 0)
        XCTAssertEqual(bjCard(.ten).hiLoValue, -1)
        XCTAssertEqual(bjCard(.ace).hiLoValue, -1)
        // A balanced count sums to zero over any full shoe.
        let simulation = CountingTrainer.shoeSimulation(decks: 2, burstSize: 10, seed: 5)
        XCTAssertEqual(simulation.finalCount, 0)
        XCTAssertEqual(simulation.bursts.flatMap { $0 }.count, 104)
    }

    func testTrueCountConversion() {
        XCTAssertEqual(CountingTrainer.trueCount(running: 6, decksRemaining: 3.0), 2)
        XCTAssertEqual(CountingTrainer.trueCount(running: -4, decksRemaining: 2.0), -2)
        XCTAssertEqual(CountingTrainer.trueCount(running: 5, decksRemaining: 0.4), 10, "floors at half a deck")
    }

    func testDrillIsDeterministic() {
        let a = CountingTrainer.drill(count: 12, seed: 8)
        let b = CountingTrainer.drill(count: 12, seed: 8)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.correctRunningCount, CountingTrainer.runningCount(a.cards))
    }

    func testRulesValidation() {
        XCTAssertEqual(BlackjackRules.standard.validate(), [])
        var bad = BlackjackRules.standard
        bad.decks = 0
        bad.penetration = 0.1
        XCTAssertEqual(bad.validate().count, 2)
    }
}
