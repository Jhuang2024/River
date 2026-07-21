import Foundation

/// Basic session statistics computed from stored hand histories.
/// Sample-size honesty: the UI shows these as descriptive numbers for the
/// session, not as confident leak claims (that arrives in a later phase).
public struct SessionStats: Equatable, Sendable {
    public let handsPlayed: Int
    public let handsWon: Int
    /// Voluntarily put money in pot (excluding blind posts) - count and %.
    public let vpipCount: Int
    /// Preflop raise count.
    public let pfrCount: Int
    public let showdownsSeen: Int
    public let showdownsWon: Int
    public let biggestPotWon: Int
    public let netChips: Int

    public var vpipPercent: Double {
        return handsPlayed > 0 ? Double(vpipCount) / Double(handsPlayed) * 100 : 0
    }

    public var pfrPercent: Double {
        return handsPlayed > 0 ? Double(pfrCount) / Double(handsPlayed) * 100 : 0
    }

    public static func compute(histories: [HandHistory], seat: Int) -> SessionStats {
        var handsWon = 0
        var vpip = 0
        var pfr = 0
        var showdowns = 0
        var showdownsWon = 0
        var biggestPot = 0
        var net = 0

        for history in histories {
            if history.netChips.indices.contains(seat) {
                net += history.netChips[seat]
            }
            var wonThisHand = 0
            var voluntary = false
            var raisedPre = false
            var atShowdown = false
            for event in history.events {
                switch event {
                case .action(let actionSeat, let street, let kind, _, _, _):
                    if actionSeat == seat && street == .preflop {
                        if kind == .call || kind == .bet || kind == .raise {
                            voluntary = true
                        }
                        if kind == .raise || kind == .bet {
                            raisedPre = true
                        }
                    }
                case .showedHand(let shownSeat, _, _):
                    if shownSeat == seat {
                        atShowdown = true
                    }
                case .wonPot(let winner, let amount, _, _):
                    if winner == seat {
                        wonThisHand += amount
                    }
                case .wonWithoutShowdown(let winner, let amount):
                    if winner == seat {
                        wonThisHand += amount
                    }
                default:
                    break
                }
            }
            if wonThisHand > 0 {
                handsWon += 1
                biggestPot = max(biggestPot, wonThisHand)
                if atShowdown {
                    showdownsWon += 1
                }
            }
            if atShowdown {
                showdowns += 1
            }
            if voluntary {
                vpip += 1
            }
            if raisedPre {
                pfr += 1
            }
        }

        return SessionStats(
            handsPlayed: histories.count,
            handsWon: handsWon,
            vpipCount: vpip,
            pfrCount: pfr,
            showdownsSeen: showdowns,
            showdownsWon: showdownsWon,
            biggestPotWon: biggestPot,
            netChips: net
        )
    }
}
