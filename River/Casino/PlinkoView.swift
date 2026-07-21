import SwiftUI
import SpriteKit
import RiverKit

/// SpriteKit board (§4). The scene ONLY animates: every ball's slot and
/// payout are decided by the seeded engine before the ball exists, and the
/// ball follows that exact path — frame rate cannot change any result (§3).
final class PlinkoScene: SKScene {
    private var rows: PlinkoRows = .twelve
    private var pegRadius: CGFloat = 2.6
    private(set) var activeBalls = 0

    func configure(rows: PlinkoRows) {
        self.rows = rows
        rebuild()
    }

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        rebuild()
    }

    private var boardInsetTop: CGFloat { 24 }
    private var boardInsetBottom: CGFloat { 34 }

    private func pegSpacing() -> (dx: CGFloat, dy: CGFloat) {
        let count = CGFloat(rows.rawValue)
        let dx = (size.width - 24) / (count + 1)
        let dy = (size.height - boardInsetTop - boardInsetBottom) / count
        return (dx, dy)
    }

    /// Peg position: row r (0-based) has r+1 pegs, centred.
    private func pegPosition(row: Int, index: Int) -> CGPoint {
        let (dx, dy) = pegSpacing()
        let y = size.height - boardInsetTop - CGFloat(row) * dy
        let width = CGFloat(row) * dx
        let x = size.width / 2 - width / 2 + CGFloat(index) * dx
        return CGPoint(x: x, y: y)
    }

    private func rebuild() {
        removeAllChildren()
        activeBalls = 0
        guard size.width > 0 else { return }
        for row in 0..<rows.rawValue {
            for index in 0...(row) {
                let peg = SKShapeNode(circleOfRadius: pegRadius)
                peg.fillColor = SKColor(white: 0.62, alpha: 0.9)
                peg.strokeColor = .clear
                peg.position = pegPosition(row: row, index: index)
                addChild(peg)
            }
        }
    }

    /// Position of a landing slot centre.
    func slotPosition(_ slot: Int) -> CGPoint {
        let (dx, _) = pegSpacing()
        let width = CGFloat(rows.rawValue) * dx
        let x = size.width / 2 - width / 2 + CGFloat(slot) * dx - dx / 2 + dx / 2
        return CGPoint(x: x, y: boardInsetBottom - 16)
    }

    /// Animates one ball down its predetermined path (§4).
    func animate(drop: PlinkoDrop, ballColor: SKColor, completion: @escaping () -> Void) {
        guard size.width > 0 else {
            completion()
            return
        }
        let ball = SKShapeNode(circleOfRadius: 5)
        ball.fillColor = ballColor
        ball.strokeColor = SKColor(white: 1, alpha: 0.35)
        ball.lineWidth = 0.5
        ball.zPosition = 10
        let start = CGPoint(x: size.width / 2, y: size.height - 6)
        ball.position = start
        addChild(ball)
        activeBalls += 1

        let (dx, _) = pegSpacing()
        var actions: [SKAction] = []
        var offset: CGFloat = 0
        for (row, right) in drop.path.enumerated() {
            offset += right ? dx / 2 : -dx / 2
            let pegY = pegPosition(row: row, index: 0).y
            let target = CGPoint(x: size.width / 2 + offset, y: pegY - 4)
            let fall = SKAction.move(to: target, duration: 0.085)
            fall.timingMode = .easeIn
            // A small lateral settle reads as a bounce without physics risk.
            let settle = SKAction.moveBy(x: right ? 1.5 : -1.5, y: -2, duration: 0.025)
            actions.append(fall)
            actions.append(settle)
        }
        let final = CGPoint(x: size.width / 2 + offset, y: boardInsetBottom - 12)
        let drop2 = SKAction.move(to: final, duration: 0.12)
        drop2.timingMode = .easeIn
        actions.append(drop2)
        actions.append(SKAction.fadeOut(withDuration: 0.18))
        actions.append(SKAction.run { [weak self] in
            self?.activeBalls -= 1
            completion()
        })
        actions.append(SKAction.removeFromParent())
        ball.run(SKAction.sequence(actions))
    }
}

