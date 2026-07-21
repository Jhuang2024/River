import SwiftUI
import RiverKit

/// The active poker table (§6): portrait, three regions - thin status bar,
/// table with five AI seats, hero region with cards and controls. Full-screen,
/// outside the tab hierarchy.
struct TableView: View {
    @ObservedObject var game: GameViewModel
    @EnvironmentObject var settingsStore: SettingsStore

    /// Identifiable wrapper so `.sheet(item:)` can present a seat's read.
    private struct SeatSelection: Identifiable {
        let id: Int
    }

    @State private var showBetSheet = false
    @State private var showMenu = false
    @State private var showHistory = false
    @State private var showPotBreakdown = false
    @State private var opponentReadSeat: SeatSelection? = nil
    @State private var confirmingAllInAmount: Int? = nil
    @State private var confirmingCallAllIn = false
    @State private var confirmingFoldReason: String? = nil
    @State private var showAdviceSheet = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accent: Color { settingsStore.accent }
    private var deckStyle: DeckStyle { settingsStore.settings.deckStyle }

    /// Seat anchors (§7): hero bottom centre; opponents clockwise from the
    /// hero's left - left middle, upper left, top centre, upper right,
    /// right middle. Slightly asymmetric beats a cramped perfect oval.
    private let seatAnchors: [CGPoint] = [
        CGPoint(x: 0.50, y: 0.94),   // hero (badge only; cards live below)
        CGPoint(x: 0.115, y: 0.635),
        CGPoint(x: 0.145, y: 0.30),
        CGPoint(x: 0.50, y: 0.145),
        CGPoint(x: 0.855, y: 0.30),
        CGPoint(x: 0.885, y: 0.635)
    ]

