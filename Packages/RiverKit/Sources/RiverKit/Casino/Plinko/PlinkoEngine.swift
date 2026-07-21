import Foundation

/// Plinko configuration (§4): board size and risk level select a validated
/// multiplier table. Multipliers are stored in hundredths so payouts are
/// exact integer arithmetic; the payout for a wager is
/// `wager * multiplierHundredths / 100`, floored deterministically.
public enum PlinkoRows: Int, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case eight = 8
    case twelve = 12
    case sixteen = 16

    public var id: Int { rawValue }
    public var slotCount: Int { rawValue + 1 }
    public var displayName: String { "\(rawValue) rows" }
}

public enum PlinkoRisk: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case low
    case medium
    case high

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
}

/// Versioned multiplier tables (§4). Symmetric, slot count = rows + 1, and
/// every table's expected value sits just under 1.0 (a small, disclosed
/// house edge) - validation enforces all of it.
public enum PlinkoTables {
    public static let configVersion = 1

    /// Multiplier in hundredths per landing slot (left to right).
    public static func multipliers(rows: PlinkoRows, risk: PlinkoRisk) -> [Int] {
        switch (rows, risk) {
        case (.eight, .low):
            return [560, 210, 110, 100, 50, 100, 110, 210, 560]
        case (.eight, .medium):
            return [1300, 300, 130, 70, 40, 70, 130, 300, 1300]
        case (.eight, .high):
            return [2900, 400, 150, 30, 20, 30, 150, 400, 2900]
        case (.twelve, .low):
            return [1000, 300, 190, 140, 110, 100, 50, 100, 110, 140, 190, 300, 1000]
        case (.twelve, .medium):
            return [3300, 1100, 400, 200, 110, 60, 30, 60, 110, 200, 400, 1100, 3300]
        case (.twelve, .high):
            return [17000, 2400, 700, 200, 70, 30, 20, 30, 70, 200, 700, 2400, 17000]
        case (.sixteen, .low):
            return [1600, 900, 200, 140, 140, 120, 110, 100, 50, 100, 110, 120, 140, 140, 200, 900, 1600]
        case (.sixteen, .medium):
            return [11000, 4100, 1000, 500, 300, 150, 100, 50, 30, 50, 100, 150, 300, 500, 1000, 4100, 11000]
        case (.sixteen, .high):
            return [100000, 13000, 2600, 900, 400, 200, 20, 20, 20, 20, 20, 200, 400, 900, 2600, 13000, 100000]
        }
    }

    /// Exact expected value in millionths of the wager (binomial landing
    /// distribution). Used by validation and the fairness display.
    public static func expectedValueMillionths(rows: PlinkoRows, risk: PlinkoRisk) -> Int {
        let table = multipliers(rows: rows, risk: risk)
        let n = rows.rawValue
        // Sum of C(n, k) * multiplier, exact in integer arithmetic.
        var weighted = 0
        var coefficient = 1 // C(n, 0)
        for k in 0...n {
            weighted += coefficient * table[k]
            if k < n {
                coefficient = coefficient * (n - k) / (k + 1)
            }
        }
        // weighted / 2^n is EV in hundredths; scale to millionths.
        return weighted * 10_000 / (1 << n)
    }

    /// Configuration validation (§13): symmetry, size, sane and sub-1.0 EV.
    public static func validate() -> [String] {
        var problems: [String] = []
        for rows in PlinkoRows.allCases {
            for risk in PlinkoRisk.allCases {
                let table = multipliers(rows: rows, risk: risk)
                let name = "\(rows.rawValue)/\(risk.rawValue)"
                if table.count != rows.slotCount {
                    problems.append("\(name): expected \(rows.slotCount) slots")
                }
                for index in 0..<(table.count / 2) where table[index] != table[table.count - 1 - index] {
                    problems.append("\(name): asymmetric at slot \(index)")
                }
                if table.contains(where: { $0 <= 0 }) {
                    problems.append("\(name): non-positive multiplier")
                }
                if table.max() ?? 0 <= 100 {
                    problems.append("\(name): no winning slot")
                }
                let ev = expectedValueMillionths(rows: rows, risk: risk)
                if ev >= 1_000_000 { problems.append("\(name): EV \(ev) not below 1.0") }
                if ev < 950_000 { problems.append("\(name): EV \(ev) unfairly low") }
            }
        }
        return problems
    }
}

