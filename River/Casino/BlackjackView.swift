import SwiftUI
import RiverKit

/// Drives blackjack rounds against the pure engine (§6). The view model owns
/// the shoe between rounds, persists mid-hand state (§15), settles the
/// bankroll and records history with strategy evaluation.
@MainActor
final class BlackjackViewModel: ObservableObject {
    @Published private(set) var round: BlackjackRound?
    @Published private(set) var shoe: BlackjackShoe
    @Published var bet: Int = 10
    @Published private(set) var lastSettlement: BlackjackSettlement?
    @Published private(set) var mistakes: [String] = []
    @Published var requestedHint: BlackjackStrategy.Recommendation?
    @Published var safeguardNotice: SessionSafeguards.Trigger?
    @Published private(set) var runningCount: Int = 0

    private let casino: CasinoStore
    private static let saveFile = "casino-blackjack-round"

    init(casino: CasinoStore) {
        self.casino = casino
        let rules = casino.settings.blackjackRules
        if let saved = casino.store.load(SavedState.self, from: Self.saveFile) {
            self.shoe = saved.shoe
            self.round = saved.round
            self.runningCount = saved.runningCount
            self.mistakes = saved.mistakes
        } else {
            self.shoe = BlackjackShoe(decks: rules.decks, penetration: rules.penetration,
                                      seed: casino.newRoundSeed())
        }
    }

    private struct SavedState: Codable {
        var shoe: BlackjackShoe
        var round: BlackjackRound?
        var runningCount: Int
        var mistakes: [String]
    }

    private func persist() {
        let state = SavedState(shoe: shoe, round: round, runningCount: runningCount, mistakes: mistakes)
        try? casino.store.save(state, as: Self.saveFile)
    }

    var rules: BlackjackRules { casino.settings.blackjackRules }
    var assist: BlackjackAssistOptions { casino.settings.blackjackAssist }
    var bankroll: CasinoBankrollState { casino.bankroll(for: .blackjack) }

    var trueCount: Int {
        return CountingTrainer.trueCount(running: runningCount, decksRemaining: shoe.decksRemaining)
    }

    /// Cards everyone can see, for the running count.
    private func countVisibleCards() {
        guard let round else { return }
        var visible = round.hands.flatMap { $0.cards }
        if round.dealerHoleRevealed {
            visible += round.dealerCards
        } else if let up = round.dealerUpcard {
            visible.append(up)
        }
        runningCount = CountingTrainer.runningCount(consumedBeforeRound) + CountingTrainer.runningCount(visible)
    }

    /// Cards dealt in earlier rounds of this shoe.
    private var consumedBeforeRound: [BlackjackCard] {
        guard let round else { return Array(shoe.cards.prefix(shoe.dealtCount)) }
        return Array(shoe.cards.prefix(round.fairness.position))
    }

    // MARK: - Round flow

    var canDeal: Bool {
        guard round == nil || round?.phase == .some(.settled) else { return false }
        return casino.canAfford(bet, game: .blackjack) && bet >= rules.betStep
    }

    func deal() {
        guard canDeal else { return }
        if shoe.needsReshuffle {
            shoe = BlackjackShoe(decks: rules.decks, penetration: rules.penetration,
                                 seed: casino.newRoundSeed())
        }
        var newRound = BlackjackRound(rules: rules, shoe: shoe)
        let evenBet = bet - (bet % rules.betStep)
        do {
            try newRound.deal(bet: max(rules.betStep, evenBet))
        } catch {
            return
        }
        mistakes = []
        lastSettlement = nil
        requestedHint = nil
        round = newRound
        countVisibleCards()
        finishIfSettled()
        persist()
    }

    func decideInsurance(take: Bool) {
        guard var current = round else { return }
        // Insurance stake must also be affordable on top of the main bet.
        if take && !casino.canAfford(current.totalStaked + current.hands[0].bet / 2, game: .blackjack) {
            return
        }
        try? current.decideInsurance(take: take)
        round = current
        countVisibleCards()
        finishIfSettled()
        persist()
    }

    /// Extra chips an action needs beyond what's already staked.
    private func additionalCost(of action: BlackjackAction, handIndex: Int) -> Int {
        guard let round, round.hands.indices.contains(handIndex) else { return 0 }
        switch action {
        case .double, .split: return round.hands[handIndex].bet
        default: return 0
        }
    }

