import Foundation

/// Observed, public behaviour for one seat (§29). Estimates carry sample
/// counts so consumers can gate on evidence; no hidden information involved.
public struct SeatTendencies: Codable, Equatable, Sendable {
    public var handsObserved: Int
    public var vpipPercent: Double
    public var pfrPercent: Double
    /// How often the seat folded when facing a flop continuation bet.
    public var foldToCBetPercent: Double
    public var cbetOpportunities: Int
    public var showdownPercent: Double

    public enum Confidence: String, Codable, Sendable {
        case low
        case moderate
        case high
    }

    public var confidence: Confidence {
        if handsObserved < 20 { return .low }
        if handsObserved < 60 { return .moderate }
        return .high
    }

    /// Enough evidence for bounded adaptation (§30).
    public var sufficientForAdaptation: Bool {
        return handsObserved >= 30
    }
}

/// Builds per-seat tendencies from completed hand histories. Everything used
/// here was publicly visible at the table.
public enum TendencyObserver {

    public static func compute(histories: [HandHistory]) -> [Int: SeatTendencies] {
        var hands: [Int: Int] = [:]
        var vpip: [Int: Int] = [:]
        var pfr: [Int: Int] = [:]
        var showdown: [Int: Int] = [:]
        var facedCBet: [Int: Int] = [:]
        var foldedToCBet: [Int: Int] = [:]

        for history in histories {
            var participated = Set<Int>()
            var voluntary = Set<Int>()
            var raisedPre = Set<Int>()
            var reachedShowdown = Set<Int>()
            var preflopAggressor: Int? = nil
            var flopCBetter: Int? = nil

            for event in history.events {
                switch event {
                case .dealtHoleCards(let seat, _):
                    participated.insert(seat)
                case .action(let seat, let street, let kind, _, _, _):
                    if street == .preflop {
                        if kind == .call || kind == .bet || kind == .raise {
                            voluntary.insert(seat)
                        }
                        if kind == .bet || kind == .raise {
                            raisedPre.insert(seat)
                            preflopAggressor = seat
                        }
                    } else if street == .flop {
                        if kind == .bet && seat == preflopAggressor {
                            flopCBetter = seat
                        } else if let cbetter = flopCBetter, seat != cbetter {
                            facedCBet[seat, default: 0] += 1
                            if kind == .fold {
                                foldedToCBet[seat, default: 0] += 1
                            }
                        }
                    }
                case .showedHand(let seat, _, _):
                    reachedShowdown.insert(seat)
                default:
                    break
                }
            }
            for seat in participated {
                hands[seat, default: 0] += 1
                if voluntary.contains(seat) { vpip[seat, default: 0] += 1 }
                if raisedPre.contains(seat) { pfr[seat, default: 0] += 1 }
                if reachedShowdown.contains(seat) { showdown[seat, default: 0] += 1 }
            }
        }

        var result: [Int: SeatTendencies] = [:]
        for (seat, count) in hands where count > 0 {
            let cbetFaced = facedCBet[seat] ?? 0
            result[seat] = SeatTendencies(
                handsObserved: count,
                vpipPercent: Double(vpip[seat] ?? 0) / Double(count) * 100,
                pfrPercent: Double(pfr[seat] ?? 0) / Double(count) * 100,
                foldToCBetPercent: cbetFaced > 0 ? Double(foldedToCBet[seat] ?? 0) / Double(cbetFaced) * 100 : 0,
                cbetOpportunities: cbetFaced,
                showdownPercent: Double(showdown[seat] ?? 0) / Double(count) * 100
            )
        }
        return result
    }
}
