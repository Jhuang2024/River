import Foundation
import SwiftUI
import RiverKit

/// Renderable state of one seat. Built fresh from the engine after every
/// event; the UI never mutates poker state.
struct SeatUIState: Identifiable, Equatable {
    let id: Int
    let name: String
    let symbolName: String
    let stack: Int
    let committed: Int
    let hasFolded: Bool
    let isAllIn: Bool
    let isActing: Bool
    let isButton: Bool
    let isHero: Bool
    /// nil = face-down (or no cards); non-nil = visible cards.
    let visibleCards: [Card]?
    let hasCards: Bool
    let lastAction: String?
    let netWon: Int
}

/// Renderable state of the whole table.
struct TableUIState: Equatable {
    var seats: [SeatUIState]
    var board: [Card]
    var pot: Int
    var street: Street
    var handNumber: Int
    var handsTarget: Int
    var blindsText: String
    var statusText: String
}

/// What the session flow is currently doing.
enum GamePhase: Equatable {
    case idle
    case playing
    case handComplete
    case sessionComplete
}

@MainActor
final class GameViewModel: ObservableObject {

    @Published private(set) var table: TableUIState?
    @Published private(set) var heroActions: AvailableActions?
    @Published private(set) var phase: GamePhase = .idle
    @Published private(set) var winnerBanner: String?
    @Published private(set) var heroHandDescription: String?
    @Published private(set) var potOddsText: String?
    @Published var advice: Advice?
    @Published private(set) var adviceLoading = false
    @Published private(set) var lastSeed: UInt64?

    private(set) var session: CashSessionState?
    private var hand: PokerHand?
    private var loopTask: Task<Void, Never>?
    private var lastActionText: [Int: String] = [:]
    private var winnings: [Int: Int] = [:]

    let store: PersistenceStore
    let sounds: SoundPlayer
    let haptics: HapticsPlayer
    var settingsProvider: () -> AppSettings

    init(store: PersistenceStore, sounds: SoundPlayer, haptics: HapticsPlayer, settingsProvider: @escaping () -> AppSettings) {
        self.store = store
        self.sounds = sounds
        self.haptics = haptics
        self.settingsProvider = settingsProvider
    }

    private var settings: AppSettings {
        return settingsProvider()
    }

    // MARK: - Session lifecycle

    var hasSavedSession: Bool {
        guard let saved = store.load(CashSessionState.self, from: PersistenceStore.FileName.session) else { return false }
        return saved.canContinue
    }

    func startNewSession(config: SessionConfig) {
        cancelLoop()
        session = CashSessionState(config: config, startDate: Date())
        saveSession()
        phase = .playing
        startNextHand()
    }

    func resumeSavedSession() {
        cancelLoop()
        guard let saved = store.load(CashSessionState.self, from: PersistenceStore.FileName.session), saved.canContinue else { return }
        session = saved
        phase = .playing
        startNextHand()
    }

    func exitToMenu() {
        cancelLoop()
        saveSession()
        hand = nil
        table = nil
        heroActions = nil
        advice = nil
        winnerBanner = nil
        phase = .idle
    }

    func saveSession() {
        if let session {
            try? store.save(session, as: PersistenceStore.FileName.session)
        }
    }

    // MARK: - Hand lifecycle