/// Plinko session driver (§4): wagers settle authoritatively the moment a
/// ball is dropped; the scene animation is presentation only.
@MainActor
final class PlinkoViewModel: ObservableObject {
    @Published private(set) var recentMultipliers: [PlinkoDrop] = []
    @Published private(set) var sessionBalls = 0
    @Published private(set) var sessionWagered = 0
    @Published private(set) var sessionReturned = 0
    @Published var wager: Int = 10
    @Published private(set) var autoRunning = false
    @Published var autoPlan = PlinkoAutoDrop()
    @Published var safeguardNotice: SessionSafeguards.Trigger?
    @Published private(set) var lastDrop: PlinkoDrop?

    let scene: PlinkoScene
    private let casino: CasinoStore
    private var autoTask: Task<Void, Never>?
    private var ballIndex = 0
    private let sessionSeed: UInt64

    init(casino: CasinoStore) {
        self.casino = casino
        self.sessionSeed = casino.newRoundSeed()
        let scene = PlinkoScene(size: CGSize(width: 330, height: 380))
        scene.scaleMode = .resizeFill
        self.scene = scene
        scene.configure(rows: casino.settings.plinkoRows)
    }

    var rows: PlinkoRows { casino.settings.plinkoRows }
    var risk: PlinkoRisk { casino.settings.plinkoRisk }
    var bankroll: CasinoBankrollState { casino.bankroll(for: .plinko) }
    var sessionNet: Int { sessionReturned - sessionWagered }

    var multipliers: [Int] {
        return PlinkoTables.multipliers(rows: rows, risk: risk)
    }

    func reconfigure() {
        scene.configure(rows: rows)
    }

    var canDrop: Bool {
        return wager > 0 && casino.canAfford(wager, game: .plinko)
    }

    /// Drops one ball: authoritative outcome now, animation follows (§4).
    @discardableResult
    func dropOne() -> Bool {
        guard canDrop else { return false }
        let seed = PlinkoEngine.ballSeed(sessionSeed: sessionSeed, ballIndex: ballIndex)
        ballIndex += 1
        let drop = PlinkoEngine.drop(rows: rows, risk: risk, wager: wager, seed: seed)

        sessionBalls += 1
        sessionWagered += drop.wager
        sessionReturned += drop.payout
        lastDrop = drop

        let record = CasinoRoundRecord(
            game: .plinko, date: Date(), seed: seed,
            wagered: drop.wager, returned: drop.payout,
            outcomeSummary: "\(drop.multiplierText) · slot \(drop.slot + 1)/\(rows.slotCount)",
            detail: .plinko(.init(rows: rows, risk: risk, slot: drop.slot,
                                  multiplierHundredths: drop.multiplierHundredths, path: drop.path))
        )
        let trigger = casino.complete(round: record)

        let color: SKColor = drop.multiplierHundredths >= 200 ? SKColor(red: 0.30, green: 0.66, blue: 0.44, alpha: 1)
            : (drop.multiplierHundredths >= 100 ? SKColor(red: 0.85, green: 0.66, blue: 0.30, alpha: 1)
               : SKColor(red: 0.80, green: 0.30, blue: 0.27, alpha: 1))
        scene.animate(drop: drop, ballColor: color) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.recentMultipliers.append(drop)
                if self.recentMultipliers.count > 12 {
                    self.recentMultipliers.removeFirst(self.recentMultipliers.count - 12)
                }
            }
        }
        if let trigger {
            stopAuto()
            safeguardNotice = trigger
        }
        return true
    }

    func dropBatch(_ count: Int) {
        startAuto(PlinkoAutoDrop(ballCount: count, wagerPerBall: wager,
                                 delayMillis: 260,
                                 profitTarget: autoPlan.profitTarget,
                                 lossLimit: autoPlan.lossLimit,
                                 bankrollFloor: autoPlan.bankrollFloor))
    }

    func startAuto(_ plan: PlinkoAutoDrop) {
        guard !autoRunning else { return }
        autoRunning = true
        var dropped = 0
        let startNet = sessionNet
        autoTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let stop = plan.shouldStop(
                    ballsDropped: dropped,
                    sessionNet: self.sessionNet - startNet,
                    bankroll: self.bankroll.chips,
                    practiceBankroll: self.bankroll.isPractice
                )
                if stop { break }
                self.wager = plan.wagerPerBall
                guard self.dropOne() else { break }
                dropped += 1
                try? await Task.sleep(nanoseconds: UInt64(max(120, plan.delayMillis)) * 1_000_000)
            }
            self?.autoRunning = false
        }
    }

    /// Immediate stop (§4): no further balls after the current one.
    func stopAuto() {
        autoTask?.cancel()
        autoTask = nil
        autoRunning = false
    }

    /// Called when the screen disappears or the app backgrounds (§4, §15):
    /// auto-drop never continues unattended.
    func endSession() {
        stopAuto()
        casino.notePlinkoSessionEnded(balls: sessionBalls, wagered: sessionWagered, net: sessionNet)
    }

    func acknowledgeSafeguard() {
        safeguardNotice = nil
        casino.beginSession(for: .plinko)
    }
}

