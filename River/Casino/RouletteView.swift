import SwiftUI
import RiverKit

/// Roulette round flow (§5): build validated bets, spin with a seeded
/// authoritative result, animate the wheel to that exact pocket, settle in
/// exact integers, remember previous bets for repeat/double.
@MainActor
final class RouletteViewModel: ObservableObject {
    @Published private(set) var bets: [RouletteBet] = []
    @Published private(set) var previousBets: [RouletteBet] = []
    @Published private(set) var lastResult: RouletteSpinResult?
    @Published private(set) var recentPockets: [Int] = []
    @Published private(set) var isSpinning = false
    @Published var wheelAngle: Double = 0
    @Published var pendingSplitFirst: Int?
    @Published var safeguardNotice: SessionSafeguards.Trigger?
    @Published var placementNote: String?

    private let casino: CasinoStore
    private static let saveFile = "casino-roulette-bets"

    init(casino: CasinoStore) {
        self.casino = casino
        if let saved = casino.store.load(SavedState.self, from: Self.saveFile) {
            bets = saved.bets
            previousBets = saved.previousBets
            recentPockets = saved.recentPockets
        }
    }

    private struct SavedState: Codable {
        var bets: [RouletteBet]
        var previousBets: [RouletteBet]
        var recentPockets: [Int]
    }

    private func persist() {
        try? casino.store.save(SavedState(bets: bets, previousBets: previousBets, recentPockets: recentPockets),
                               as: Self.saveFile)
    }

    var wheel: RouletteWheel { casino.settings.rouletteWheel }
    var chip: Int { casino.settings.chipDenomination }
    var bankroll: CasinoBankrollState { casino.bankroll(for: .roulette) }
    var totalWager: Int { bets.reduce(0) { $0 + $1.amount } }

    // MARK: - Bet building (§5)

    private func add(_ bet: RouletteBet) {
        guard !isSpinning else { return }
        if let problem = RouletteLayout.validate(bet, wheel: wheel) {
            placementNote = problem
            return
        }
        guard casino.canAfford(totalWager + bet.amount, game: .roulette) else {
            placementNote = "That bet would exceed your bankroll."
            return
        }
        placementNote = nil
        // Merge with an identical existing placement.
        if let index = bets.firstIndex(where: { $0.kind == bet.kind && $0.numbers == bet.numbers }) {
            bets[index].amount += bet.amount
        } else {
            bets.append(bet)
        }
        persist()
    }

    func tapNumber(_ number: Int, mode: PlacementMode) {
        switch mode {
        case .straight:
            add(RouletteBet(kind: .straightUp, numbers: [number], amount: chip))
        case .split:
            if let first = pendingSplitFirst {
                pendingSplitFirst = nil
                add(RouletteBet(kind: .split, numbers: [first, number], amount: chip))
            } else {
                pendingSplitFirst = number
                placementNote = "Now tap an adjacent number to finish the split."
            }
        case .street:
            guard let position = streetContaining(number) else {
                placementNote = "Streets cover a row of three numbers."
                return
            }
            add(RouletteBet(kind: .street, numbers: position, amount: chip))
        case .corner:
            // The tapped number is the corner's top-left.
            add(RouletteBet(kind: .corner, numbers: [number, number + 1, number + 3, number + 4], amount: chip))
        case .sixLine:
            guard let street = streetContaining(number), let low = street.min(), low + 5 <= 36 else {
                placementNote = "Six lines cover two adjacent rows."
                return
            }
            add(RouletteBet(kind: .sixLine, numbers: Set(low...(low + 5)), amount: chip))
        }
    }

    private func streetContaining(_ number: Int) -> Set<Int>? {
        guard (1...36).contains(number) else { return nil }
        let row = (number - 1) / 3
        return [row * 3 + 1, row * 3 + 2, row * 3 + 3]
    }

    func placeOutside(_ kind: RouletteBetKind) {
        guard let bet = RouletteLayout.outsideBet(kind, amount: chip) else { return }
        add(bet)
    }

    func placeDozen(_ index: Int) {
        add(RouletteBet(kind: .dozen, numbers: RouletteLayout.dozens[index], amount: chip))
    }

    func placeColumn(_ index: Int) {
        add(RouletteBet(kind: .column, numbers: RouletteLayout.columns[index], amount: chip))
    }

    func removeBet(_ bet: RouletteBet) {
        guard !isSpinning else { return }
        bets.removeAll { $0.id == bet.id }
        persist()
    }

