import Foundation
import SwiftUI
import RiverKit

/// Renderable state of one seat. Built fresh from the engine after every
/// transition; the UI never mutates poker state (§46).
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
    /// "SB" / "BB" when posting a blind this hand, else nil.
    let blindLabel: String?
    /// Position name relative to the button ("BTN", "CO", …).
    let position: String
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
    var smallBlind: Int
    var bigBlind: Int
    var statusText: String
    var isHandComplete: Bool

    var blindsText: String {
        return "\(smallBlind)/\(bigBlind)"
    }
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

    // MARK: - Published presentation state

    @Published private(set) var table: TableUIState?
    @Published private(set) var heroActions: AvailableActions?
    @Published private(set) var phase: GamePhase = .idle
    @Published private(set) var winnerBanner: String?
    @Published private(set) var heroHandDescription: String?
    @Published private(set) var heroDrawLabels: [String] = []
    @Published var advice: Advice?
    @Published private(set) var adviceLoading = false
    @Published private(set) var lastSeed: UInt64?
    /// Board cards currently revealed (staged one at a time, §9).
    @Published private(set) var visibleBoardCount: Int = 0
    /// True while committed chips animate toward the pot (§22).
    @Published private(set) var chipsSweeping: Bool = false
    /// Seats whose showdown hands have been revealed so far (§23).
    @Published private(set) var revealedShowdownSeats: Set<Int> = []
    /// Remaining decision-timer fraction (1...0), nil when no timer runs.
    @Published private(set) var heroTimerFraction: Double?

    private(set) var session: CashSessionState?
    private var hand: PokerHand?
    private var loopTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var autoDealTask: Task<Void, Never>?
    private var lastActionText: [Int: String] = [:]
    private var winnings: [Int: Int] = [:]
    /// Street commitments as the table should DISPLAY them. The engine resets
    /// its own street counters the instant a betting round closes; this copy
    /// persists until the chip-sweep animation has carried the chips to the
    /// pot, so the closing action's chips are visible while they travel (§47).
    private var displayCommitted: [Int: Int] = [:]

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

    private func pause(_ seconds: Double) async {
        guard seconds > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    // MARK: - Session lifecycle

    var hasSavedSession: Bool {
        guard let saved = store.load(CashSessionState.self, from: PersistenceStore.FileName.session) else { return false }
        return saved.canContinue
    }

    var isTablePresented: Bool {
        return phase != .idle
    }

    func startNewSession(config: SessionConfig) {
        cancelAllTasks()
        session = CashSessionState(config: config, startDate: Date())
        saveSession()
        phase = .playing
        startNextHand()
    }

    func resumeSavedSession() {
        cancelAllTasks()
        guard let saved = store.load(CashSessionState.self, from: PersistenceStore.FileName.session), saved.canContinue else { return }
        session = saved
        phase = .playing
        startNextHand()
    }

    func exitToMenu() {
        cancelAllTasks()
        saveSession()
        hand = nil
        table = nil
        heroActions = nil
        advice = nil
        winnerBanner = nil
        heroTimerFraction = nil
        phase = .idle
    }

    func saveSession() {
        if let session {
            try? store.save(session, as: PersistenceStore.FileName.session)
        }
    }

    private func cancelAllTasks() {
        loopTask?.cancel()
        loopTask = nil
        timerTask?.cancel()
        timerTask = nil
        autoDealTask?.cancel()
        autoDealTask = nil
    }

    // MARK: - Hand lifecycle

    func startNextHand() {
        guard var currentSession = session, currentSession.canContinue else {
            phase = .sessionComplete
            return
        }
        cancelAllTasks()
        winnerBanner = nil
        advice = nil
        lastActionText = [:]
        winnings = [:]
        displayCommitted = [:]
        revealedShowdownSeats = []
        visibleBoardCount = 0
        chipsSweeping = false
        heroHandDescription = nil
        heroDrawLabels = []
        let config = currentSession.nextHandConfig()
        session = currentSession
        lastSeed = config.seed
        let newHand = PokerHand(config: config)
        hand = newHand
        for seat in newHand.seats where seat.committedThisStreet > 0 {
            displayCommitted[seat.seatIndex] = seat.committedThisStreet
        }
        phase = .playing
        publish()
        sounds.play(.cardDeal)
        haptics.play(.cardDeal)
        loopTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    private func runLoop() async {
        guard let hand, let session else { return }
        while !hand.isComplete && !Task.isCancelled {
            guard let seat = hand.actionOn else { break }
            if seat == heroSeatIndex {
                presentHeroTurn()
                return // resumed by submitHeroAction
            }
            guard let profile = session.botProfile(forSeat: seat) else { break }
            let decisionTask = Task.detached(priority: .userInitiated) { [hand] in
                return BotDecider.decide(hand: hand, seat: seat, profile: profile)
            }
            await pause(settings.speed.botDelay)
            guard let decision = await decisionTask.value, !Task.isCancelled else { break }
            do {
                try hand.apply(decision.action, by: seat, annotation: decision.annotation)
            } catch {
                assertionFailure("bot submitted illegal action: \(error)")
                break
            }
            noteAction(seat: seat, action: decision.action)
            publish()
            await animateStreetTransitionIfNeeded()
        }
        if hand.isComplete && !Task.isCancelled {
            await finishHand()
        }
    }

    /// The hero's turn (§15): expose legal actions, compute glance info,
    /// double haptic pulse, optional decision timer.
    private func presentHeroTurn() {
        guard let hand else { return }
        heroActions = hand.availableActions(for: heroSeatIndex)
        updateHeroGlanceInfo()
        publish()
        haptics.play(.yourTurn)
        startHeroTimerIfEnabled()
    }

    func submitHeroAction(_ action: PlayerAction) {
        guard let hand, hand.actionOn == heroSeatIndex else { return }
        timerTask?.cancel()
        timerTask = nil
        heroTimerFraction = nil
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
        heroDrawLabels = []
        noteAction(seat: heroSeatIndex, action: action)
        haptics.play(action.kind == .raise || action.kind == .bet ? .raise : .actionConfirm)
        publish()
        loopTask = Task { [weak self] in
            await self?.postHeroActionLoop()
        }
    }

    private func postHeroActionLoop() async {
        await animateStreetTransitionIfNeeded()
        await runLoop()
    }

    // MARK: - Animation sequencing (§47)

    /// When the engine advanced past a street boundary: sweep committed chips
    /// into the pot, then reveal new board cards one at a time.
    private func animateStreetTransitionIfNeeded() async {
        guard let hand else { return }
        guard hand.board.count > visibleBoardCount else { return }
        let scale = settings.speed.motionScale

        // 1) Chips sweep to the pot.
        await sweepChipsToPot(scale: scale)

        // 2) Board cards land one at a time; all-in runouts breathe slower.
        let runout = !hand.seats.contains { $0.canAct && !$0.hasFolded } || hand.isComplete
        let perCard = runout ? max(settings.speed.dealPause, settings.speed.showdownPause * 0.5) : settings.speed.dealPause
        while visibleBoardCount < hand.board.count && !Task.isCancelled {
            visibleBoardCount += 1
            sounds.play(.cardDeal)
            haptics.play(.cardDeal)
            publish()
            await pause(perCard)
        }
    }

    /// Animates displayed street chips into the pot, then clears them.
    private func sweepChipsToPot(scale: Double) async {
        guard displayCommitted.values.contains(where: { $0 > 0 }) else {
            lastActionText = [:]
            publish()
            return
        }
        withAnimation(.easeIn(duration: Theme.Motion.chip)) {
            chipsSweeping = true
        }
        await pause(Theme.Motion.chip * scale + 0.05)
        chipsSweeping = false
        displayCommitted = [:]
        lastActionText = [:]
        publish()
    }

    /// Showdown sequence (§23): reveal in order, describe, distribute, banner.
    private func finishHand() async {
        guard let hand, var currentSession = session else { return }
        await animateStreetTransitionIfNeeded()

        // Sweep any final-street chips.
        await sweepChipsToPot(scale: settings.speed.motionScale)

        // Reveal showdown hands one seat at a time, in engine order.
        let showdownSeats = hand.events.compactMap { event -> Int? in
            if case .showedHand(let seat, _, _) = event { return seat }
            return nil
        }
        for seat in showdownSeats where !Task.isCancelled {
            revealedShowdownSeats.insert(seat)
            sounds.play(.cardDeal)
            publish()
            await pause(settings.speed.showdownPause * 0.55)
        }

        // Winners and pot distribution.
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
        publish()

        // Persist: session state and complete hand history.
        let history = HandHistory(date: Date(), heroSeat: heroSeatIndex, playerNames: names, hand: hand)
        store.appendHistory(history)
        currentSession.complete(hand: hand)
        session = currentSession
        saveSession()
        publish()
        phase = currentSession.canContinue ? .handComplete : .sessionComplete

        // Optional auto-deal (§25).
        if phase == .handComplete, let delay = settings.autoDeal.delay {
            autoDealTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                if self.phase == .handComplete {
                    self.startNextHand()
                }
            }
        }
    }

    /// Reads amounts from the freshly appended action event, which records
    /// pre-street-reset values, and updates labels, sounds and chip display.
    private func noteAction(seat: Int, action: PlayerAction) {
        guard let hand else { return }
        var added = 0
        var toTotal = 0
        var wasAllIn = false
        for event in hand.events.reversed() {
            if case .action(let eventSeat, _, _, let eventAdded, let eventTotal, let eventAllIn) = event, eventSeat == seat {
                added = eventAdded
                toTotal = eventTotal
                wasAllIn = eventAllIn
                break
            }
        }
        if toTotal > 0 {
            displayCommitted[seat] = toTotal
        }
        switch action.kind {
        case .fold:
            lastActionText[seat] = "Folds"
            sounds.play(.fold)
        case .check:
            lastActionText[seat] = "Checks"
            sounds.play(.check)
        case .call:
            lastActionText[seat] = "Calls \(added)"
            sounds.play(.chipBet)
        case .bet:
            lastActionText[seat] = "Bets \(toTotal)"
            sounds.play(.chipBet)
        case .raise:
            lastActionText[seat] = "Raises to \(toTotal)"
            sounds.play(.chipBet)
        }
        if wasAllIn {
            lastActionText[seat] = "All-in \(toTotal)"
            sounds.play(.allIn)
            haptics.play(.allIn)
        }
    }

    // MARK: - Decision timer (§24)

    private func startHeroTimerIfEnabled() {
        timerTask?.cancel()
        heroTimerFraction = nil
        guard let total = settings.decisionTimer.seconds else { return }
        heroTimerFraction = 1
        timerTask = Task { [weak self] in
            var remaining = total
            var warned = false
            while remaining > 0 && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                remaining -= 0.1
                guard let self, !Task.isCancelled else { return }
                self.heroTimerFraction = max(0, remaining / total)
                if !warned && remaining / total < 0.25 {
                    warned = true
                    self.haptics.play(.warning)
                }
            }
            guard let self, !Task.isCancelled else { return }
            self.heroTimerFraction = nil
            // Expiry: check when free, otherwise fold.
            if let actions = self.heroActions {
                self.submitHeroAction(actions.canCheck ? .check : .fold)
            }
        }
    }

    // MARK: - Assistance (§17)

    private func updateHeroGlanceInfo() {
        guard let hand else { return }
        let currentSettings = settings
        heroHandDescription = nil
        heroDrawLabels = []
        guard currentSettings.showHandStrength else { return }
        let hero = hand.seats[heroSeatIndex]
        if hand.board.count >= 3 {
            heroHandDescription = HandEvaluator.evaluate(hole: hero.holeCards, board: hand.board).readableDescription
            let draws = EquityEstimator.detectDraws(hole: hero.holeCards, board: hand.board)
            var labels: [String] = []
            if draws.flushDraw { labels.append("Flush draw") }
            if draws.openEndedStraightDraw { labels.append("Open-ended") }
            else if draws.gutshotStraightDraw { labels.append("Gutshot") }
            heroDrawLabels = labels
        } else {
            heroHandDescription = PreflopHands.label(for: hero.holeCards)
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
                if self.hand === hand && hand.actionOn == heroSeatIndex {
                    self.advice = result
                }
                self.adviceLoading = false
            }
        }
    }

    /// Reason to confirm a fold under Protect Strong Hands (§12), or nil.
    func foldProtectionReason() -> String? {
        guard settings.protectStrongHands, let hand, let actions = heroActions else { return nil }
        if actions.canCheck {
            return "Checking is free — you don't need to fold."
        }
        let hero = hand.seats[heroSeatIndex]
        if hand.board.count >= 3 {
            let value = HandEvaluator.evaluate(hole: hero.holeCards, board: hand.board)
            if value.category.rawValue >= HandCategory.twoPair.rawValue {
                return "You hold \(value.readableDescription.lowercased())."
            }
        } else if PreflopHands.chenScore(for: hero.holeCards) >= 12 {
            return "You hold \(PreflopHands.label(for: hero.holeCards)) — a premium hand."
        }
        return nil
    }

    // MARK: - Table info providers

    func historySections() -> [ActionHistoryBuilder.HistorySection] {
        guard let hand, let session else { return [] }
        return ActionHistoryBuilder.sections(events: hand.events, names: session.playerNames, heroSeat: heroSeatIndex)
    }

    func opponentRead(seat: Int) -> OpponentRead? {
        guard let session, let profile = session.botProfile(forSeat: seat) else { return nil }
        let histories = Array(store.loadHistories().suffix(session.handsPlayed))
        let stats = SessionStats.compute(histories: histories, seat: seat)
        return OpponentRead(
            id: seat,
            name: profile.name,
            symbolName: profile.symbolName,
            archetypeName: "\(profile.archetype.displayName) · \(profile.difficulty.displayName)",
            note: profile.note,
            handsObserved: stats.handsPlayed,
            vpipPercent: stats.vpipPercent,
            pfrPercent: stats.pfrPercent,
            showdownsSeen: stats.showdownsSeen
        )
    }

    func potBreakdown() -> (entries: [PotBreakdownEntry], total: Int)? {
        guard let hand, let session else { return nil }
        let committed = hand.seats.map { $0.committedTotal }
        let live = Set(hand.liveSeatIndices)
        guard !live.isEmpty else { return nil }
        let result = PotBuilder.build(committed: committed, liveSeats: live)
        let names = session.playerNames
        var entries: [PotBreakdownEntry] = []
        for (index, pot) in result.pots.enumerated() {
            entries.append(PotBreakdownEntry(
                id: index,
                title: index == 0 ? "Main pot" : "Side pot \(index)",
                amount: pot.amount,
                eligibleNames: pot.eligibleSeats.map { seat in
                    seat == heroSeatIndex ? "You" : (names.indices.contains(seat) ? names[seat] : "Seat \(seat + 1)")
                }
            ))
        }
        return (entries, hand.pot)
    }

    /// More than one pot layer (or an all-in) makes the pot worth inspecting.
    var potIsInspectable: Bool {
        guard let hand else { return false }
        if hand.seats.contains(where: { $0.isAllIn }) { return true }
        return Set(hand.seats.filter { $0.isLive && $0.committedTotal > 0 }.map { $0.committedTotal }).count > 1
    }

    // MARK: - Publishing (§46)

    private func positionName(offset: Int, count: Int) -> String {
        if count == 2 {
            return offset == 0 ? "BTN" : "BB"
        }
        switch offset {
        case 0: return "BTN"
        case 1: return "SB"
        case 2: return "BB"
        default:
            let fromButton = count - offset
            if fromButton == 1 { return "CO" }
            if fromButton == 2 && count >= 5 { return "HJ" }
            return "UTG"
        }
    }

    private func publish() {
        guard let hand, let session else {
            table = nil
            return
        }
        let names = session.playerNames
        let currentSettings = settings
        let sbSeat = hand.smallBlindSeat
        let bbSeat = hand.bigBlindSeat
        let seatCount = hand.seats.count
        var seatStates: [SeatUIState] = []
        for seat in hand.seats {
            let index = seat.seatIndex
            let isHero = index == heroSeatIndex
            let reveal = isHero
                || revealedShowdownSeats.contains(index)
                || (hand.isComplete && currentSettings.revealFoldedBotCards && !seat.holeCards.isEmpty)
            let profile = session.botProfile(forSeat: index)
            let offset = ((index - hand.config.buttonIndex) % seatCount + seatCount) % seatCount
            var blindLabel: String? = nil
            if index == sbSeat && index != hand.config.buttonIndex { blindLabel = "SB" }
            if index == bbSeat { blindLabel = "BB" }
            seatStates.append(SeatUIState(
                id: index,
                name: isHero ? "You" : (names.indices.contains(index) ? names[index] : "Seat \(index + 1)"),
                symbolName: isHero ? "person.fill" : (profile?.symbolName ?? "person"),
                stack: seat.stack,
                committed: displayCommitted[index] ?? 0,
                hasFolded: seat.hasFolded && seat.isParticipating,
                isAllIn: seat.isAllIn,
                isActing: hand.actionOn == index,
                isButton: hand.config.buttonIndex == index,
                blindLabel: blindLabel,
                position: positionName(offset: offset, count: seatCount),
                isHero: isHero,
                visibleCards: reveal ? seat.holeCards : nil,
                hasCards: !seat.holeCards.isEmpty && !seat.hasFolded,
                lastAction: lastActionText[index],
                netWon: winnings[index] ?? 0
            ))
        }
        table = TableUIState(
            seats: seatStates,
            board: hand.board,
            pot: hand.pot,
            street: hand.street,
            handNumber: hand.config.handNumber,
            handsTarget: session.config.handsTarget,
            smallBlind: session.config.smallBlind,
            bigBlind: session.config.bigBlind,
            statusText: hand.isComplete ? "Hand complete" : hand.street.name,
            isHandComplete: hand.isComplete
        )
    }

    // MARK: - Results helpers

    var sessionStats: SessionStats? {
        guard let session else { return nil }
        let histories = store.loadHistories().suffix(session.handsPlayed)
        return SessionStats.compute(histories: Array(histories), seat: heroSeatIndex)
    }

    func endSessionAndClear() {
        cancelAllTasks()
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

// MARK: - Preview support

extension GameViewModel {
    /// Injects deterministic mock state so previews and design work never
    /// depend on a live engine (§48).
    func applyPreviewState(table previewTable: TableUIState, heroActions previewActions: AvailableActions?, boardVisible: Int) {
        self.table = previewTable
        self.heroActions = previewActions
        self.visibleBoardCount = boardVisible
        self.phase = .playing
    }
}