    func startNextHand() {
        guard var currentSession = session, currentSession.canContinue else {
            phase = .sessionComplete
            return
        }
        cancelLoop()
        winnerBanner = nil
        advice = nil
        lastActionText = [:]
        winnings = [:]
        let config = currentSession.nextHandConfig()
        session = currentSession
        lastSeed = config.seed
        let newHand = PokerHand(config: config)
        hand = newHand
        phase = .playing
        publish()
        sounds.play(.cardDeal)
        haptics.play(.cardDeal)
        loopTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    private func cancelLoop() {
        loopTask?.cancel()
        loopTask = nil
    }

    private func runLoop() async {
        guard let hand, let session else { return }
        while !hand.isComplete && !Task.isCancelled {
            guard let seat = hand.actionOn else { break }
            if seat == heroSeatIndex {
                heroActions = hand.availableActions(for: seat)
                updateHeroAssistance()
                publish()
                return // resumed by submitHeroAction
            }
            guard let profile = session.botProfile(forSeat: seat) else { break }
            let streetBefore = hand.street
            let delay = settings.speed.botDelay
            let decisionTask = Task.detached(priority: .userInitiated) { [hand] in
                return BotDecider.decide(hand: hand, seat: seat, profile: profile)
            }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let decision = await decisionTask.value, !Task.isCancelled else { break }
            do {
                try hand.apply(decision.action, by: seat, annotation: decision.annotation)
            } catch {
                assertionFailure("bot submitted illegal action: \(error)")
                break
            }
            noteAction(seat: seat, action: decision.action)
            publish()
            if hand.street != streetBefore && !hand.isComplete {
                sounds.play(.cardDeal)
                try? await Task.sleep(nanoseconds: UInt64(settings.speed.dealPause * 1_000_000_000))
                publish()
            }
        }
        if hand.isComplete && !Task.isCancelled {
            await finishHand()
        }
    }

    func submitHeroAction(_ action: PlayerAction) {
        guard let hand, hand.actionOn == heroSeatIndex else { return }
        var annotation = DecisionAnnotation()
        if let advice {
            annotation.strengthEstimate = advice.equity
            annotation.advisorKind = advice.kind
        }
        do {
            try hand.apply(action, by: heroSeatIndex, annotation: annotation)
        } catch {
            // The UI only offers legal actions; if something slips through,
            // refresh the choices rather than corrupting state.
            heroActions = hand.availableActions(for: heroSeatIndex)
            return
        }
        heroActions = nil
        advice = nil
        heroHandDescription = nil
        potOddsText = nil
        noteAction(seat: heroSeatIndex, action: action)
        haptics.play(action.kind == .raise || action.kind == .bet ? .raise : .actionConfirm)
        publish()
        loopTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    private func noteAction(seat: Int, action: PlayerAction) {
        switch action.kind {
        case .fold:
            lastActionText[seat] = "Fold"
            sounds.play(.fold)
        case .check:
            lastActionText[seat] = "Check"
            sounds.play(.check)
        case .call:
            lastActionText[seat] = "Call"
            sounds.play(.chipBet)
        case .bet:
            lastActionText[seat] = "Bet \(action.toAmount)"
            sounds.play(.chipBet)
        case .raise:
            lastActionText[seat] = "Raise \(action.toAmount)"
            sounds.play(.chipBet)
        }
        if let hand, hand.seats[seat].isAllIn {
            lastActionText[seat] = "All-in"
            sounds.play(.allIn)
            if seat == heroSeatIndex {
                haptics.play(.allIn)
            }
        }
    }

    private func finishHand() async {
        guard let hand, var currentSession = session else { return }
        // Collect winner info for the banner and seat badges.
        var totalWon: [Int: Int] = [:]
        for event in hand.events {
            switch event {
            case .wonPot(let seat, let amount, _, _):
                totalWon[seat, default: 0] += amount
            case .wonWithoutShowdown(let seat, let amount):
                totalWon[seat, default: 0] += amount
            default:
                break
            }
        }
        winnings = totalWon
        let names = currentSession.playerNames
        if hand.events.contains(where: { if case .showedHand = $0 { return true } else { return false } }) {
            try? await Task.sleep(nanoseconds: UInt64(settings.speed.showdownPause * 1_000_000_000))
        }
        publish()

        let heroNet = hand.seats[heroSeatIndex].stack - hand.seats[heroSeatIndex].startingStack
        let bigPot = hand.finalPots.reduce(0) { $0 + $1.amount } >= currentSession.config.bigBlind * 30
        if heroNet > 0 {
            sounds.play(.win)
            if bigPot { haptics.play(.bigWin) }
            winnerBanner = "You win \(totalWon[heroSeatIndex] ?? heroNet)"
        } else if let bestWinner = totalWon.max(by: { $0.value < $1.value }) {
            if heroNet < 0 {
                sounds.play(.lose)
                if bigPot { haptics.play(.bigLoss) }
            }
            let name = names.indices.contains(bestWinner.key) ? names[bestWinner.key] : "Seat \(bestWinner.key + 1)"
            winnerBanner = "\(name) wins \(bestWinner.value)"
        }

        // Persist: session state and complete hand history.
        let history = HandHistory(date: Date(), heroSeat: heroSeatIndex, playerNames: names, hand: hand)
        store.appendHistory(history)
        currentSession.complete(hand: hand)
        session = currentSession
        saveSession()
        publish()
        phase = currentSession.canContinue ? .handComplete : .sessionComplete
    }

    // MARK: - Assistance

    private func updateHeroAssistance() {
        guard let hand else { return }
        let currentSettings = settings
        heroHandDescription = nil
        potOddsText = nil
        if currentSettings.showHandStrength {
            let hero = hand.seats[heroSeatIndex]
            if hand.board.count >= 3 {
                heroHandDescription = HandEvaluator.evaluate(hole: hero.holeCards, board: hand.board).readableDescription
            } else {
                heroHandDescription = PreflopHands.label(for: hero.holeCards)
            }
        }
        if currentSettings.showPotOdds, let actions = heroActions, actions.callCost > 0 {
            let odds = Double(actions.callCost) / Double(hand.pot + actions.callCost) * 100
            potOddsText = "Call \(actions.callCost) into \(hand.pot + actions.callCost) — need \(Int(odds.rounded()))%"
        }
    }

    func requestAdvice() {
        guard settings.allowRecommendations, let hand, hand.actionOn == heroSeatIndex, !adviceLoading else { return }
        adviceLoading = true
        Task { [weak self, hand] in
            let result = await Task.detached(priority: .userInitiated) {
                return Advisor.advise(hand: hand, seat: heroSeatIndex)
            }.value
            await MainActor.run {
                guard let self else { return }
                // Only show if it is still the hero's turn on the same hand.
                if self.hand === hand && hand.actionOn == heroSeatIndex {
                    self.advice = result
                }
                self.adviceLoading = false
            }
        }
    }

    // MARK: - Publishing

    private func publish() {
        guard let hand, let session else {
            table = nil
            return
        }
        let names = session.playerNames
        let shownSeats = Set(hand.events.compactMap { event -> Int? in
            if case .showedHand(let seat, _, _) = event { return seat }
            return nil
        })
        var seatStates: [SeatUIState] = []
        for seat in hand.seats {
            let index = seat.seatIndex
            let isHero = index == heroSeatIndex
            let reveal = isHero || shownSeats.contains(index) || (hand.isComplete && settings.revealFoldedBotCards && !seat.holeCards.isEmpty)
            let profile = session.botProfile(forSeat: index)
            seatStates.append(SeatUIState(
                id: index,
                name: names.indices.contains(index) ? names[index] : "Seat \(index + 1)",
                symbolName: isHero ? "person.fill" : (profile?.symbolName ?? "person"),
                stack: seat.stack,
                committed: seat.committedThisStreet,
                hasFolded: seat.hasFolded && seat.isParticipating,
                isAllIn: seat.isAllIn,
                isActing: hand.actionOn == index,
                isButton: hand.config.buttonIndex == index,
                isHero: isHero,
                visibleCards: reveal ? seat.holeCards : nil,
                hasCards: !seat.holeCards.isEmpty && !seat.hasFolded,
                lastAction: lastActionText[index],
                netWon: winnings[index] ?? 0
            ))
        }
        let target = session.config.handsTarget
        table = TableUIState(
            seats: seatStates,
            board: hand.board,
            pot: hand.pot,
            street: hand.street,
            handNumber: hand.config.handNumber,
            handsTarget: target,
            blindsText: "\(session.config.smallBlind)/\(session.config.bigBlind)",
            statusText: hand.isComplete ? "Hand complete" : hand.street.name
        )
    }

    // MARK: - Results helpers

    var sessionStats: SessionStats? {
        guard let session else { return nil }
        let histories = store.loadHistories().suffix(session.handsPlayed)
        return SessionStats.compute(histories: Array(histories), seat: heroSeatIndex)
    }

    func endSessionAndClear() {
        cancelLoop()
        if var currentSession = session {
            currentSession.isFinished = true
            session = currentSession
        }
        store.delete(PersistenceStore.FileName.session)
        session = nil
        hand = nil
        table = nil
        phase = .idle
    }
}
