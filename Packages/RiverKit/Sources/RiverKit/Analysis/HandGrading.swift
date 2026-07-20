import Foundation

/// Result-independent decision grades (§33–34).
public enum DecisionGrade: String, Codable, Hashable, Sendable, CaseIterable {
    case blunder
    case significantMistake
    case inaccuracy
    case reasonable
    case strong
    case excellent
    case mixed

    public var displayName: String {
        switch self {
        case .blunder: return "Blunder"
        case .significantMistake: return "Significant mistake"
        case .inaccuracy: return "Inaccuracy"
        case .reasonable: return "Reasonable"
        case .strong: return "Strong"
        case .excellent: return "Excellent"
        case .mixed: return "Mixed"
        }
    }
}

/// Honest recommendation confidence (§35).
public enum AnalysisConfidence: String, Codable, Hashable, Sendable {
    case low
    case moderate
    case high

    public var displayName: String {
        switch self {
        case .low: return "Low"
        case .moderate: return "Moderate"
        case .high: return "High"
        }
    }
}

/// One evaluated candidate stored with the analysis (§32).
public struct CandidateEvaluation: Codable, Hashable, Sendable {
    public let label: String
    public let kind: ActionKind
    public let toAmount: Int
    /// Approximate EV in big blinds relative to folding now. Marked
    /// approximate everywhere it is shown (§19).
    public let evBB: Double
}

/// Reproducible post-hand analysis of one human decision (§32). Stored inside
/// the hand history; never depends on mutable live AI state.
public struct DecisionAnalysis: Codable, Hashable, Sendable {
    public static let analysisVersion = 1

    /// Index into the hand history's `decisions` array.
    public let decisionIndex: Int
    public let street: Street
    public let potBefore: Int
    public let toCall: Int
    public let equity: Double
    public let requiredEquity: Double
    public let candidates: [CandidateEvaluation]
    public let recommendedLabel: String
    public let chosenLabel: String
    /// Estimated EV lost by the chosen action versus the best candidate, in
    /// big blinds. 0 when the choice was best.
    public let evLossBB: Double
    public let grade: DecisionGrade
    public let confidence: AnalysisConfidence
    public let explanation: String
    /// Concept tags powering leak detection and drills later (§37).
    public let tags: [String]
    public let strategyVersion: Int
    public let analysisVersion: Int
}

/// Grading thresholds in big blinds (§34). Configurable in one place; low
/// confidence softens severity rather than fabricating certainty.
enum GradingThresholds {
    static let excellent = 0.15
    static let strong = 0.4
    static let reasonable = 1.0
    static let inaccuracy = 2.5
    static let significant = 6.0
    /// Top candidates within this band make a decision "Mixed".
    static let mixedBand = 0.3

    static func grade(evLossBB: Double, isCloseDecision: Bool, confidence: AnalysisConfidence) -> DecisionGrade {
        if isCloseDecision && evLossBB <= reasonable {
            return .mixed
        }
        var grade: DecisionGrade
        switch evLossBB {
        case ..<excellent: grade = .excellent
        case ..<strong: grade = .strong
        case ..<reasonable: grade = .reasonable
        case ..<inaccuracy: grade = .inaccuracy
        case ..<significant: grade = .significantMistake
        default: grade = .blunder
        }
        // Low-confidence models must not scream "blunder" (§34).
        if confidence == .low {
            if grade == .blunder { grade = .significantMistake }
            if grade == .significantMistake { grade = .inaccuracy }
            if grade == .inaccuracy && evLossBB < inaccuracy { grade = .reasonable }
        }
        return grade
    }
}
