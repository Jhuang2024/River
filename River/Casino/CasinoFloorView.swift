import SwiftUI
import RiverKit

/// Casino Floor (§1, §7): four mode cards with poker first, cross-game
/// summary, history and settings. Poker remains the primary mode; nothing
/// here displaces the training identity.
struct CasinoFloorView: View {
    @EnvironmentObject var casino: CasinoStore
    @EnvironmentObject var game: GameViewModel
    @EnvironmentObject var settingsStore: SettingsStore

    private var accent: Color { settingsStore.accent }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            ScrollView {
                VStack(spacing: Theme.Spacing.l) {
                    pokerCard
                    ForEach(CasinoGameKind.allCases) { kind in
                        gameCard(kind)
                    }
                    summaryCard
                    achievementsCard
                    links
                    Text("Fictional chips only · fair seeded outcomes · nothing to buy")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(Theme.Spacing.l)
            }
            .readableColumn()
        }
        .navigationTitle("Casino Floor")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Mode cards (§7)

    private var pokerCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                Image(systemName: "suit.spade.fill")
                    .foregroundStyle(accent)
                Text("Texas Hold'em")
                    .font(Theme.Fonts.body.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("PRIMARY").sectionHeader()
            }
            Text("Strategy, opponents, and hand analysis")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: Theme.Spacing.s) {
                if game.hasSavedSession {
                    ActionButton(title: "Continue", role: .primary, accent: accent, identifier: "floor.poker.continue") {
                        game.resumeSavedSession()
                    }
                }
                NavigationLink(value: Route.setup) {
                    Text(game.hasSavedSession ? "New game" : "Play")
                        .riverButton(prominent: !game.hasSavedSession, accent: accent)
                }
            }
        }
        .padding(Theme.Spacing.l)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.backgroundElevated))
    }

    private func gameCard(_ kind: CasinoGameKind) -> some View {
        let last = casino.lastRound(for: kind)
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                Image(systemName: kind.symbolName)
                    .foregroundStyle(accent)
                Text(kind.displayName)
                    .font(Theme.Fonts.body.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if !kind.isSkillGame {
                    Text("PURE CHANCE").sectionHeader()
                }
            }
            Text(kind.tagline)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textSecondary)
            if let last {
                Text("Last round: \(last.outcomeSummary) · \(last.net >= 0 ? "+\(last.net)" : "\(last.net)")")
                    .font(Theme.Fonts.caption)
                    .monospacedDigit()
                    .foregroundStyle(last.net >= 0 ? Theme.positive : Theme.danger)
            }
            NavigationLink(value: kind.rawValue) {
                Text(last == nil ? "Play" : "Continue")
                    .riverButton(prominent: false, accent: accent)
            }
        }
        .padding(Theme.Spacing.l)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.backgroundElevated.opacity(0.75)))
    }

    // MARK: - Cross-game summary (§8)

    private var summaryCard: some View {
        let stats = casino.stats()
        let blackjack = casino.stats(for: .blackjack)
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("FLOOR SUMMARY").sectionHeader()
            HStack(spacing: Theme.Spacing.xl) {
                metric("Rounds", "\(stats.rounds)")
                metric("Wagered", "\(stats.totalWagered)")
                metric("Returned", "\(stats.totalReturned)")
                metric("Net", stats.net >= 0 ? "+\(stats.net)" : "\(stats.net)",
                       color: stats.net >= 0 ? Theme.positive : Theme.danger)
            }
            Divider().overlay(Theme.separator)
            Text("Poker and Blackjack reward good decisions. Your Blackjack decision accuracy so far: \(blackjack.bjDecisions > 0 ? "\(Int((blackjack.bjDecisionAccuracy * 100).rounded()))%" : "no data yet").")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textSecondary)
            Text("Roulette and Plinko are pure chance: no play pattern, streak or system improves their odds.")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.backgroundElevated))
    }

    private func metric(_ label: String, _ value: String, color: Color = Theme.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Theme.Fonts.stackValue)
                .monospacedDigit()
                .foregroundStyle(color)
            Text(label)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var achievementsCard: some View {
        let unlocked = casino.unlockedAchievements
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                Text("FLOOR ACHIEVEMENTS").sectionHeader()
                Spacer()
                Text("\(unlocked.count)/\(CasinoAchievementLibrary.all.count)")
                    .font(Theme.Fonts.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.s) {
                ForEach(CasinoAchievementLibrary.all) { achievement in
                    HStack(spacing: 6) {
                        Image(systemName: unlocked.contains(achievement.id) ? achievement.symbolName : "lock.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(unlocked.contains(achievement.id) ? accent : Theme.textTertiary)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(achievement.title)
                                .font(Theme.Fonts.caption.weight(.semibold))
                                .foregroundStyle(unlocked.contains(achievement.id) ? Theme.textPrimary : Theme.textTertiary)
                                .lineLimit(1)
                            Text(achievement.detail)
                                .font(.system(size: 9, design: .rounded))
                                .foregroundStyle(Theme.textTertiary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.chip).fill(Theme.surface.opacity(0.6)))
                }
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.backgroundElevated.opacity(0.75)))
    }

    private var links: some View {
        VStack(spacing: Theme.Spacing.s) {
            NavigationLink(value: "casino-history") {
                linkRow("Round history & fairness", symbol: "clock.arrow.circlepath")
            }
            NavigationLink(value: "counting-trainer") {
                linkRow("Card counting trainer", symbol: "number.circle")
            }
            NavigationLink(value: "casino-settings") {
                linkRow("Bankroll, rules & safeguards", symbol: "slider.horizontal.3")
            }
            NavigationLink(value: "glossary") {
                linkRow("Glossary: what the words mean", symbol: "book.closed")
            }
        }
    }

    private func linkRow(_ title: String, symbol: String) -> some View {
        HStack {
            Image(systemName: symbol)
                .foregroundStyle(accent)
                .frame(width: 26)
            Text(title)
                .font(Theme.Fonts.secondaryAction)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(Theme.Spacing.m)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.backgroundElevated))
    }
}