    func undoLastBet() {
        guard !isSpinning, !bets.isEmpty else { return }
        if bets[bets.count - 1].amount > chip {
            bets[bets.count - 1].amount -= chip
        } else {
            bets.removeLast()
        }
        persist()
    }

    func clearBets() {
        guard !isSpinning else { return }
        bets.removeAll()
        pendingSplitFirst = nil
        persist()
    }

    func repeatPrevious(doubled: Bool) {
        guard !isSpinning, !previousBets.isEmpty else { return }
        let factor = doubled ? 2 : 1
        let candidate = previousBets.map { bet -> RouletteBet in
            RouletteBet(kind: bet.kind, numbers: bet.numbers, amount: bet.amount * factor)
        }
        let total = candidate.reduce(0) { $0 + $1.amount }
        guard casino.canAfford(total, game: .roulette) else {
            placementNote = "Repeating those bets would exceed your bankroll."
            return
        }
        bets = candidate
        persist()
    }

    /// Payout preview when inspecting a bet (§5).
    func possibleReturn(of bet: RouletteBet) -> Int {
        return bet.amount * (bet.kind.payoutOdds + 1)
    }

    // MARK: - Spinning (§5)

    var canSpin: Bool {
        return !isSpinning && !bets.isEmpty && casino.canAfford(totalWager, game: .roulette)
    }

    func spin() {
        guard canSpin else { return }
        let seed = casino.newRoundSeed()
        // Authoritative result FIRST; the animation merely lands on it (§3).
        guard let result = try? RouletteEngine.spin(wheel: wheel, bets: bets, seed: seed) else { return }
        isSpinning = true
        pendingSplitFirst = nil

        // Rotate several turns and stop with the winning pocket at the top
        // pointer. Duration is fixed; frame rate cannot alter the result.
        let pocketCount = wheel.pocketOrder.count
        let pocketAngle = 360.0 / Double(pocketCount)
        let target = 5 * 360 + (360 - Double(result.wheelIndex) * pocketAngle)
        withAnimation(.timingCurve(0.16, 0.9, 0.32, 1.0, duration: 3.4)) {
            wheelAngle += target - wheelAngle.truncatingRemainder(dividingBy: 360)
        }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            self?.completeSpin(result)
        }
    }

    private func completeSpin(_ result: RouletteSpinResult) {
        lastResult = result
        recentPockets.append(result.pocket)
        if recentPockets.count > 20 { recentPockets.removeFirst(recentPockets.count - 20) }
        previousBets = bets
        bets = []
        isSpinning = false

        let record = CasinoRoundRecord(
            game: .roulette, date: Date(), seed: result.seed,
            wagered: result.totalStaked, returned: result.totalReturned,
            outcomeSummary: "\(result.pocketLabel) \(result.color.rawValue)",
            detail: .roulette(.init(wheel: result.wheel, pocket: result.pocket, bets: result.betResults))
        )
        safeguardNotice = casino.complete(round: record)
        persist()
    }

    func acknowledgeSafeguard() {
        safeguardNotice = nil
        casino.beginSession(for: .roulette)
    }

    enum PlacementMode: String, CaseIterable, Identifiable {
        case straight, split, street, corner, sixLine
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .straight: return "Straight"
            case .split: return "Split"
            case .street: return "Street"
            case .corner: return "Corner"
            case .sixLine: return "Six line"
            }
        }
    }
}

/// Portrait roulette (§5): compact wheel up top, readable betting grid,
/// chips near the thumb, honest house-edge labeling.
struct RouletteView: View {
    @EnvironmentObject var casino: CasinoStore
    @EnvironmentObject var settingsStore: SettingsStore
    @StateObject private var model: RouletteViewModel
    @State private var placementMode: RouletteViewModel.PlacementMode = .straight

    init(casino: CasinoStore) {
        _model = StateObject(wrappedValue: RouletteViewModel(casino: casino))
    }

