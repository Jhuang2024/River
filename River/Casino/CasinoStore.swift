import Foundation
import SwiftUI
import RiverKit

/// Blackjack assistance configuration (§6): Guided / Hint / Pure presets
/// plus individual toggles. Counting displays are OFF by default.
struct BlackjackAssistOptions: Codable, Equatable {
    enum Mode: String, Codable, CaseIterable, Identifiable {
        case guided, hint, pure
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .guided: return "Guided"
            case .hint: return "Hint"
            case .pure: return "Pure"
            }
        }
    }

    var mode: Mode = .guided
    var showHandTotal: Bool = true
    var showDealerLogic: Bool = true
    var recommendAction: Bool = true
    var showStrategyChart: Bool = false
    var explainMistakesAfterHand: Bool = true
    var showRunningCount: Bool = false
    var showTrueCount: Bool = false

    mutating func applyPreset(_ preset: Mode) {
        mode = preset
        switch preset {
        case .guided:
            showHandTotal = true
            showDealerLogic = true
            recommendAction = true
            explainMistakesAfterHand = true
        case .hint:
            showHandTotal = true
            showDealerLogic = false
            recommendAction = false // on request only
            explainMistakesAfterHand = true
        case .pure:
            showHandTotal = false
            showDealerLogic = false
            recommendAction = false
            explainMistakesAfterHand = false
        }
    }
}

/// Casino-floor preferences, persisted with resilient decoding like the main
/// settings (§2, §5, §11).
struct CasinoSettings: Codable, Equatable {
    var bankrollMode: BankrollMode = .career
    /// Independent Practice Bankrolls (§2): each game keeps its own chips.
    var independentBankrolls: Bool = false
    var safeguards: SessionSafeguards = SessionSafeguards()
    var blackjackRules: BlackjackRules = .standard
    var blackjackAssist: BlackjackAssistOptions = BlackjackAssistOptions()
    var rouletteWheel: RouletteWheel = .european
    var plinkoRows: PlinkoRows = .twelve
    var plinkoRisk: PlinkoRisk = .medium
    var chipDenomination: Int = 10
}

/// Owns bankrolls, casino history and settings (§2, §12). All fictional, all
/// local, exact integer accounting throughout.
@MainActor
final class CasinoStore: ObservableObject {
    private enum File {
        static let settings = "casino-settings"
        static let bankrolls = "casino-bankrolls"
        static let history = "casino-history"
        static let sessions = "casino-session-meta"
    }

    static let historyLimit = 600

    @Published var settings: CasinoSettings {
        didSet {
            try? store.save(settings, as: File.settings)
            syncBankrollModes()
        }
    }
    @Published private(set) var bankrolls: [String: CasinoBankrollState]
    @Published private(set) var records: [CasinoRoundRecord]
    /// Rounds played this sitting per game (safeguards, §11).
    @Published private(set) var sessionRounds: [String: Int] = [:]
    @Published private(set) var sessionNets: [String: Int] = [:]
    /// Extra achievement evidence that records alone can't hold.
    @Published private(set) var meta: CasinoMeta

    struct CasinoMeta: Codable, Equatable {
        var plinkoSessionLengths: [Int] = []
        var plinkoSessionCloseness: [PlinkoSessionCloseness] = []
        var fullShoeCountedCorrectly: Bool = false
        var longestCorrectDecisionRun: Int = 0
        var currentCorrectDecisionRun: Int = 0

        struct PlinkoSessionCloseness: Codable, Equatable {
            var balls: Int
            var drift: Double
        }
    }

    let store: PersistenceStore

    init(store: PersistenceStore) {
        self.store = store
        self.settings = store.load(CasinoSettings.self, from: File.settings) ?? CasinoSettings()
        self.bankrolls = store.load([String: CasinoBankrollState].self, from: File.bankrolls) ?? [:]
        self.records = store.load([CasinoRoundRecord].self, from: File.history) ?? []
        self.meta = store.load(CasinoMeta.self, from: File.sessions) ?? CasinoMeta()
        syncBankrollModes()
    }

    private func persist() {
        try? store.save(bankrolls, as: File.bankrolls)
        try? store.save(records, as: File.history)
        try? store.save(meta, as: File.sessions)
    }

    // MARK: - Bankrolls (§2)

    private func bankrollKey(for game: CasinoGameKind) -> String {
        return settings.independentBankrolls ? game.rawValue : "shared"
    }

    func bankroll(for game: CasinoGameKind) -> CasinoBankrollState {
        let key = bankrollKey(for: game)
        if let existing = bankrolls[key] { return existing }
        let fresh = CasinoBankrollState(mode: settings.bankrollMode)
        bankrolls[key] = fresh
        persist()
        return fresh
    }