// MARK: - History (§12)

struct CasinoHistoryView: View {
    @EnvironmentObject var casino: CasinoStore
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var filter: CasinoGameKind?

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            ScrollView {
                VStack(spacing: Theme.Spacing.m) {
                    Picker("Game", selection: $filter) {
                        Text("All").tag(CasinoGameKind?.none)
                        ForEach(CasinoGameKind.allCases) { kind in
                            Text(kind.displayName).tag(CasinoGameKind?.some(kind))
                        }
                    }
                    .pickerStyle(.segmented)
                    let records = casino.records(for: filter).reversed()
                    if records.isEmpty {
                        Text("No rounds yet.")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.top, Theme.Spacing.xl)
                    }
                    ForEach(Array(records)) { record in
                        recordRow(record)
                    }
                }
                .padding(Theme.Spacing.l)
            }
            .readableColumn()
        }
        .navigationTitle("Casino history")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func recordRow(_ record: CasinoRoundRecord) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Image(systemName: record.game.symbolName)
                    .font(.system(size: 12))
                    .foregroundStyle(settingsStore.accent)
                Text("\(record.game.displayName) · \(record.outcomeSummary)")
                    .font(Theme.Fonts.caption.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(record.net >= 0 ? "+\(record.net)" : "\(record.net)")
                    .font(Theme.Fonts.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(record.net >= 0 ? Theme.positive : Theme.danger)
            }
            Text("Wagered \(record.wagered) · returned \(record.returned) · seed \(record.seed)")
                .font(Theme.Fonts.telemetry)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.backgroundElevated))
    }
}

// MARK: - Settings (§2, §5, §6, §11)

struct CasinoSettingsView: View {
    @EnvironmentObject var casino: CasinoStore

