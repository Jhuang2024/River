import Foundation

/// Range-aware equity engine (§16): exact enumeration where feasible (river
/// versus one range), seeded Monte Carlo otherwise. Deterministic per seed.
public enum EquityEngine {

    public struct Result: Equatable, Sendable {
        public let win: Double
        public let tie: Double
        /// Expected pot share: win + tie split.
        public let share: Double
        public let trials: Int
        public let isExact: Bool
        public let seed: UInt64
    }

    /// Equity of `hole` + `board` against one weighted range per opponent.
    /// - Exact when the board is complete and there is a single opponent.
    /// - Monte Carlo otherwise: samples each opponent's combo from their
    ///   range (collision-rejected) and completes the board.
    public static func equity(hole: [Card], board: [Card], vsRanges: [HandRange], iterations: Int, seed: UInt64) -> Result {
        precondition(hole.count == 2)
        precondition(!vsRanges.isEmpty)
        let dead = Set(hole + board)
        let ranges = vsRanges.map { $0.removingCombos(containing: dead) }

        if board.count == 5 && ranges.count == 1 {
            return exactRiver(hole: hole, board: board, range: ranges[0], seed: seed)
        }
        return monteCarlo(hole: hole, board: board, ranges: ranges, iterations: iterations, seed: seed)
    }

    /// Async wrapper with cooperative cancellation (§17). Returns the best
    /// partial result if cancelled mid-way.
    public static func equityAsync(hole: [Card], board: [Card], vsRanges: [HandRange], iterations: Int, seed: UInt64) async -> Result {
        let dead = Set(hole + board)
        let ranges = vsRanges.map { $0.removingCombos(containing: dead) }
        if board.count == 5 && ranges.count == 1 {
            return exactRiver(hole: hole, board: board, range: ranges[0], seed: seed)
        }
        // Chunked Monte Carlo so cancellation is responsive.
        let chunk = max(50, iterations / 8)
        var completed = 0
        var winTotal = 0.0
        var tieTotal = 0.0
        var shareTotal = 0.0
        var rng = SeededRNG(seed: seed)
        while completed < iterations && !Task.isCancelled {
            let n = min(chunk, iterations - completed)
            let partial = monteCarloPass(hole: hole, board: board, ranges: ranges, iterations: n, rng: &rng)
            winTotal += partial.winSum
            tieTotal += partial.tieSum
            shareTotal += partial.shareSum
            completed += partial.trials
            await Task.yield()
        }
        guard completed > 0 else {
            return Result(win: 0, tie: 0, share: 0, trials: 0, isExact: false, seed: seed)
        }
        return Result(
            win: winTotal / Double(completed),
            tie: tieTotal / Double(completed),
            share: shareTotal / Double(completed),
            trials: completed,
            isExact: false,
            seed: seed
        )
    }

    // MARK: - Exact river vs one range

    private static func exactRiver(hole: [Card], board: [Card], range: HandRange, seed: UInt64) -> Result {
        let heroValue = HandEvaluator.evaluate(hole: hole, board: board)
        var win = 0.0
        var tie = 0.0
        var total = 0.0
        for (combo, weight) in range.weights {
            let value = HandEvaluator.evaluate(hole: combo.cards, board: board)
            total += weight
            if heroValue > value {
                win += weight
            } else if heroValue == value {
                tie += weight
            }
        }
        guard total > 0 else {
            return Result(win: 0.5, tie: 0, share: 0.5, trials: 0, isExact: true, seed: seed)
        }
        let winFraction = win / total
        let tieFraction = tie / total
        return Result(
            win: winFraction,
            tie: tieFraction,
            share: winFraction + tieFraction / 2,
            trials: Int(range.weights.count),
            isExact: true,
            seed: seed
        )
    }

    // MARK: - Monte Carlo

    private static func monteCarlo(hole: [Card], board: [Card], ranges: [HandRange], iterations: Int, seed: UInt64) -> Result {
        var rng = SeededRNG(seed: seed)
        let pass = monteCarloPass(hole: hole, board: board, ranges: ranges, iterations: iterations, rng: &rng)
        guard pass.trials > 0 else {
            return Result(win: 0, tie: 0, share: 0, trials: 0, isExact: false, seed: seed)
        }
        return Result(
            win: pass.winSum / Double(pass.trials),
            tie: pass.tieSum / Double(pass.trials),
            share: pass.shareSum / Double(pass.trials),
            trials: pass.trials,
            isExact: false,
            seed: seed
        )
    }

    private struct PassResult {
        var winSum = 0.0
        /// Sum of trials that ended in any tie with the best opponent.
        var tieSum = 0.0
        /// Sum of the hero's pot share (1 for wins, split share for ties).
        var shareSum = 0.0
        var trials = 0
    }