    private func syncBankrollModes() {
        for key in bankrolls.keys where bankrolls[key]?.mode != settings.bankrollMode {
            var state = bankrolls[key]!
            let previous = state.mode
            state.mode = settings.bankrollMode
            // Entering a chip-tracked mode from practice restarts the stake.
            if previous == .practice || state.mode == .session {
                state.chips = CasinoBankrollState.defaultStart
            }
            state.beginSession(stake: CasinoBankrollState.defaultStart)
            bankrolls[key] = state
        }
        persist()
    }

    func canAfford(_ wager: Int, game: CasinoGameKind) -> Bool {
        return bankroll(for: game).canAfford(wager)
    }

    func rebuildCareerBankroll(for game: CasinoGameKind) {
        let key = bankrollKey(for: game)
        var state = bankroll(for: game)
        state.rebuildCareer()
        bankrolls[key] = state
        persist()
    }

    func beginSession(for game: CasinoGameKind) {
        let key = bankrollKey(for: game)
        var state = bankroll(for: game)
        state.beginSession(stake: CasinoBankrollState.defaultStart)
        bankrolls[key] = state
        sessionRounds[game.rawValue] = 0
        sessionNets[game.rawValue] = 0
        persist()
    }

    // MARK: - Recording rounds (§12)

    /// Settles a completed round against the bankroll and stores its record.
    /// Returns the safeguard trigger, if the player's own limit was reached.
    @discardableResult
    func complete(round: CasinoRoundRecord) -> SessionSafeguards.Trigger? {
        let key = bankrollKey(for: round.game)
        var state = bankroll(for: round.game)
        state.settle(staked: round.wagered, returned: round.returned)
        bankrolls[key] = state

        records.append(round)
        if records.count > Self.historyLimit {
            records.removeFirst(records.count - Self.historyLimit)
        }
        let gameKey = round.game.rawValue
        sessionRounds[gameKey, default: 0] += 1
        sessionNets[gameKey, default: 0] += round.net
        persist()
        return settings.safeguards.triggered(
            roundsPlayed: sessionRounds[gameKey] ?? 0,
            sessionNet: sessionNets[gameKey] ?? 0
        )
    }

    func records(for game: CasinoGameKind?) -> [CasinoRoundRecord] {
        guard let game else { return records }
        return records.filter { $0.game == game }
    }

    func stats(for game: CasinoGameKind? = nil) -> CasinoStats {
        return CasinoStats.compute(records: records, game: game)
    }

    /// Most recent completed round per game, for the mode cards (§7).
    func lastRound(for game: CasinoGameKind) -> CasinoRoundRecord? {
        return records.last { $0.game == game }
    }

    // MARK: - Achievement evidence (§10)

    func noteBlackjackDecision(correct: Bool) {
        if correct {
            meta.currentCorrectDecisionRun += 1
            meta.longestCorrectDecisionRun = max(meta.longestCorrectDecisionRun, meta.currentCorrectDecisionRun)
        } else {
            meta.currentCorrectDecisionRun = 0
        }
        persist()
    }

    func notePlinkoSessionEnded(balls: Int, wagered: Int, net: Int) {
        guard balls > 0 else { return }
        meta.plinkoSessionLengths.append(balls)
        if wagered > 0 {
            meta.plinkoSessionCloseness.append(.init(balls: balls, drift: abs(Double(net)) / Double(wagered)))
        }
        if meta.plinkoSessionLengths.count > 50 {
            meta.plinkoSessionLengths.removeFirst(meta.plinkoSessionLengths.count - 50)
        }
        if meta.plinkoSessionCloseness.count > 50 {
            meta.plinkoSessionCloseness.removeFirst(meta.plinkoSessionCloseness.count - 50)
        }
        persist()
    }

    func noteFullShoeCounted() {
        meta.fullShoeCountedCorrectly = true
        persist()
    }

    var unlockedAchievements: Set<String> {
        let evidence = CasinoAchievementLibrary.Evidence(
            records: records,
            plinkoSessionLengths: meta.plinkoSessionLengths,
            plinkoSessionCloseness: meta.plinkoSessionCloseness.map { ($0.balls, $0.drift) },
            fullShoeCountedCorrectly: meta.fullShoeCountedCorrectly,
            longestCorrectDecisionRun: meta.longestCorrectDecisionRun
        )
        return CasinoAchievementLibrary.unlocked(evidence: evidence)
    }

    // MARK: - Seeds (§3)

    /// A fresh round seed. Drawn from system entropy; recorded with the
    /// round so it can be inspected and replayed afterwards.
    func newRoundSeed() -> UInt64 {
        return UITestSupport.seedOverride ?? UInt64.random(in: UInt64.min...UInt64.max)
    }
}