    /// Where a seat's committed chips render (pulled toward the pot).
    private func chipAnchor(for seat: Int) -> CGPoint {
        let anchor = seatAnchors[min(seat, seatAnchors.count - 1)]
        let center = CGPoint(x: 0.5, y: 0.50)
        return CGPoint(
            x: anchor.x + (center.x - anchor.x) * 0.42,
            y: anchor.y + (center.y - anchor.y) * 0.38
        )
    }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            VStack(spacing: 0) {
                statusBar
                GeometryReader { proxy in
                    tableRegion(size: proxy.size)
                }
                heroRegion
            }
        }
        .statusBarHidden(false)
        .sheet(isPresented: $showMenu) { menuSheet }
        .sheet(isPresented: $showHistory) {
            ActionHistorySheet(sections: game.historySections())
        }
        .sheet(isPresented: $showPotBreakdown) {
            if let breakdown = game.potBreakdown() {
                PotBreakdownSheet(entries: breakdown.entries, total: breakdown.total)
            }
        }
        .sheet(isPresented: $showAdviceSheet) {
            if let advice = game.advice {
                HintSheet(advice: advice, accent: accent)
            }
        }
        .sheet(item: $opponentReadSeat) { selection in
            if let read = game.opponentRead(seat: selection.id) {
                OpponentReadSheet(read: read)
            }
        }
        .onChange(of: game.advice) { _, newValue in
            if newValue != nil {
                showAdviceSheet = true
            }
        }
        .onChange(of: game.heroActions) { _, newValue in
            if newValue == nil {
                showBetSheet = false
            }
        }
        .confirmationDialog(
            "Go all-in for \(confirmingAllInAmount ?? 0)?",
            isPresented: Binding(
                get: { confirmingAllInAmount != nil },
                set: { if !$0 { confirmingAllInAmount = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("All-in", role: .destructive) {
                if let amount = confirmingAllInAmount, let options = game.heroActions?.betRaise {
                    game.submitHeroAction(PlayerAction(kind: options.kind, toAmount: amount))
                }
                confirmingAllInAmount = nil
            }
            Button("Cancel", role: .cancel) { confirmingAllInAmount = nil }
        }
        .confirmationDialog(
            "Fold anyway?",
            isPresented: Binding(
                get: { confirmingFoldReason != nil },
                set: { if !$0 { confirmingFoldReason = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Fold", role: .destructive) {
                confirmingFoldReason = nil
                game.submitHeroAction(.fold)
            }
            Button("Keep playing", role: .cancel) { confirmingFoldReason = nil }
        } message: {
            Text(confirmingFoldReason ?? "")
        }
        .confirmationDialog(
            "Call all-in for \(game.heroActions?.callCost ?? 0)?",
            isPresented: $confirmingCallAllIn,
            titleVisibility: .visible
        ) {
            Button("Call all-in", role: .destructive) {
                confirmingCallAllIn = false
                game.submitHeroAction(.call)
            }
            Button("Cancel", role: .cancel) { confirmingCallAllIn = false }
        }
    }

    // MARK: - Status bar (top region)

    private var statusBar: some View {
        HStack(spacing: Theme.Spacing.s) {
            Button {
                showMenu = true
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(8)
            }
            .accessibilityIdentifier("table.menu")
            .accessibilityLabel("Pause menu")

            Spacer()
            if let table = game.table {
                VStack(spacing: 0) {
                    Text(table.handsTarget > 0 ? "Hand \(table.handNumber) of \(table.handsTarget)" : "Hand \(table.handNumber)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    Text("Cash · Blinds \(table.blindsText)")
                        .font(Theme.Fonts.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()

            Button {
                showHistory = true
            } label: {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(8)
            }
            .accessibilityIdentifier("table.history")
            .accessibilityLabel("Action history")
        }
        .padding(.horizontal, 8)
        .padding(.top, 2)
    }

    // MARK: - Table region (middle)

    private func tableRegion(size: CGSize) -> some View {
        let heroDeciding = game.heroActions != nil
        return ZStack {
            // Felt surface.
            RoundedRectangle(cornerRadius: size.width * 0.40, style: .continuous)
                .fill(Theme.tableGradient(for: settingsStore.settings.tableTheme))
                .overlay(
                    RoundedRectangle(cornerRadius: size.width * 0.40, style: .continuous)
                        .strokeBorder(Theme.rail, lineWidth: 7)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size.width * 0.40, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                        .padding(9)
                )
                .padding(.horizontal, size.width * 0.075)
                .padding(.vertical, size.height * 0.085)

            if let table = game.table {
                // Board, texture, pot.
                VStack(spacing: Theme.Spacing.s) {
                    CommunityBoardView(
                        board: table.board,
                        visibleCount: game.visibleBoardCount,
                        deckStyle: deckStyle,
                        cardWidth: min(46, size.width / 8.4),
                        textureLabels: settingsStore.settings.showBoardTexture
                            ? BoardTexture.labels(for: Array(table.board.prefix(game.visibleBoardCount)))
                            : []
                    )
                    PotView(pot: table.pot, tappable: game.potIsInspectable, accent: accent) {
                        showPotBreakdown = true
                    }
                }
                .position(x: size.width * 0.5, y: size.height * 0.47)

                // Winner banner (§23).
                if let banner = game.winnerBanner {
                    Text(banner)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(accent))
                        .position(x: size.width * 0.5, y: size.height * 0.66)
                        .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                }

                // Opponent seats.
                ForEach(table.seats) { seat in
                    if !seat.isHero {
                        PokerSeatView(
                            seat: seat,
                            deckStyle: deckStyle,
                            accent: accent,
                            deEmphasized: heroDeciding && !seat.isActing,
                            onTap: { opponentReadSeat = SeatSelection(id: seat.id) }
                        )
                        .position(
                            x: seatAnchors[seat.id].x * size.width,
                            y: seatAnchors[seat.id].y * size.height
                        )
                    }
                    // Committed chips travel to the pot when sweeping (§22).
                    ChipStackView(amount: seat.committed, chipColor: Theme.chipColor(for: settingsStore.settings.chipStyle))
                        .position(
                            x: (game.chipsSweeping ? 0.5 : chipAnchor(for: seat.id).x) * size.width,
                            y: (game.chipsSweeping ? 0.50 : chipAnchor(for: seat.id).y) * size.height
                        )
                        .opacity(game.chipsSweeping ? 0 : 1)
                }

                // Hero stack badge at the table edge.
                if let hero = table.seats.first(where: { $0.isHero }) {
                    heroBadge(hero)
                        .position(x: size.width * 0.5, y: size.height * 0.915)
                }
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.12) : .easeInOut(duration: Theme.Motion.chip), value: game.chipsSweeping)
        .animation(.easeInOut(duration: Theme.Motion.button), value: game.table)
    }

    private func stackText(_ hero: SeatUIState) -> String {
        guard let table = game.table, table.bigBlind > 0 else { return "\(hero.stack)" }
        let bb = Double(hero.stack) / Double(table.bigBlind)
        switch settingsStore.settings.stackDisplay {
        case .chips: return "\(hero.stack)"
        case .bigBlinds: return String(format: "%.1f BB", bb)
        case .both: return "\(hero.stack) · \(String(format: "%.0f BB", bb))"
        }
    }

    private func heroBadge(_ hero: SeatUIState) -> some View {
        Button {
            settingsStore.settings.stackDisplay = settingsStore.settings.stackDisplay.next
        } label: {
            HStack(spacing: 8) {
                if hero.isButton {
                    DealerButtonView(size: 17)
                } else if let blind = hero.blindLabel {
                    Text(blind)
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 17, height: 17)
                        .background(Circle().fill(Color.white.opacity(0.14)))
                }
                Text(hero.position)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                Text(hero.isAllIn ? "ALL-IN" : stackText(hero))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(hero.isAllIn ? Theme.danger : accent)
                if hero.isActing {
                    Circle().fill(accent).frame(width: 7, height: 7)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.black.opacity(0.55)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Your stack, \(hero.stack) chips, position \(hero.position)")
        .accessibilityIdentifier("hero.stack")
    }

    // MARK: - Hero region (bottom)

    private var heroRegion: some View {
        VStack(spacing: Theme.Spacing.s) {
            if let fraction = game.heroTimerFraction {
                DecisionTimerView(fraction: fraction, accent: accent)
                    .padding(.horizontal, Theme.Spacing.l)
            }
            HStack(alignment: .bottom, spacing: Theme.Spacing.m) {
                if let hero = game.table?.seats.first(where: { $0.isHero }) {
                    HoleCardsView(
                        cards: hero.visibleCards,
                        width: 56,
                        style: deckStyle,
                        dimmed: hero.hasFolded,
                        onSwipeDownFold: settingsStore.settings.swipeDownToFold ? { requestFold() } : nil
                    )
                }
                Spacer()
                glancePanel
            }
            .padding(.horizontal, Theme.Spacing.l)

            controlsArea
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.bottom, Theme.Spacing.s)
        }
        .frame(minHeight: 196)
        .background(Color.black.opacity(game.heroActions != nil ? 0.34 : 0.22))
        .animation(.easeInOut(duration: Theme.Motion.button), value: game.heroActions != nil)
    }

    /// Level-1 assistance: hand, draws, price (§17).
    private var glancePanel: some View {
        VStack(alignment: .trailing, spacing: 3) {
            if let description = game.heroHandDescription {
                Text(description)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if !game.heroDrawLabels.isEmpty {
                Text(game.heroDrawLabels.joined(separator: " · "))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.info)
            }
            if let priceLine {
                Text(priceLine)
                    .font(Theme.Fonts.telemetry)
                    .foregroundStyle(Theme.textSecondary)
            }
            if settingsStore.settings.allowRecommendations && game.heroActions != nil {
                Button {
                    game.requestAdvice()
                } label: {
                    Label(game.adviceLoading ? "Thinking…" : "Hint", systemImage: "lightbulb")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(accent)
                }
                .disabled(game.adviceLoading)
                .accessibilityIdentifier("table.hint")
            }
        }
    }

    /// "Call 18 · Pot 72" plus required equity when enabled (§10).
    private var priceLine: String? {
        guard let actions = game.heroActions, actions.callCost > 0, let table = game.table else { return nil }
        var line = "Call \(actions.callCost) · Pot \(table.pot + actions.callCost)"
        if settingsStore.settings.showPotOdds || settingsStore.settings.showRequiredEquity {
            let needed = Double(actions.callCost) / Double(table.pot + actions.callCost) * 100
            line += " · Need \(Int(needed.rounded()))%"
        }
        return line
    }

    @ViewBuilder
    private var controlsArea: some View {
        if showBetSheet, let actions = game.heroActions, let options = actions.betRaise, let table = game.table {
            BetSizingSheet(
                options: options,
                pot: table.pot,
                callCost: actions.callCost,
                myCommitted: heroCommitted,
                myStack: heroStack,
                bigBlind: table.bigBlind,
                currentBet: currentBetGuess(actions: actions),
                street: table.street,
                accent: accent,
                onConfirm: { amount in
                    showBetSheet = false
                    if settingsStore.settings.confirmAllIn && amount == options.maxTo && amount - heroCommitted >= heroStack {
                        confirmingAllInAmount = amount
                    } else {
                        game.submitHeroAction(PlayerAction(kind: options.kind, toAmount: amount))
                    }
                },
                onCancel: { showBetSheet = false }
            )
        } else if let actions = game.heroActions {
            ActionBar(
                actions: actions,
                accent: accent,
                leftHanded: settingsStore.settings.leftHandedMode,
                onFold: { requestFold() },
                onCheck: { game.submitHeroAction(.check) },
                onCall: {
                    if settingsStore.settings.confirmAllIn && actions.callCost >= heroStack {
                        confirmingCallAllIn = true
                    } else {
                        game.submitHeroAction(.call)
                    }
                },
                onOpenBetSheet: { showBetSheet = true }
            )
        } else {
            completionArea
        }
    }

    @ViewBuilder
    private var completionArea: some View {
        switch game.phase {
        case .handComplete:
            HStack(spacing: Theme.Spacing.m) {
                if settingsStore.settings.showSeedAfterHand, let seed = game.lastSeed {
                    Text("Seed \(seed)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                }
                ActionButton(title: "Next hand", role: .primary, accent: accent, identifier: "table.nextHand") {
                    game.startNextHand()
                }
            }
        case .sessionComplete:
            NavigationLink(value: Route.results) {
                Text(game.mode == .tournament ? "Tournament result" : "Session results")
                    .riverButton(accent: accent)
            }
            .accessibilityIdentifier("table.results")
        default:
            Text("Waiting…")
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.textTertiary)
                .padding(.vertical, 15)
        }
    }

    private var heroStack: Int {
        return game.table?.seats.first(where: { $0.isHero })?.stack ?? 0
    }

    private var heroCommitted: Int {
        return game.table?.seats.first(where: { $0.isHero })?.committed ?? 0
    }

    /// Current bet to match, reconstructed from the hero's options.
    private func currentBetGuess(actions: AvailableActions) -> Int {
        return heroCommitted + actions.fullAmountOwed
    }

    private func requestFold() {
        guard game.heroActions != nil else { return }
        if let reason = game.foldProtectionReason() {
            confirmingFoldReason = reason
        } else {
            game.submitHeroAction(.fold)
        }
    }

    // MARK: - Menu sheet

    private var menuSheet: some View {
        NavigationStack {
            List {
                Button {
                    showMenu = false
                } label: {
                    Label("Resume", systemImage: "play.fill")
                }
                Button {
                    showMenu = false
                    game.exitToMenu()
                } label: {
                    Label("Save & exit", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .accessibilityIdentifier("menu.exit")
                Section("Speed") {
                    Picker("Game speed", selection: $settingsStore.settings.speed) {
                        ForEach(GameSpeed.allCases) { speed in
                            Text(speed.displayName).tag(speed)
                        }
                    }
                    .pickerStyle(.segmented)
                    Picker("Next hand", selection: $settingsStore.settings.autoDeal) {
                        ForEach(AutoDealSetting.allCases) { setting in
                            Text(setting.displayName).tag(setting)
                        }
                    }
                }
                Section("Assistance") {
                    Picker("Style", selection: Binding(
                        get: { settingsStore.settings.assistanceLevel },
                        set: { settingsStore.settings.applyAssistancePreset($0) }
                    )) {
                        ForEach(AssistanceLevel.allCases) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Hand strength", isOn: $settingsStore.settings.showHandStrength)
                    Toggle("Pot odds", isOn: $settingsStore.settings.showPotOdds)
                    Toggle("Hints", isOn: $settingsStore.settings.allowRecommendations)
                }
                Section("Help") {
                    NavigationLink {
                        GlossaryView()
                    } label: {
                        Label("Glossary: what the words mean", systemImage: "book.closed")
                    }
                }
            }
            .navigationTitle("Paused")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}