/// One authoritative drop (§4): the seeded model decides the peg decisions
/// and therefore the slot BEFORE anything animates. The animation replays
/// the same path; frame rate cannot change the payout (§3, §14).
public struct PlinkoDrop: Codable, Hashable, Sendable {
    public let seed: UInt64
    public let rows: PlinkoRows
    public let risk: PlinkoRisk
    public let wager: Int
    /// Per-row decisions: false = left, true = right.
    public let path: [Bool]
    /// Final slot index = number of rights.
    public let slot: Int
    public let multiplierHundredths: Int
    public let payout: Int

    public var multiplierText: String {
        let whole = multiplierHundredths / 100
        let cents = multiplierHundredths % 100
        if cents == 0 { return "\(whole)x" }
        if cents % 10 == 0 { return "\(whole).\(cents / 10)x" }
        return String(format: "%d.%02dx", whole, cents)
    }

    public var net: Int { payout - wager }
}

public enum PlinkoEngine {

    /// Computes a drop's outcome from the seed alone. Bankroll, streaks and
    /// history are not inputs, so they cannot bend the odds (§3).
    public static func drop(rows: PlinkoRows, risk: PlinkoRisk, wager: Int, seed: UInt64) -> PlinkoDrop {
        precondition(wager >= 0)
        var rng = SeededRNG.derive(seed: seed, stream: 82_001)
        var path: [Bool] = []
        path.reserveCapacity(rows.rawValue)
        var rights = 0
        for _ in 0..<rows.rawValue {
            let right = rng.int(upperBound: 2) == 1
            path.append(right)
            if right { rights += 1 }
        }
        let table = PlinkoTables.multipliers(rows: rows, risk: risk)
        let multiplier = table[rights]
        let payout = wager * multiplier / 100
        return PlinkoDrop(seed: seed, rows: rows, risk: risk, wager: wager,
                          path: path, slot: rights,
                          multiplierHundredths: multiplier, payout: payout)
    }

    /// Derives per-ball seeds for a batch from one session seed, so a batch
    /// is reproducible while each ball stays independent.
    public static func ballSeed(sessionSeed: UInt64, ballIndex: Int) -> UInt64 {
        var rng = SeededRNG.derive(seed: sessionSeed, stream: 83_000 &+ UInt64(ballIndex))
        return rng.nextUInt64()
    }
}

/// Auto-drop plan with stop conditions (§4). Evaluated between balls by the
/// UI layer; the engine exposes the pure stopping rule so it can be tested.
public struct PlinkoAutoDrop: Codable, Hashable, Sendable {
    public var ballCount: Int
    public var wagerPerBall: Int
    /// Delay between balls in milliseconds (UI pacing only).
    public var delayMillis: Int
    /// Stop when session net profit reaches this (nil = no target).
    public var profitTarget: Int?
    /// Stop when session net loss reaches this (nil = no limit).
    public var lossLimit: Int?
    /// Stop when bankroll falls below this (nil = no threshold).
    public var bankrollFloor: Int?

    public init(ballCount: Int = 10, wagerPerBall: Int = 10, delayMillis: Int = 400,
                profitTarget: Int? = nil, lossLimit: Int? = nil, bankrollFloor: Int? = nil) {
        self.ballCount = ballCount
        self.wagerPerBall = wagerPerBall
        self.delayMillis = delayMillis
        self.profitTarget = profitTarget
        self.lossLimit = lossLimit
        self.bankrollFloor = bankrollFloor
    }

    /// Whether the run must stop BEFORE dropping the next ball (§4, §11):
    /// finished the count, hit a configured limit, or can't fund the wager.
    public func shouldStop(ballsDropped: Int, sessionNet: Int, bankroll: Int, practiceBankroll: Bool) -> Bool {
        if ballsDropped >= ballCount { return true }
        if let target = profitTarget, sessionNet >= target { return true }
        if let limit = lossLimit, sessionNet <= -limit { return true }
        if !practiceBankroll {
            if let floor = bankrollFloor, bankroll < floor { return true }
            if bankroll < wagerPerBall { return true }
        }
        return false
    }
}