    func canApply(_ action: BlackjackAction, handIndex: Int) -> Bool {
        guard let round else { return false }
        guard round.legalActions(handIndex: handIndex).contains(action) else { return false }
        // Insufficient bankroll blocks double/split (§6).
        let cost = additionalCost(of: action, handIndex: handIndex)
        return cost == 0 || casino.canAfford(round.totalStaked + cost, game: .blackjack)
    }

    func apply(_ action: BlackjackAction, handIndex: Int) {
        guard var current = round, canApply(action, handIndex: handIndex) else { return }
        gradeDecision(action, handIndex: handIndex, round: current)
        try? current.apply(action, handIndex: handIndex)
        round = current
        requestedHint = nil
        countVisibleCards()
        finishIfSettled()
        persist()
    }

    private func gradeDecision(_ action: BlackjackAction, handIndex: Int, round: BlackjackRound) {
        guard let up = round.dealerUpcard else { return }
        let legal = round.legalActions(handIndex: handIndex)
        let result = BlackjackStrategy.evaluate(
            taken: action, hand: round.hands[handIndex],
            dealerUpcard: up, rules: rules, legalActions: legal
        )
        casino.noteBlackjackDecision(correct: result.correct)
        if !result.correct {
            let hand = round.hands[handIndex]
            mistakes.append("\(hand.isSoft ? "Soft" : "Hard") \(hand.total) vs \(up.rank.symbol): you chose \(action.displayName.lowercased()); basic strategy \(result.recommended.displayName.lowercased())s.")
        }
    }

    func requestHint() {
        guard let round, case .playerTurn(let index) = round.phase, let up = round.dealerUpcard else { return }
        requestedHint = BlackjackStrategy.recommend(
            hand: round.hands[index], dealerUpcard: up,
            rules: rules, legalActions: round.legalActions(handIndex: index)
        )
    }

    var liveRecommendation: BlackjackStrategy.Recommendation? {
        guard assist.mode == .guided && assist.recommendAction else { return nil }
        guard let round, case .playerTurn(let index) = round.phase, let up = round.dealerUpcard else { return nil }
        return BlackjackStrategy.recommend(
            hand: round.hands[index], dealerUpcard: up,
            rules: rules, legalActions: round.legalActions(handIndex: index)
        )
    }

    private func finishIfSettled() {
        guard let current = round, case .settled = current.phase,
              let settlement = current.settlement else { return }
        shoe = current.shoe
        lastSettlement = settlement

        let detail = CasinoRoundRecord.BlackjackDetail(
            hands: zip(current.hands, settlement.hands).map { hand, result in
                .init(cards: hand.cards, actions: hand.actions, outcome: result.outcome,
                      bet: result.bet, returned: result.returned,
                      strategyMistakes: mistakes)
            },
            dealerCards: current.dealerCards,
            insuranceBet: settlement.insuranceBet,
            insuranceReturned: settlement.insuranceReturned,
            rules: rules
        )
        let summary: String
        if settlement.net > 0 { summary = "Won \(settlement.net)" }
        else if settlement.net == 0 { summary = "Push" }
        else { summary = "Lost \(-settlement.net)" }
        let record = CasinoRoundRecord(
            game: .blackjack, date: Date(), seed: current.fairness.seed,
            wagered: settlement.totalStaked, returned: settlement.totalReturned,
            outcomeSummary: summary, detail: .blackjack(detail)
        )
        safeguardNotice = casino.complete(round: record)
        countVisibleCards()
        persist()
    }

    func acknowledgeSafeguard() {
        safeguardNotice = nil
        casino.beginSession(for: .blackjack)
    }
}

/// The blackjack table (§6): dealer on top, player hands below, actions in
/// thumb reach, optional strategy and counting panels.
struct BlackjackView: View {
    @EnvironmentObject var casino: CasinoStore
    @EnvironmentObject var settingsStore: SettingsStore
    @StateObject private var model: BlackjackViewModel

    init(casino: CasinoStore) {
        _model = StateObject(wrappedValue: BlackjackViewModel(casino: casino))
    }

