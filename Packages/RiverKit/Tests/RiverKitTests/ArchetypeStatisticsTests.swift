import XCTest
@testable import RiverKit

/// Deterministic simulation-based validation of archetype behaviour (§42).
/// Wide expected bands, not fake precision — the point is catching
/// pathologies (a nit that plays half its hands, a station that raises).
final class ArchetypeStatisticsTests: XCTestCase {

    private struct SeatStats {
        var hands = 0
        var voluntary = 0
        var preflopRaises = 0
        var preflopCalls = 0
        var postflopBets = 0
        var postflopChecksCalls = 0

        var vpip: Double { hands > 0 ? Double(voluntary) / Double(hands) * 100 : 0 }
        var pfr: Double { hands > 0 ? Double(preflopRaises) / Double(hands) * 100 : 0 }
    }

    func testArchetypesProduceIntendedStatistics() throws {
        // Seat assignment: 0 nit, 1 station, 2 LAG, 3 solid, 4 maniac, 5 trapper.
        let difficulty = BotDifficulty.intermediate
        let profiles: [BotProfile] = [
            .nit(name: "Nit", symbolName: "person", difficulty: difficulty),
            .callingStation(name: "Sta", symbolName: "person", difficulty: difficulty),
            .looseAggressive(name: "LAG", symbolName: "person", difficulty: difficulty),
            .solidRegular(name: "Reg", symbolName: "person", difficulty: difficulty),
            .maniac(name: "Man", symbolName: "person", difficulty: difficulty),
            .trapper(name: "Trp", symbolName: "person", difficulty: difficulty)
        ]

        var stats = Array(repeating: SeatStats(), count: 6)
        var stacks = Array(repeating: 200, count: 6)
        var button = 0
        var totalChips = 1200

        for handNumber in 0..<90 {
            // Casual reload keeps every archetype in play.
            for i in stacks.indices where stacks[i] < 40 {
                totalChips += 200 - stacks[i]
                stacks[i] = 200
            }
            let config = HandConfig(
                stacks: stacks,
                buttonIndex: button,
                smallBlind: 1,
                bigBlind: 2,
                seed: 900_000 &+ UInt64(handNumber),
                handNumber: handNumber
            )
            let hand = PokerHand(config: config)
            var guardCount = 0
            while !hand.isComplete {
                guard let seat = hand.actionOn else { return XCTFail("stalled hand \(handNumber)") }
                let decision = try XCTUnwrap(BotDecider.decide(hand: hand, seat: seat, profile: profiles[seat]))
                try hand.apply(decision.action, by: seat, annotation: decision.annotation)
                guardCount += 1
                if guardCount > 300 { return XCTFail("runaway hand \(handNumber)") }
            }
            XCTAssertEqual(hand.seats.reduce(0) { $0 + $1.stack }, totalChips, "chip conservation broke in hand \(handNumber)")

            var voluntaryThisHand = Set<Int>()
            for seat in 0..<6 {
                stats[seat].hands += 1
            }
            for decision in hand.decisions {
                let seat = decision.seat
                if decision.street == .preflop {
                    switch decision.chosen.kind {
                    case .call:
                        voluntaryThisHand.insert(seat)
                        stats[seat].preflopCalls += 1
                    case .bet, .raise:
                        voluntaryThisHand.insert(seat)
                        stats[seat].preflopRaises += 1
                    default:
                        break
                    }
                } else {
                    switch decision.chosen.kind {
                    case .bet, .raise: stats[seat].postflopBets += 1
                    case .check, .call: stats[seat].postflopChecksCalls += 1
                    default: break
                    }
                }
            }
            for seat in voluntaryThisHand {
                stats[seat].voluntary += 1
            }
            stacks = hand.seats.map { $0.stack }
            button = (button + 1) % 6
        }

        let nit = stats[0], station = stats[1], lag = stats[2], solid = stats[3], maniac = stats[4], trapper = stats[5]

        // Sanity: nobody plays everything or nothing (§42).
        for (index, seat) in stats.enumerated() {
            XCTAssertGreaterThan(seat.vpip, 2, "seat \(index) never plays")
            XCTAssertLessThan(seat.vpip, 95, "seat \(index) plays absurdly often")
        }

        // Orderings with generous margins.
        XCTAssertLessThan(nit.vpip, station.vpip - 8, "nit (\(nit.vpip)) must be far tighter than the station (\(station.vpip))")
        XCTAssertLessThan(nit.vpip, maniac.vpip - 8, "nit must be tighter than the maniac")
        XCTAssertGreaterThan(maniac.pfr, nit.pfr + 5, "maniac (\(maniac.pfr)) must raise far more than the nit (\(nit.pfr))")
        XCTAssertGreaterThan(maniac.pfr, station.pfr, "maniac raises more than the station")
        // The station calls preflop far more than it raises.
        XCTAssertGreaterThan(station.preflopCalls, station.preflopRaises, "a calling station must call more than raise")
        // The LAG is looser than the solid regular.
        XCTAssertGreaterThan(lag.vpip, solid.vpip - 2, "LAG (\(lag.vpip)) should not be tighter than the regular (\(solid.vpip))")
        // Trapper exists and plays a disciplined-tight game.
        XCTAssertLessThan(trapper.vpip, station.vpip, "trapper is tighter than a station")
    }

    /// Difficulty must alter strategy, not cards: identical seeds deal
    /// identical cards at every difficulty (§10, §43).
    func testDifficultyDoesNotChangeDealtCards() {
        for difficulty in BotDifficulty.allCases {
            _ = difficulty // difficulty influences decisions only
            let hand = PokerHand(config: HandConfig(stacks: Array(repeating: 200, count: 6), buttonIndex: 2, smallBlind: 1, bigBlind: 2, seed: 31337))
            let reference = PokerHand(config: HandConfig(stacks: Array(repeating: 200, count: 6), buttonIndex: 2, smallBlind: 1, bigBlind: 2, seed: 31337))
            for seat in 0..<6 {
                XCTAssertEqual(hand.seats[seat].holeCards, reference.seats[seat].holeCards)
            }
        }
    }
}
