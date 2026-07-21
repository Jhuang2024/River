import Foundation

/// Deterministic offline daily challenge (§37): seeded by calendar date and
/// content version — same day, same challenge, no server, no streak pressure.
public struct DailyChallenge: Sendable {
    public let dateKey: String
    public let seed: UInt64
    public let title: String
    public let questions: [DrillQuestion]

    /// "YYYY-MM-DD" in the user's calendar.
    public static func dateKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    /// FNV-1a over the date key and versions: stable across launches.
    public static func seed(forDateKey key: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in "\(key)|content\(Lesson.contentVersion)|analysis\(DecisionAnalysis.analysisVersion)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    /// Builds the day's five-part mixed challenge.
    public static func build(for date: Date, calendar: Calendar = .current) -> DailyChallenge {
        let key = dateKey(for: date, calendar: calendar)
        let daySeed = seed(forDateKey: key)
        var questions: [DrillQuestion] = []
        var rng = SeededRNG(seed: daySeed)

        // A rotating mix keeps days distinct but balanced.
        let plans: [DrillPlan] = [
            .potOdds(count: 1),
            .handReading(count: 1),
            .preflop(count: 1, scenario: rng.double01() < 0.5 ? .facingOpen : .blindDefense, stackBB: 100),
            .pushFold(count: 1, stackBB: 6 + rng.int(upperBound: 6)),
            .postflop(count: 1, street: rng.double01() < 0.5 ? .turn : .river)
        ]
        for (index, plan) in plans.enumerated() {
            let generated = DrillEngine.questions(
                for: plan,
                seed: daySeed &+ UInt64(index &* 977),
                conceptTag: "daily"
            )
            if let first = generated.first {
                questions.append(first)
            }
        }
        return DailyChallenge(dateKey: key, seed: daySeed, title: "Daily Challenge", questions: questions)
    }
}

/// Endless mixed trainer (§38): samples weak and due concepts first, then the
/// full mix; deterministic within a run seed, varied between runs.
public enum EndlessTrainer {

    public enum Filter: String, CaseIterable, Sendable {
        case fullMix
        case preflopOnly
        case postflopOnly
        case riverOnly
        case mathOnly

        public var displayName: String {
            switch self {
            case .fullMix: return "Full mix"
            case .preflopOnly: return "Preflop"
            case .postflopOnly: return "Postflop"
            case .riverOnly: return "River"
            case .mathOnly: return "Mathematics"
            }
        }
    }

    /// Produces the next batch of questions for the filter.
    public static func batch(filter: Filter, seed: UInt64, count: Int = 5, weakConcepts: [String] = []) -> [DrillQuestion] {
        var questions: [DrillQuestion] = []
        var rng = SeededRNG(seed: seed)
        var index = 0
        while questions.count < count && index < count * 6 {
            index += 1
            let plan: DrillPlan
            switch filter {
            case .preflopOnly:
                let kinds: [PreflopScenarioKind] = [.unopened, .facingOpen, .blindDefense, .facingThreeBet]
                plan = .preflop(count: 1, scenario: kinds[rng.int(upperBound: kinds.count)], stackBB: rng.double01() < 0.25 ? 10 : 100)
            case .postflopOnly:
                let streets: [Street] = [.flop, .turn, .river]
                plan = .postflop(count: 1, street: streets[rng.int(upperBound: streets.count)])
            case .riverOnly:
                plan = .postflop(count: 1, street: .river)
            case .mathOnly:
                let mathPlans: [DrillPlan] = [.potOdds(count: 1), .outs(count: 1), .combos(count: 1)]
                plan = mathPlans[rng.int(upperBound: mathPlans.count)]
            case .fullMix:
                // Weak concepts bias the mix toward decisions (§38).
                let roll = rng.double01()
                if roll < 0.30 {
                    let kinds: [PreflopScenarioKind] = [.unopened, .facingOpen, .blindDefense]
                    plan = .preflop(count: 1, scenario: kinds[rng.int(upperBound: kinds.count)], stackBB: 100)
                } else if roll < 0.55 {
                    let streets: [Street] = [.flop, .turn, .river]
                    plan = .postflop(count: 1, street: streets[rng.int(upperBound: streets.count)])
                } else if roll < 0.7 {
                    plan = .pushFold(count: 1, stackBB: 5 + rng.int(upperBound: 8))
                } else if roll < 0.85 {
                    plan = .potOdds(count: 1)
                } else {
                    plan = weakConcepts.contains("hand rankings") ? .handReading(count: 1) : .combos(count: 1)
                }
            }
            let generated = DrillEngine.questions(for: plan, seed: seed &+ UInt64(index &* 5_501), conceptTag: "endless")
            if let first = generated.first {
                questions.append(first)
            }
        }
        return questions
    }
}