    private var accent: Color { settingsStore.accent }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            ScrollView {
                VStack(spacing: Theme.Spacing.l) {
                    bankrollHeader
                    dealerArea
                    playerArea
                    controls
                    assistPanels
                    if let settlement = model.lastSettlement {
                        settlementCard(settlement)
                    }
                }
                .padding(Theme.Spacing.l)
            }
        }
        .navigationTitle("Blackjack")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: "blackjack-settings") {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        .alert(item: Binding(
            get: { model.safeguardNotice.map { SafeguardAlert(trigger: $0) } },
            set: { _ in }
        )) { alert in
            Alert(
                title: Text("Session limit reached"),
                message: Text(alert.trigger.message + " Start a new session whenever you like."),
                dismissButton: .default(Text("Show summary")) { model.acknowledgeSafeguard() }
            )
        }
    }

    private struct SafeguardAlert: Identifiable {
        let trigger: SessionSafeguards.Trigger
        var id: String { trigger.rawValue }
    }

    // MARK: - Header

    private var bankrollHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("BANKROLL").sectionHeader()
                Text(model.bankroll.isPractice ? "Practice ∞" : "\(model.bankroll.chips)")
                    .font(Theme.Fonts.potValue)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("SHOE").sectionHeader()
                Text("\(model.shoe.remainingCount) cards\(model.shoe.needsReshuffle ? " · shuffle next" : "")")
                    .font(Theme.Fonts.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(Theme.Spacing.m)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.backgroundElevated))
    }

    // MARK: - Cards

    private func cardView(_ card: BlackjackCard, faceUp: Bool = true) -> some View {
        PlayingCardView(card: faceUp ? Card(card.rank, card.suit) : nil,
                        width: 46, style: settingsStore.settings.deckStyle)
    }

    private var dealerArea: some View {
        VStack(spacing: Theme.Spacing.s) {
            Text("DEALER").sectionHeader()
            if let round = model.round {
                HStack(spacing: 6) {
                    ForEach(Array(round.dealerCards.enumerated()), id: \.offset) { index, card in
                        cardView(card, faceUp: index == 0 || round.dealerHoleRevealed)
                    }
                }
                if round.dealerHoleRevealed && model.assist.showHandTotal {
                    Text("\(round.dealerTotal)")
                        .font(Theme.Fonts.stackValue)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
                if model.assist.showDealerLogic {
                    Text(model.rules.dealerHitsSoft17 ? "Dealer hits soft 17" : "Dealer stands on all 17s")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            } else {
                Text("Place a bet and deal")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.vertical, Theme.Spacing.l)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.m)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.backgroundElevated.opacity(0.6)))
    }

    private var playerArea: some View {
        VStack(spacing: Theme.Spacing.m) {
            if let round = model.round {
                ForEach(Array(round.hands.enumerated()), id: \.offset) { index, hand in
                    handRow(hand, index: index, round: round)
                }
            }
        }
    }

    private func handRow(_ hand: BlackjackHand, index: Int, round: BlackjackRound) -> some View {
        let isActive = round.phase == .playerTurn(handIndex: index)
        return HStack(spacing: Theme.Spacing.m) {
            HStack(spacing: 6) {
                ForEach(Array(hand.cards.enumerated()), id: \.offset) { _, card in
                    cardView(card)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if model.assist.showHandTotal {
                    Text(hand.isSoft ? "Soft \(hand.total)" : "\(hand.total)")
                        .font(Theme.Fonts.stackValue)
                        .monospacedDigit()
                        .foregroundStyle(hand.isBust ? Theme.danger : Theme.textPrimary)
                }
                Text("Bet \(hand.bet)")
                    .font(Theme.Fonts.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                if hand.isSurrendered {
                    Text("Surrendered").font(Theme.Fonts.caption).foregroundStyle(Theme.caution)
                }
            }
        }
        .padding(Theme.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .fill(Theme.backgroundElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(isActive ? accent : Theme.separator, lineWidth: isActive ? 1.5 : 1)
        )
    }

    // MARK: - Controls

    @ViewBuilder
    private var controls: some View {
        if let round = model.round, case .insuranceOffer = round.phase {
            VStack(spacing: Theme.Spacing.s) {
                Text("Dealer shows an ace. Insurance costs \(round.hands[0].bet / 2) and pays 2:1 on a dealer blackjack.")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: Theme.Spacing.s) {
                    ActionButton(title: "No insurance", role: .secondary, accent: accent, identifier: "bj.noInsurance") {
                        model.decideInsurance(take: false)
                    }
                    ActionButton(title: "Insure", role: .quiet, accent: accent, identifier: "bj.insurance") {
                        model.decideInsurance(take: true)
                    }
                }
            }
        } else if let round = model.round, case .playerTurn(let index) = round.phase {
            VStack(spacing: Theme.Spacing.s) {
                if let hint = model.requestedHint ?? model.liveRecommendation {
                    VStack(spacing: 3) {
                        Text("Basic strategy: \(hint.action.displayName)")
                            .font(Theme.Fonts.caption.weight(.bold))
                            .foregroundStyle(accent)
                        Text(hint.explanation)
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
                let legal = round.legalActions(handIndex: index)
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(legal, id: \.self) { action in
                        ActionButton(
                            title: action.displayName,
                            role: action == .stand ? .primary : (action == .surrender ? .destructive : .secondary),
                            accent: accent,
                            identifier: "bj.\(action.rawValue)"
                        ) {
                            model.apply(action, handIndex: index)
                        }
                        .opacity(model.canApply(action, handIndex: index) ? 1 : 0.4)
                        .disabled(!model.canApply(action, handIndex: index))
                    }
                }
                if model.assist.mode == .hint && model.requestedHint == nil {
                    Button("Hint") { model.requestHint() }
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(accent)
                }
            }
        } else {
            dealControls
        }
    }

    private var dealControls: some View {
        VStack(spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                ForEach([2, 10, 25, 50, 100], id: \.self) { amount in
                    Button {
                        model.bet = amount
                    } label: {
                        Text("\(amount)")
                            .font(Theme.Fonts.secondaryAction)
                            .monospacedDigit()
                            .foregroundStyle(model.bet == amount ? Color.black : Theme.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(model.bet == amount ? accent : Theme.backgroundElevated))
                    }
                }
            }
            ActionButton(title: "Deal · bet \(model.bet)", role: .primary, accent: accent, identifier: "bj.deal") {
                model.deal()
            }
            .disabled(!model.canDeal)
            .opacity(model.canDeal ? 1 : 0.5)
            if !model.bankroll.isPractice && model.bankroll.chips <= 0 {
                ActionButton(title: "Rebuild bankroll (free)", role: .secondary, accent: accent, identifier: "bj.rebuild") {
                    casino.rebuildCareerBankroll(for: .blackjack)
                }
            }
        }
    }

    // MARK: - Assist panels

    @ViewBuilder
    private var assistPanels: some View {
        if model.assist.showRunningCount || model.assist.showTrueCount {
            HStack(spacing: Theme.Spacing.xl) {
                if model.assist.showRunningCount {
                    VStack(spacing: 2) {
                        Text("RUNNING").sectionHeader()
                        Text("\(model.runningCount)")
                            .font(Theme.Fonts.potValue).monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
                if model.assist.showTrueCount {
                    VStack(spacing: 2) {
                        Text("TRUE").sectionHeader()
                        Text("\(model.trueCount)")
                            .font(Theme.Fonts.potValue).monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(Theme.Spacing.m)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.backgroundElevated.opacity(0.6)))
        }
        if model.assist.showStrategyChart {
            Text("Chart: stand 17+; stand 13-16 vs 2-6 else hit; 12 stands vs 4-6; double 11 (and 10 vs 2-9, 9 vs 3-6); soft 18 doubles vs 3-6, stands vs 2/7/8, hits vs 9+; always split A,A and 8,8; never split 10,10 or 5,5.")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textSecondary)
                .padding(Theme.Spacing.m)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.backgroundElevated.opacity(0.6)))
        }
    }

    // MARK: - Settlement

    private func settlementCard(_ settlement: BlackjackSettlement) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                Text(settlement.net > 0 ? "+\(settlement.net)" : "\(settlement.net)")
                    .font(Theme.Fonts.screenTitle)
                    .monospacedDigit()
                    .foregroundStyle(settlement.net > 0 ? Theme.positive : (settlement.net < 0 ? Theme.danger : Theme.textPrimary))
                Spacer()
            }
            ForEach(Array(settlement.hands.enumerated()), id: \.offset) { index, hand in
                Text("Hand \(index + 1): \(outcomeText(hand.outcome)) · bet \(hand.bet), returned \(hand.returned)")
                    .font(Theme.Fonts.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
            if settlement.insuranceBet > 0 {
                Text("Insurance \(settlement.insuranceBet): returned \(settlement.insuranceReturned)")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            if model.assist.explainMistakesAfterHand && !model.mistakes.isEmpty {
                ForEach(model.mistakes, id: \.self) { mistake in
                    Label(mistake, systemImage: "exclamationmark.circle")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.caution)
                }
            }
            if let round = model.round {
                Text("Fair deal: shoe seed \(round.fairness.seed) · card \(round.fairness.position)")
                    .font(Theme.Fonts.telemetry)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.backgroundElevated))
    }

    private func outcomeText(_ outcome: BlackjackHandOutcome) -> String {
        switch outcome {
        case .blackjack: return "Blackjack"
        case .win: return "Win"
        case .push: return "Push"
        case .loss: return "Loss"
        case .bust: return "Bust"
        case .surrender: return "Surrendered"
        case .dealerBlackjack: return "Dealer blackjack"
        }
    }
}