    private var accent: Color { settingsStore.accent }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            ScrollView {
                VStack(spacing: Theme.Spacing.l) {
                    wheelView
                    historyStrip
                    if let result = model.lastResult {
                        resultCard(result)
                    }
                    bettingTable
                    betList
                    controls
                }
                .padding(Theme.Spacing.l)
            }
        }
        .navigationTitle("Roulette")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: "roulette-settings") {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        .alert(item: Binding(
            get: { model.safeguardNotice.map { Notice(trigger: $0) } },
            set: { _ in }
        )) { notice in
            Alert(
                title: Text("Session limit reached"),
                message: Text(notice.trigger.message + " Start a new session whenever you like."),
                dismissButton: .default(Text("OK")) { model.acknowledgeSafeguard() }
            )
        }
    }

    private struct Notice: Identifiable {
        let trigger: SessionSafeguards.Trigger
        var id: String { trigger.rawValue }
    }

    // MARK: - Wheel

    private var wheelView: some View {
        VStack(spacing: Theme.Spacing.s) {
            ZStack {
                wheelFace
                    .rotationEffect(.degrees(model.wheelAngle))
                Triangle()
                    .fill(Theme.metallic)
                    .frame(width: 14, height: 12)
                    .offset(y: -78)
            }
            .frame(width: 170, height: 170)
            Text(model.wheel.houseEdgeDescription)
                .font(Theme.Fonts.caption)
                .foregroundStyle(model.wheel == .american ? Theme.caution : Theme.textTertiary)
        }
    }

    private var wheelFace: some View {
        let order = model.wheel.pocketOrder
        let slice = 360.0 / Double(order.count)
        return ZStack {
            Circle().fill(Theme.rail)
            ForEach(Array(order.enumerated()), id: \.offset) { index, pocket in
                let angle = Double(index) * slice
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(pocketColor(pocket))
                        .frame(width: 10, height: 26)
                    Text(RoulettePocket.label(pocket))
                        .font(.system(size: 7, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                }
                .frame(height: 160)
                .rotationEffect(.degrees(angle))
            }
            Circle()
                .fill(Theme.backgroundElevated)
                .frame(width: 74, height: 74)
            if let result = model.lastResult, !model.isSpinning {
                Text(result.pocketLabel)
                    .font(Theme.Fonts.screenTitle)
                    .monospacedDigit()
                    .foregroundStyle(pocketColor(result.pocket))
            }
        }
    }

    private func pocketColor(_ pocket: Int) -> Color {
        switch RoulettePocket.color(pocket) {
        case .red: return Theme.danger
        case .black: return Color(white: 0.25)
        case .green: return Theme.positive
        }
    }

    private struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.closeSubpath()
            return path
        }
    }

    // MARK: - History (§5)

    @ViewBuilder
    private var historyStrip: some View {
        if !model.recentPockets.isEmpty {
            VStack(spacing: 4) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(model.recentPockets.reversed().enumerated()), id: \.offset) { _, pocket in
                            Text(RoulettePocket.label(pocket))
                                .font(Theme.Fonts.telemetry)
                                .foregroundStyle(Color.white)
                                .frame(width: 28, height: 22)
                                .background(RoundedRectangle(cornerRadius: 5).fill(pocketColor(pocket)))
                        }
                    }
                }
                Text("Each spin is independent.")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func resultCard(_ result: RouletteSpinResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(result.net >= 0 ? "+\(result.net)" : "\(result.net)")
                .font(Theme.Fonts.screenTitle)
                .monospacedDigit()
                .foregroundStyle(result.net > 0 ? Theme.positive : (result.net < 0 ? Theme.danger : Theme.textPrimary))
            ForEach(Array(result.betResults.enumerated()), id: \.offset) { _, betResult in
                Text("\(betResult.bet.label) · \(betResult.bet.amount): \(betResult.won ? "returned \(betResult.returned)" : "lost")")
                    .font(Theme.Fonts.caption)
                    .monospacedDigit()
                    .foregroundStyle(betResult.won ? Theme.positive : Theme.textSecondary)
            }
            Text("Fair spin: seed \(result.seed)")
                .font(Theme.Fonts.telemetry)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.backgroundElevated))
    }

    // MARK: - Betting table (§5)

    private var bettingTable: some View {
        VStack(spacing: Theme.Spacing.s) {
            Picker("Bet type", selection: $placementMode) {
                ForEach(RouletteViewModel.PlacementMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            if let note = model.placementNote {
                Text(note)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.caution)
            }
            zeroRow
            numberGrid
            dozensAndColumns
            outsideRow
        }
    }

    private var zeroRow: some View {
        HStack(spacing: 3) {
            numberCell(0)
            if model.wheel == .american {
                numberCell(RoulettePocket.doubleZero)
            }
        }
    }

    private var numberGrid: some View {
        VStack(spacing: 3) {
            ForEach(0..<12, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { column in
                        numberCell(row * 3 + column + 1)
                    }
                }
            }
        }
    }

    private func numberCell(_ number: Int) -> some View {
        let staked = model.bets.filter { $0.numbers.contains(number) }.reduce(0) { $0 + $1.amount }
        let isPendingSplit = model.pendingSplitFirst == number
        return Button {
            if number == 0 || number == RoulettePocket.doubleZero {
                model.tapNumber(number, mode: .straight)
            } else {
                model.tapNumber(number, mode: placementMode)
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(pocketColor(number).opacity(0.82))
                VStack(spacing: 1) {
                    Text(RoulettePocket.label(number))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.white)
                    if staked > 0 {
                        Text("\(staked)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Theme.chipColor(for: settingsStore.settings.chipStyle).opacity(0.95)))
                    }
                }
            }
            .frame(height: 40)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isPendingSplit ? accent : Color.white.opacity(0.15),
                                  lineWidth: isPendingSplit ? 2 : 0.5)
            )
        }
        .disabled(model.isSpinning)
    }

    private var dozensAndColumns: some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                outsideCell("1st 12") { model.placeDozen(0) }
                outsideCell("2nd 12") { model.placeDozen(1) }
                outsideCell("3rd 12") { model.placeDozen(2) }
            }
            HStack(spacing: 3) {
                outsideCell("Col 1") { model.placeColumn(0) }
                outsideCell("Col 2") { model.placeColumn(1) }
                outsideCell("Col 3") { model.placeColumn(2) }
            }
        }
    }

    private var outsideRow: some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                outsideCell("1-18") { model.placeOutside(.low) }
                outsideCell("Even") { model.placeOutside(.even) }
                outsideCell("Red", tint: Theme.danger) { model.placeOutside(.red) }
            }
            HStack(spacing: 3) {
                outsideCell("Black", tint: Color(white: 0.25)) { model.placeOutside(.black) }
                outsideCell("Odd") { model.placeOutside(.odd) }
                outsideCell("19-36") { model.placeOutside(.high) }
            }
        }
    }

    private func outsideCell(_ label: String, tint: Color = Theme.backgroundElevated, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Theme.Fonts.secondaryAction)
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(RoundedRectangle(cornerRadius: 6).fill(tint.opacity(0.85)))
        }
        .disabled(model.isSpinning)
    }

    // MARK: - Bets and spin controls

    @ViewBuilder
    private var betList: some View {
        if !model.bets.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(model.bets) { bet in
                    HStack {
                        Text("\(bet.label) · \(bet.amount)")
                            .font(Theme.Fonts.caption)
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text("pays \(model.possibleReturn(of: bet))")
                            .font(Theme.Fonts.caption)
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                        Button {
                            model.removeBet(bet)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
            }
            .padding(Theme.Spacing.m)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.backgroundElevated.opacity(0.6)))
        }
    }

    private var controls: some View {
        VStack(spacing: Theme.Spacing.s) {
            HStack {
                Text("Chip")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textSecondary)
                ForEach([1, 5, 10, 25, 100], id: \.self) { amount in
                    Button {
                        casino.settings.chipDenomination = amount
                    } label: {
                        Text("\(amount)")
                            .font(Theme.Fonts.caption.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(casino.settings.chipDenomination == amount ? Color.black : Theme.textPrimary)
                            .frame(width: 36, height: 28)
                            .background(Capsule().fill(casino.settings.chipDenomination == amount ? accent : Theme.backgroundElevated))
                    }
                }
                Spacer()
            }
            HStack {
                Text("Wager \(model.totalWager)")
                    .font(Theme.Fonts.stackValue)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(model.bankroll.isPractice ? "Practice ∞" : "Bankroll \(model.bankroll.chips)")
                    .font(Theme.Fonts.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: Theme.Spacing.s) {
                Button("Undo") { model.undoLastBet() }
                Button("Clear") { model.clearBets() }
                Button("Repeat") { model.repeatPrevious(doubled: false) }
                Button("Double") { model.repeatPrevious(doubled: true) }
            }
            .font(Theme.Fonts.caption.weight(.semibold))
            .foregroundStyle(accent)
            ActionButton(title: model.isSpinning ? "Spinning…" : "Spin", role: .primary, accent: accent, identifier: "roulette.spin") {
                model.spin()
            }
            .disabled(!model.canSpin)
            .opacity(model.canSpin ? 1 : 0.5)
            if !model.bankroll.isPractice && model.bankroll.chips <= 0 {
                ActionButton(title: "Rebuild bankroll (free)", role: .secondary, accent: accent, identifier: "roulette.rebuild") {
                    casino.rebuildCareerBankroll(for: .roulette)
                }
            }
        }
    }
}