/// Plinko screen (§4): board, restrained multiplier slots, drop controls,
/// session numbers, auto-drop with stop conditions.
struct PlinkoView: View {
    @EnvironmentObject var casino: CasinoStore
    @EnvironmentObject var settingsStore: SettingsStore
    @StateObject private var model: PlinkoViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showAutoOptions = false

    init(casino: CasinoStore) {
        _model = StateObject(wrappedValue: PlinkoViewModel(casino: casino))
    }

    private var accent: Color { settingsStore.accent }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            ScrollView {
                VStack(spacing: Theme.Spacing.m) {
                    header
                    board
                    slotStrip
                    recentStrip
                    controls
                }
                .padding(Theme.Spacing.l)
            }
        }
        .navigationTitle("Plinko")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: "plinko-settings") {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        .onDisappear {
            model.endSession()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                model.stopAuto()
            }
        }
        .onChange(of: casino.settings.plinkoRows) { _, _ in
            model.reconfigure()
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

    private var header: some View {
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
                Text("SESSION").sectionHeader()
                Text(model.sessionNet >= 0 ? "+\(model.sessionNet)" : "\(model.sessionNet)")
                    .font(Theme.Fonts.potValue)
                    .monospacedDigit()
                    .foregroundStyle(model.sessionNet > 0 ? Theme.positive : (model.sessionNet < 0 ? Theme.danger : Theme.textPrimary))
                Text("\(model.sessionBalls) balls")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(Theme.Spacing.m)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.backgroundElevated))
    }

    private var board: some View {
        SpriteView(scene: model.scene, options: [.allowsTransparency])
            .frame(height: 360)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .fill(Theme.backgroundElevated.opacity(0.6))
            )
    }

    /// Multiplier slots: green favourable, amber neutral, red poor (§4).
    private var slotStrip: some View {
        HStack(spacing: 2) {
            ForEach(Array(model.multipliers.enumerated()), id: \.offset) { index, multiplier in
                Text(multiplierLabel(multiplier))
                    .font(.system(size: model.multipliers.count > 13 ? 7 : 9, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .frame(height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(slotColor(multiplier).opacity(model.lastDrop?.slot == index ? 1 : 0.55))
                    )
                    .foregroundStyle(Color.black)
            }
        }
    }

    private func multiplierLabel(_ hundredths: Int) -> String {
        if hundredths % 100 == 0 { return "\(hundredths / 100)x" }
        if hundredths % 10 == 0 { return "\(hundredths / 100).\((hundredths % 100) / 10)x" }
        return String(format: "%.2fx", Double(hundredths) / 100)
    }

    private func slotColor(_ hundredths: Int) -> Color {
        if hundredths >= 200 { return Theme.positive }
        if hundredths >= 100 { return Theme.caution }
        return Theme.danger
    }

    @ViewBuilder
    private var recentStrip: some View {
        if !model.recentMultipliers.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(model.recentMultipliers.reversed().enumerated()), id: \.offset) { _, drop in
                        Text(drop.multiplierText)
                            .font(Theme.Fonts.telemetry)
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(slotColor(drop.multiplierHundredths)))
                    }
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: Theme.Spacing.s) {
            HStack {
                Text("Wager")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textSecondary)
                ForEach([1, 5, 10, 25, 100], id: \.self) { amount in
                    Button {
                        model.wager = amount
                    } label: {
                        Text("\(amount)")
                            .font(Theme.Fonts.caption.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(model.wager == amount ? Color.black : Theme.textPrimary)
                            .frame(width: 36, height: 28)
                            .background(Capsule().fill(model.wager == amount ? accent : Theme.backgroundElevated))
                    }
                }
                Spacer()
                Text("\(model.rows.displayName) · \(model.risk.displayName)")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            if model.autoRunning {
                ActionButton(title: "Stop dropping", role: .destructive, accent: accent, identifier: "plinko.stop") {
                    model.stopAuto()
                }
            } else {
                HStack(spacing: Theme.Spacing.s) {
                    ActionButton(title: "Drop", role: .primary, accent: accent, identifier: "plinko.drop") {
                        model.dropOne()
                    }
                    ActionButton(title: "×5", role: .secondary, accent: accent, identifier: "plinko.batch5") {
                        model.dropBatch(5)
                    }
                    ActionButton(title: "×10", role: .secondary, accent: accent, identifier: "plinko.batch10") {
                        model.dropBatch(10)
                    }
                }
                Button {
                    showAutoOptions = true
                } label: {
                    Label("Auto-drop…", systemImage: "infinity")
                        .font(Theme.Fonts.caption.weight(.semibold))
                        .foregroundStyle(accent)
                }
            }
            if let drop = model.lastDrop {
                Text("Fair drop: seed \(drop.seed) → slot \(drop.slot + 1) → \(drop.wager) × \(drop.multiplierText) = \(drop.payout)")
                    .font(Theme.Fonts.telemetry)
                    .foregroundStyle(Theme.textTertiary)
            }
            if !model.bankroll.isPractice && model.bankroll.chips <= 0 {
                ActionButton(title: "Rebuild bankroll (free)", role: .secondary, accent: accent, identifier: "plinko.rebuild") {
                    casino.rebuildCareerBankroll(for: .plinko)
                }
            }
        }
        .sheet(isPresented: $showAutoOptions) {
            autoOptionsSheet
        }
    }

    private var autoOptionsSheet: some View {
        NavigationStack {
            Form {
                Section("Auto-drop") {
                    Stepper("Balls: \(model.autoPlan.ballCount)", value: $model.autoPlan.ballCount, in: 5...200, step: 5)
                    Stepper("Wager per ball: \(model.autoPlan.wagerPerBall)", value: $model.autoPlan.wagerPerBall, in: 1...500, step: 5)
                    Stepper("Delay: \(model.autoPlan.delayMillis) ms", value: $model.autoPlan.delayMillis, in: 150...2000, step: 50)
                }
                Section("Stop conditions") {
                    optionalStepper("Profit target", value: Binding(
                        get: { model.autoPlan.profitTarget ?? 0 },
                        set: { model.autoPlan.profitTarget = $0 == 0 ? nil : $0 }
                    ))
                    optionalStepper("Loss limit", value: Binding(
                        get: { model.autoPlan.lossLimit ?? 0 },
                        set: { model.autoPlan.lossLimit = $0 == 0 ? nil : $0 }
                    ))
                    optionalStepper("Bankroll floor", value: Binding(
                        get: { model.autoPlan.bankrollFloor ?? 0 },
                        set: { model.autoPlan.bankrollFloor = $0 == 0 ? nil : $0 }
                    ))
                    Text("Zero means no limit. Auto-drop always stops when the app leaves the foreground.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button("Start auto-drop") {
                    showAutoOptions = false
                    model.startAuto(model.autoPlan)
                }
            }
            .navigationTitle("Auto-drop")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private func optionalStepper(_ label: String, value: Binding<Int>) -> some View {
        Stepper("\(label): \(value.wrappedValue == 0 ? "off" : "\(value.wrappedValue)")",
                value: value, in: 0...5000, step: 25)
    }
}