    /// Pre-sorted weighted entries so per-iteration sampling never re-sorts.
    private struct WeightedSampler {
        let entries: [(combo: HoleCombo, weight: Double)]

        init(_ range: HandRange) {
            entries = range.weights
                .map { (combo: $0.key, weight: $0.value) }
                .sorted { lhs, rhs in
                    if lhs.combo.first != rhs.combo.first { return lhs.combo.first < rhs.combo.first }
                    return lhs.combo.second < rhs.combo.second
                }
        }

        func sample(excluding dead: Set<Card>, rng: inout SeededRNG) -> HoleCombo? {
            var total = 0.0
            for entry in entries where !entry.combo.contains(any: dead) {
                total += entry.weight
            }
            guard total > 0 else { return nil }
            var target = rng.double01() * total
            var last: HoleCombo? = nil
            for entry in entries where !entry.combo.contains(any: dead) {
                last = entry.combo
                target -= entry.weight
                if target <= 0 {
                    return entry.combo
                }
            }
            return last
        }
    }

    private static func monteCarloPass(hole: [Card], board: [Card], ranges: [HandRange], iterations: Int, rng: inout SeededRNG) -> PassResult {
        let baseDead = Set(hole + board)
        let stock = Deck.standard().filter { !baseDead.contains($0) }
        let boardNeeded = 5 - board.count
        var result = PassResult()
        let samplers = ranges.map { WeightedSampler($0) }

        for _ in 0..<max(1, iterations) {
            var dead = baseDead
            var opponentHands: [[Card]] = []
            var failed = false
            for sampler in samplers {
                if let combo = sampler.sample(excluding: dead, rng: &rng) {
                    opponentHands.append(combo.cards)
                    dead.insert(combo.first)
                    dead.insert(combo.second)
                } else {
                    // Range fully blocked by dead cards: deal uniformly.
                    var remaining = stock.filter { !dead.contains($0) }
                    guard remaining.count >= 2 else { failed = true; break }
                    var upper = remaining.count
                    let i = rng.int(upperBound: upper)
                    remaining.swapAt(i, upper - 1)
                    let c1 = remaining[upper - 1]
                    upper -= 1
                    let j = rng.int(upperBound: upper)
                    remaining.swapAt(j, upper - 1)
                    let c2 = remaining[upper - 1]
                    opponentHands.append([c1, c2])
                    dead.insert(c1)
                    dead.insert(c2)
                }
            }
            if failed { continue }

            // Complete the board from the unblocked remainder.
            var fullBoard = board
            if boardNeeded > 0 {
                var available = stock.filter { !dead.contains($0) }
                guard available.count >= boardNeeded else { continue }
                var upper = available.count
                for _ in 0..<boardNeeded {
                    let index = rng.int(upperBound: upper)
                    available.swapAt(index, upper - 1)
                    fullBoard.append(available[upper - 1])
                    upper -= 1
                }
            }

            let heroValue = HandEvaluator.evaluate(hole: hole, board: fullBoard)
            var best: HandValue? = nil
            var bestCount = 0
            for opponent in opponentHands {
                let value = HandEvaluator.evaluate(hole: opponent, board: fullBoard)
                if best == nil || value > best! {
                    best = value
                    bestCount = 1
                } else if value == best! {
                    bestCount += 1
                }
            }
            result.trials += 1
            if let opponentBest = best {
                if heroValue > opponentBest {
                    result.winSum += 1
                    result.shareSum += 1
                } else if heroValue == opponentBest {
                    result.tieSum += 1
                    result.shareSum += 1.0 / Double(bestCount + 1)
                }
            }
        }
        return result
    }
}

/// Pot-odds mathematics with one consistent set of definitions (§18).
public enum PotMath {

    public struct PotOdds: Equatable, Sendable {
        public let amountToCall: Int
        public let potBeforeCall: Int
        public let finalPot: Int
        /// C / (P + C): the break-even equity for a call.
        public let requiredEquity: Double
    }

    /// - Parameters:
    ///   - amountToCall: chips the caller must add.
    ///   - potBeforeCall: every chip already committed by everyone (including
    ///     the caller's own previous commitments — they are in the pot).
    public static func odds(amountToCall: Int, potBeforeCall: Int) -> PotOdds {
        let call = max(0, amountToCall)
        let pot = max(0, potBeforeCall)
        let final = pot + call
        return PotOdds(
            amountToCall: call,
            potBeforeCall: pot,
            finalPot: final,
            requiredEquity: final > 0 ? Double(call) / Double(final) : 0
        )
    }

    /// EV of calling in chips: equity × finalPot − call (§19). Approximate —
    /// ignores future betting.
    public static func callEV(equity: Double, amountToCall: Int, potBeforeCall: Int) -> Double {
        let odds = odds(amountToCall: amountToCall, potBeforeCall: potBeforeCall)
        return equity * Double(odds.finalPot) - Double(odds.amountToCall)
    }
}
