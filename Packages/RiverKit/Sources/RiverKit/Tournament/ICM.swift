import Foundation

/// Exact Malmuth-Harville ICM for up to six players (§21). Isolated from all
/// cash-game logic; cash games never consult it (§28 of the AI spec).
public enum ICM {

    /// Exact recursive prize equity for each player.
    /// - Parameters:
    ///   - stacks: chip stacks (0 entries are ignored/eliminated).
    ///   - payouts: prize for 1st, 2nd, ... (shorter than player count is fine).
    /// - Returns: equity per input index (0 for empty stacks).
    public static func equities(stacks: [Int], payouts: [Double]) -> [Double] {
        let players = stacks.indices.filter { stacks[$0] > 0 }
        var result = [Double](repeating: 0, count: stacks.count)
        guard !players.isEmpty, !payouts.isEmpty else { return result }
        precondition(players.count <= 8, "exact ICM is exponential; bounded to small fields")

        // P(finishing order prefix) via Malmuth-Harville: the chance a player
        // finishes next among the remaining field is proportional to stack.
        func recurse(remaining: [Int], place: Int, probability: Double) {
            guard place < payouts.count else { return }
            let total = remaining.reduce(0.0) { $0 + Double(stacks[$1]) }
            guard total > 0 else { return }
            for player in remaining {
                let pFirst = Double(stacks[player]) / total
                let p = probability * pFirst
                result[player] += p * payouts[place]
                if remaining.count > 1 && place + 1 < payouts.count {
                    recurse(remaining: remaining.filter { $0 != player }, place: place + 1, probability: p)
                }
            }
        }
        recurse(remaining: players, place: 0, probability: 1)
        return result
    }

    /// The ICM risk premium of an all-in for `heroIndex` (§21): how much MORE
    /// than raw chip pot-odds equity the call needs, expressed as an equity
    /// fraction in 0...1.
    ///
    /// Computed from three futures: fold now, call-and-win, call-and-lose,
    /// each priced in exact prize equity.
    public static func riskPremium(
        stacks: [Int],
        payouts: [Double],
        heroIndex: Int,
        villainIndex: Int,
        amountAtRisk: Int
    ) -> Double {
        guard stacks.indices.contains(heroIndex), stacks.indices.contains(villainIndex),
              heroIndex != villainIndex, amountAtRisk > 0 else { return 0 }
        let risk = min(amountAtRisk, min(stacks[heroIndex], stacks[villainIndex]))
        guard risk > 0 else { return 0 }

        var winStacks = stacks
        winStacks[heroIndex] += risk
        winStacks[villainIndex] -= risk
        var loseStacks = stacks
        loseStacks[heroIndex] -= risk
        loseStacks[villainIndex] += risk

        let winEquity = equities(stacks: winStacks, payouts: payouts)[heroIndex]
        let loseEquity = equities(stacks: loseStacks, payouts: payouts)[heroIndex]
        guard winEquity > loseEquity else { return 0 }

        // Chip-EV breakeven is risk/(2*risk) = 50% of the matched chips; the
        // $EV breakeven is where p*win + (1-p)*lose equals folding equity -
        // approximate the premium as the shift of the breakeven point.
        let foldEquity = equities(stacks: stacks, payouts: payouts)[heroIndex]
        let breakEven = (foldEquity - loseEquity) / (winEquity - loseEquity)
        // Chip-only breakeven for a call of `risk` into a pot of 2*risk ≈ 0.5.
        let premium = breakEven - 0.5
        return max(0, min(0.4, premium))
    }
}
