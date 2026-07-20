import SwiftUI
import RiverKit

/// The main play screen: portrait six-max table, hero at the bottom.
struct TableView: View {
    @ObservedObject var game: GameViewModel
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var showBetPanel = false
    @State private var showMenu = false
    @State private var confirmingAllInRaise: Int? = nil
    @State private var showAdviceSheet = false

    /// Relative seat anchor positions (hero seat 0 at the bottom, then
    /// clockwise around the table).
    private let seatAnchors: [CGPoint] = [
        CGPoint(x: 0.50, y: 0.885), // hero
        CGPoint(x: 0.115, y: 0.72),
        CGPoint(x: 0.115, y: 0.38),
        CGPoint(x: 0.50, y: 0.185),
        CGPoint(x: 0.885, y: 0.38),
        CGPoint(x: 0.885, y: 0.72)
    ]

    /// Where a seat's committed chips render (pulled toward the pot).
    private func chipAnchor(for seat: Int) -> CGPoint {
        let anchor = seatAnchors[min(seat, seatAnchors.count - 1)]
        let center = CGPoint(x: 0.5, y: 0.52)
        return CGPoint(
            x: anchor.x + (center.x - anchor.x) * 0.38,
            y: anchor.y + (center.y - anchor.y) * 0.34
        )
    }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                GeometryReader { proxy in
                    tableArea(size: proxy.size)
                }
                bottomArea
            }
        }
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showMenu) {
            menuSheet
        }
        .sheet(isPresented: $showAdviceSheet) {
            adviceSheet
        }
        .onChange(of: game.advice) { _, newValue in
            if newValue != nil {
                showAdviceSheet = true
            }
        }
        .confirmationDialog(
            "Go all-in for \(confirmingAllInRaise ?? 0)?",
            isPresented: Binding(
                get: { confirmingAllInRaise != nil },
                set: { if !$0 { confirmingAllInRaise = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("All-in", role: .destructive) {
                if let amount = confirmingAllInRaise, let options = game.heroActions?.betRaise {
                    game.submitHeroAction(PlayerAction(kind: options.kind, toAmount: amount))
                }
                confirmingAllInRaise = nil
            }
            Button("Cancel", role: .cancel) {
                confirmingAllInRaise = nil
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button {
                showMenu = true
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(8)
            }
            Spacer()
            if let table = game.table {
                VStack(spacing: 1) {
                    Text(table.handsTarget > 0 ? "Hand \(table.handNumber) of \(table.handsTarget)" : "Hand \(table.handNumber)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Blinds \(table.blindsText) · \(table.statusText)")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            speedButton
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
    }

    private var speedButton: some View {
        Menu {
            ForEach(GameSpeed.allCases) { speed in
                Button {
                    settingsStore.settings.speed = speed
                } label: {
                    if settingsStore.settings.speed == speed {
                        Label(speed.displayName, systemImage: "checkmark")
                    } else {
                        Text(speed.displayName)
                    }
                }
            }
        } label: {
            Image(systemName: "gauge.with.needle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(8)
        }
    }

    // MARK: - Table area

    private func tableArea(size: CGSize) -> some View {
        ZStack {
            // Felt.
            RoundedRectangle(cornerRadius: size.width * 0.42, style: .continuous)
                .fill(Theme.tableGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: size.width * 0.42, style: .continuous)
                        .strokeBorder(Theme.rail, lineWidth: 8)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size.width * 0.42, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                        .padding(10)
                )
                .padding(.horizontal, size.width * 0.09)
                .padding(.vertical, size.height * 0.10)

            if let table = game.table {
                // Board and pot.
                VStack(spacing: 8) {
                    BoardView(board: table.board, fourColor: settingsStore.settings.fourColorDeck, cardWidth: min(46, size.width / 8.2))
                    potLabel(table.pot)
                }
                .position(x: size.width * 0.5, y: size.height * 0.50)

                // Winner banner.
                if let banner = game.winnerBanner {
                    Text(banner)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Theme.accent))
                        .position(x: size.width * 0.5, y: size.height * 0.655)
                        .transition(.scale.combined(with: .opacity))
                }

                // Seats.
                ForEach(table.seats) { seat in
                    if !seat.isHero {
                        SeatView(seat: seat, fourColor: settingsStore.settings.fourColorDeck)
                            .position(
                                x: seatAnchors[seat.id].x * size.width,
                                y: seatAnchors[seat.id].y * size.height
                            )
                    }
                    CommittedChipView(amount: seat.committed)
                        .position(
                            x: chipAnchor(for: seat.id).x * size.width,
                            y: chipAnchor(for: seat.id).y * size.height
                        )
                }

                // Hero seat marker (cards render in the bottom area).
                if let hero = table.seats.first(where: { $0.isHero }) {
                    heroBadge(hero)
                        .position(x: size.width * 0.5, y: size.height * 0.90)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: game.table)
    }

    private func potLabel(_ pot: Int) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Theme.accent)
                .frame(width: 9, height: 9)
            Text("Pot \(pot)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.black.opacity(0.45)))
    }

    private func heroBadge(_ hero: SeatUIState) -> some View {
        HStack(spacing: 8) {
            if hero.isButton {
                Text("D")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.black)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.white))
            }
            Text(hero.isAllIn ? "ALL-IN" : "Stack \(hero.stack)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(hero.isAllIn ? Theme.danger : Theme.accent)
                .monospacedDigit()
            if hero.isActing {
                Circle()
                    .fill(Theme.actingRing)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.black.opacity(0.5)))
    }

    // MARK: - Bottom: hero cards + actions

    private var bottomArea: some View {
        VStack(spacing: 10) {
            HStack(alignment: .bottom) {
                // Hero hole cards.
                if let hero = game.table?.seats.first(where: { $0.isHero }),
                   let cards = hero.visibleCards, cards.count == 2 {
                    HStack(spacing: 6) {
                        CardView(card: cards[0], width: 58, fourColor: settingsStore.settings.fourColorDeck)
                        CardView(card: cards[1], width: 58, fourColor: settingsStore.settings.fourColorDeck)
                    }
                    .opacity(hero.hasFolded ? 0.4 : 1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    if let description = game.heroHandDescription {
                        Text(description)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    if let odds = game.potOddsText {
                        Text(odds)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if settingsStore.settings.allowRecommendations && game.heroActions != nil {
                        Button {
                            game.requestAdvice()
                        } label: {
                            Label(game.adviceLoading ? "Thinking…" : "Advice", systemImage: "lightbulb")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.accent)
                        }
                        .disabled(game.adviceLoading)
                    }
                }
            }
            .padding(.horizontal, 16)

            actionOrStatusArea
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
        .frame(height: 190)
        .background(Color.black.opacity(0.25))
    }

    @ViewBuilder
    private var actionOrStatusArea: some View {
        if showBetPanel, let actions = game.heroActions, let options = actions.betRaise, let table = game.table {
            BetSizePanel(
                options: options,
                pot: table.pot,
                callCost: actions.callCost,
                myCommitted: heroCommitted,
                onConfirm: { amount in
                    showBetPanel = false
                    if settingsStore.settings.confirmAllIn && amount == options.maxTo && amount - heroCommitted >= heroStack {
                        confirmingAllInRaise = amount
                    } else {
                        game.submitHeroAction(PlayerAction(kind: options.kind, toAmount: amount))
                    }
                },
                onCancel: { showBetPanel = false }
            )
        } else if let actions = game.heroActions {
            ActionBar(
                actions: actions,
                heroStack: heroStack,
                confirmAllIn: settingsStore.settings.confirmAllIn,
                onAction: { action in
                    game.submitHeroAction(action)
                },
                onOpenBetPanel: { showBetPanel = true }
            )
        } else {
            switch game.phase {
            case .handComplete:
                HStack(spacing: 10) {
                    if settingsStore.settings.showSeedAfterHand, let seed = game.lastSeed {
                        Text("Seed \(seed)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Button {
                        game.startNextHand()
                    } label: {
                        Text("Next hand").riverButton()
                    }
                }
            case .sessionComplete:
                NavigationLink(value: Route.results) {
                    Text("Session results").riverButton()
                }
            default:
                Text("Waiting…")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.vertical, 14)
            }
        }
    }

    private var heroStack: Int {
        return game.table?.seats.first(where: { $0.isHero })?.stack ?? 0
    }

    private var heroCommitted: Int {
        return game.table?.seats.first(where: { $0.isHero })?.committed ?? 0
    }

    // MARK: - Sheets

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
                    dismiss()
                } label: {
                    Label("Save & exit to menu", systemImage: "rectangle.portrait.and.arrow.right")
                }
                Section("Assistance") {
                    Toggle("Hand strength", isOn: $settingsStore.settings.showHandStrength)
                    Toggle("Pot odds", isOn: $settingsStore.settings.showPotOdds)
                    Toggle("Advice button", isOn: $settingsStore.settings.allowRecommendations)
                }
            }
            .navigationTitle("Paused")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    private var adviceSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let advice = game.advice {
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(Theme.accent)
                    Text(recommendationTitle(advice))
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                }
                Text(advice.explanation)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Theme.textPrimary.opacity(0.9))
                HStack(spacing: 16) {
                    statPill("Equity", "\(Int((advice.equity * 100).rounded()))%")
                    if advice.potOdds > 0 {
                        statPill("Needs", "\(Int((advice.potOdds * 100).rounded()))%")
                    }
                }
                Text("Estimates from simulation against unknown hands — a guide, not gospel.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background)
        .presentationDetents([.height(280)])
    }

    private func recommendationTitle(_ advice: Advice) -> String {
        switch advice.kind {
        case .fold: return "Consider folding"
        case .check: return "Check"
        case .call: return "Calling is fine"
        case .bet: return "Bet — around \(advice.toAmount ?? 0)"
        case .raise: return "Raise — to about \(advice.toAmount ?? 0)"
        }
    }

    private func statPill(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Theme.accent)
            Text(label)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.backgroundElevated))
    }
}