    var body: some View {
        List {
            Section {
                Picker("Bankroll mode", selection: $casino.settings.bankrollMode) {
                    ForEach(BankrollMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Text(casino.settings.bankrollMode.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Toggle("Independent practice bankrolls", isOn: $casino.settings.independentBankrolls)
                Text("When on, Blackjack, Roulette and Plinko each keep their own chips.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Fictional bankroll")
            }

            Section("Session safeguards (optional)") {
                limitStepper("Round limit", value: Binding(
                    get: { casino.settings.safeguards.roundLimit ?? 0 },
                    set: { casino.settings.safeguards.roundLimit = $0 == 0 ? nil : $0 }
                ), step: 10)
                limitStepper("Loss limit", value: Binding(
                    get: { casino.settings.safeguards.lossLimit ?? 0 },
                    set: { casino.settings.safeguards.lossLimit = $0 == 0 ? nil : $0 }
                ), step: 50)
                limitStepper("Profit target", value: Binding(
                    get: { casino.settings.safeguards.profitTarget ?? 0 },
                    set: { casino.settings.safeguards.profitTarget = $0 == 0 ? nil : $0 }
                ), step: 50)
                Text("Zero disables a limit. When a limit is reached the current round finishes safely and the summary appears.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Blackjack rules") {
                Toggle("Dealer hits soft 17", isOn: $casino.settings.blackjackRules.dealerHitsSoft17)
                Toggle("Double after split", isOn: $casino.settings.blackjackRules.doubleAfterSplitAllowed)
                Toggle("Surrender", isOn: $casino.settings.blackjackRules.surrenderAllowed)
                Toggle("Insurance", isOn: $casino.settings.blackjackRules.insuranceAllowed)
                Stepper("Decks: \(casino.settings.blackjackRules.decks)",
                        value: $casino.settings.blackjackRules.decks, in: 1...8)
                Text("Blackjack pays 3:2. Strategy advice always follows the rules configured here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Blackjack assistance") {
                Picker("Mode", selection: Binding(
                    get: { casino.settings.blackjackAssist.mode },
                    set: { casino.settings.blackjackAssist.applyPreset($0) }
                )) {
                    ForEach(BlackjackAssistOptions.Mode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Show hand total", isOn: $casino.settings.blackjackAssist.showHandTotal)
                Toggle("Show dealer logic", isOn: $casino.settings.blackjackAssist.showDealerLogic)
                Toggle("Recommend action", isOn: $casino.settings.blackjackAssist.recommendAction)
                Toggle("Show strategy chart", isOn: $casino.settings.blackjackAssist.showStrategyChart)
                Toggle("Explain mistakes after hand", isOn: $casino.settings.blackjackAssist.explainMistakesAfterHand)
                Toggle("Show running count", isOn: $casino.settings.blackjackAssist.showRunningCount)
                Toggle("Show true count", isOn: $casino.settings.blackjackAssist.showTrueCount)
            }

            Section("Roulette") {
                Picker("Wheel", selection: $casino.settings.rouletteWheel) {
                    ForEach(RouletteWheel.allCases) { wheel in
                        Text(wheel.displayName).tag(wheel)
                    }
                }
                Text(casino.settings.rouletteWheel.houseEdgeDescription)
                    .font(.footnote)
                    .foregroundStyle(casino.settings.rouletteWheel == .american ? Color(red: 0.85, green: 0.66, blue: 0.30) : .secondary)
            }

            Section("Plinko") {
                Picker("Rows", selection: $casino.settings.plinkoRows) {
                    ForEach(PlinkoRows.allCases) { rows in
                        Text(rows.displayName).tag(rows)
                    }
                }
                Picker("Risk", selection: $casino.settings.plinkoRisk) {
                    ForEach(PlinkoRisk.allCases) { risk in
                        Text(risk.displayName).tag(risk)
                    }
                }
                .pickerStyle(.segmented)
                Text("Multiplier tables are fixed configuration with a small, constant house edge. Nothing you unlock or do changes them.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Casino settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func limitStepper(_ label: String, value: Binding<Int>, step: Int) -> some View {
        Stepper("\(label): \(value.wrappedValue == 0 ? "off" : "\(value.wrappedValue)")",
                value: value, in: 0...10_000, step: step)
    }
}

// MARK: - Counting trainer (§6)

struct CountingTrainerView: View {
    @EnvironmentObject var casino: CasinoStore
    @EnvironmentObject var settingsStore: SettingsStore

    @State private var drill: CountingTrainer.Drill?
    @State private var revealedCount = 0
    @State private var answer = 0
    @State private var drillResult: Bool?

    @State private var shoeSimulation: CountingTrainer.ShoeSimulation?
    @State private var burstIndex = 0
    @State private var shoeAnswer = 0
    @State private var shoeMistakes = 0
    @State private var shoeFinished = false

    private var accent: Color { settingsStore.accent }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            ScrollView {
                VStack(spacing: Theme.Spacing.l) {
                    Text("Hi-Lo counting: cards 2-6 count +1, cards 7-9 count 0, tens and aces count -1. Keep a running total as cards appear. Educational only: the dealer never reacts to your count.")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textSecondary)
                    drillCard
                    shoeCard
                }
                .padding(Theme.Spacing.l)
            }
            .readableColumn()
        }
        .navigationTitle("Counting trainer")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var drillCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("CARD DRILL").sectionHeader()
            if let drill {
                let shown = Array(drill.cards.prefix(revealedCount))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 4) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { _, card in
                        PlayingCardView(card: Card(card.rank, card.suit), width: 30,
                                        style: settingsStore.settings.deckStyle)
                    }
                }
                if revealedCount < drill.cards.count {
                    ActionButton(title: "Next card (\(revealedCount)/\(drill.cards.count))",
                                 role: .secondary, accent: accent, identifier: "count.next") {
                        revealedCount += 1
                    }
                } else {
                    Stepper("Your running count: \(answer)", value: $answer, in: -30...30)
                        .font(Theme.Fonts.body)
                        .foregroundStyle(Theme.textPrimary)
                    ActionButton(title: "Check", role: .primary, accent: accent, identifier: "count.check") {
                        drillResult = (answer == drill.correctRunningCount)
                    }
                    if let result = drillResult {
                        Text(result ? "Correct: the count is \(drill.correctRunningCount)."
                                    : "Not quite: the count is \(drill.correctRunningCount).")
                            .font(Theme.Fonts.caption.weight(.semibold))
                            .foregroundStyle(result ? Theme.positive : Theme.danger)
                    }
                }
            }
            ActionButton(title: drill == nil ? "Start a 12-card drill" : "New drill",
                         role: drill == nil ? .primary : .quiet, accent: accent, identifier: "count.newDrill") {
                drill = CountingTrainer.drill(count: 12, seed: UInt64.random(in: UInt64.min...UInt64.max))
                revealedCount = 1
                answer = 0
                drillResult = nil
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.backgroundElevated))
    }

    private var shoeCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("FULL SHOE (2 DECKS, BURSTS OF 10)").sectionHeader()
            if let simulation = shoeSimulation, !shoeFinished {
                let burst = simulation.bursts[burstIndex]
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 4) {
                    ForEach(Array(burst.enumerated()), id: \.offset) { _, card in
                        PlayingCardView(card: Card(card.rank, card.suit), width: 30,
                                        style: settingsStore.settings.deckStyle)
                    }
                }
                Stepper("Running count so far: \(shoeAnswer)", value: $shoeAnswer, in: -60...60)
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.textPrimary)
                ActionButton(title: "Check burst \(burstIndex + 1)/\(simulation.bursts.count)",
                             role: .primary, accent: accent, identifier: "count.shoeCheck") {
                    let correct = simulation.runningCountAfterBurst[burstIndex]
                    if shoeAnswer != correct {
                        shoeMistakes += 1
                        shoeAnswer = correct // resynchronise honestly
                    }
                    if burstIndex + 1 < simulation.bursts.count {
                        burstIndex += 1
                    } else {
                        shoeFinished = true
                        if shoeMistakes == 0 {
                            casino.noteFullShoeCounted()
                        }
                    }
                }
                if shoeMistakes > 0 {
                    Text("\(shoeMistakes) slip\(shoeMistakes == 1 ? "" : "s") so far: the count was corrected for you.")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.caution)
                }
            } else if shoeFinished {
                Text(shoeMistakes == 0 ? "Perfect shoe: every burst counted correctly."
                                       : "Shoe complete with \(shoeMistakes) slip\(shoeMistakes == 1 ? "" : "s"). Run it again for a clean count.")
                    .font(Theme.Fonts.caption.weight(.semibold))
                    .foregroundStyle(shoeMistakes == 0 ? Theme.positive : Theme.caution)
            }
            ActionButton(title: shoeSimulation == nil ? "Start shoe simulation" : "Restart shoe",
                         role: shoeSimulation == nil ? .primary : .quiet, accent: accent, identifier: "count.shoe") {
                shoeSimulation = CountingTrainer.shoeSimulation(
                    decks: 2, burstSize: 10,
                    seed: UInt64.random(in: UInt64.min...UInt64.max)
                )
                burstIndex = 0
                shoeAnswer = 0
                shoeMistakes = 0
                shoeFinished = false
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.backgroundElevated))
    }
}
