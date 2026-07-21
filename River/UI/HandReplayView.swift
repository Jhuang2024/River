import SwiftUI
import RiverKit

/// Step-by-step replay of a recorded hand with per-decision analysis.
struct HandReplayView: View {
    let history: HandHistory
    @EnvironmentObject var settingsStore: SettingsStore

    @State private var step: Int = -1
    @State private var revealAll = false

    private var replayer: HandReplayer {
        return HandReplayer(history: history)
    }

    private var snapshot: HandReplayer.Snapshot {
        return replayer.snapshot(afterStep: step, revealAll: revealAll || settingsStore.settings.revealFoldedBotCards)
    }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    miniTable
                    transportControls
                    decisionsPanel
                }
                .padding(16)
            }
            .readableColumn()
        }
        .navigationTitle("Hand #\(history.handNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    revealAll.toggle()
                } label: {
                    Image(systemName: revealAll ? "eye.fill" : "eye")
                }
            }
        }
        .onAppear {
            step = history.events.count - 1
        }
    }

    // MARK: - Table snapshot

    private var miniTable: some View {
        let snap = snapshot
        return VStack(spacing: 10) {
            // Board and pot.
            CommunityBoardView(board: snap.board, visibleCount: snap.board.count, deckStyle: settingsStore.settings.deckStyle, cardWidth: 40)
            Text("Pot \(snap.pot)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()

            // Caption of the current step.
            Text(snap.caption)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(settingsStore.accent)
                .multilineTextAlignment(.center)
                .frame(minHeight: 34)

            // Seats.
            VStack(spacing: 6) {
                ForEach(0..<snap.seats.count, id: \.self) { index in
                    seatRow(index: index, seat: snap.seats[index], highlight: snap.lastActor == index)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.feltDark.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07))
                )
        )
    }

    private func seatRow(index: Int, seat: HandReplayer.SeatSnapshot, highlight: Bool) -> some View {
        HStack(spacing: 8) {
            Text(name(index))
                .font(.system(size: 13, weight: index == history.heroSeat ? .bold : .semibold, design: .rounded))
                .foregroundStyle(index == history.heroSeat ? settingsStore.accent : Theme.textPrimary)
                .frame(width: 74, alignment: .leading)
                .lineLimit(1)
            if index == history.buttonIndex {
                Text("D")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(Color.black)
                    .frame(width: 13, height: 13)
                    .background(Circle().fill(Color.white))
            }
            if let cards = seat.holeCards, cards.count == 2 {
                PlayingCardView(card: cards[0], width: 22, style: settingsStore.settings.deckStyle)
                PlayingCardView(card: cards[1], width: 22, style: settingsStore.settings.deckStyle)
            } else if !seat.hasFolded {
                PlayingCardView(card: nil, width: 22, style: settingsStore.settings.deckStyle)
                PlayingCardView(card: nil, width: 22, style: settingsStore.settings.deckStyle)
            }
            Spacer()
            if seat.committedThisStreet > 0 {
                Text("bet \(seat.committedThisStreet)")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Theme.chipCommitted)
                    .monospacedDigit()
            }
            if seat.hasFolded {
                Text("folded")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            } else if seat.isAllIn {
                Text("all-in")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.danger)
            }
            Text("\(seat.stack)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(highlight ? settingsStore.accent.opacity(0.16) : Color.black.opacity(0.25))
        )
        .opacity(seat.hasFolded ? 0.55 : 1)
    }

    private func name(_ index: Int) -> String {
        if history.playerNames.indices.contains(index) {
            return history.playerNames[index]
        }
        return "Seat \(index + 1)"
    }

    // MARK: - Transport

    private var transportControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 18) {
                transportButton("backward.end.fill") { step = -1 }
                transportButton("backward.frame.fill") { step = max(-1, step - 1) }
                Text("\(step + 1) / \(history.events.count)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
                    .frame(width: 74)
                transportButton("forward.frame.fill") { step = min(history.events.count - 1, step + 1) }
                transportButton("forward.end.fill") { step = history.events.count - 1 }
            }
            Slider(
                value: Binding(
                    get: { Double(step + 1) },
                    set: { step = Int($0.rounded()) - 1 }
                ),
                in: 0...Double(max(1, history.events.count))
            )
            .tint(settingsStore.accent)
            if settingsStore.settings.showSeedAfterHand {
                Text("Deck seed \(history.seed)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.backgroundElevated))
    }

    private func transportButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 36, height: 36)
        }
    }

    // MARK: - Decision analysis

    /// Hero decisions paired with their index in the full decision list, so
    /// stored analyses (keyed by decisionIndex) line up.
    private var heroDecisions: [(index: Int, record: DecisionRecord)] {
        var result: [(Int, DecisionRecord)] = []
        for (index, record) in history.decisions.enumerated() where record.seat == history.heroSeat {
            result.append((index, record))
        }
        return result
    }

    private func analysis(forDecisionIndex index: Int) -> DecisionAnalysis? {
        return history.analyses.first { $0.decisionIndex == index }
    }

    private var decisionsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YOUR DECISIONS")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .kerning(1.2)
                .foregroundStyle(Theme.textSecondary)
            if heroDecisions.isEmpty {
                Text("No decisions this hand: you were in the blinds and never had to act.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(heroDecisions, id: \.index) { entry in
                decisionCard(entry.record, analysis: analysis(forDecisionIndex: entry.index))
            }
        }
    }

    private func gradeColor(_ grade: DecisionGrade) -> Color {
        switch grade {
        case .blunder, .significantMistake: return Theme.danger
        case .inaccuracy: return Theme.caution
        case .reasonable, .mixed: return Theme.textSecondary
        case .strong, .excellent: return Theme.positive
        }
    }

    private func decisionCard(_ decision: DecisionRecord, analysis: DecisionAnalysis?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(decision.street.name)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(settingsStore.accent)
                Spacer()
                Text(actionLabel(decision.chosen))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
            }
            // Understated grade indicator (§27 of the UI spec): label plus a
            // thin colour accent, never a celebration.
            if let analysis {
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(gradeColor(analysis.grade))
                        .frame(width: 3, height: 14)
                    Text(analysis.grade.displayName)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(gradeColor(analysis.grade))
                    if analysis.evLossBB > 0.15 {
                        Text("−\(String(format: "%.1f", analysis.evLossBB)) BB est.")
                            .font(.system(size: 11, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Text("Confidence: \(analysis.confidence.displayName)")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Text(decision.handDescription)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary.opacity(0.85))
            HStack(spacing: 12) {
                detail("Pot", "\(decision.potBefore)")
                if decision.toCall > 0 {
                    detail("To call", "\(decision.toCall)")
                    detail("Needed", "\(Int((decision.potOdds * 100).rounded()))%")
                }
                if let equity = analysis?.equity {
                    detail("Est. equity", "\(Int((equity * 100).rounded()))%")
                } else if let strength = decision.annotation?.strengthEstimate {
                    detail("Est. equity", "\(Int((strength * 100).rounded()))%")
                }
            }
            if let analysis {
                Text(analysis.explanation)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if decision.toCall > 0 {
                Text("You were asked to pay \(decision.toCall) into a final pot of \(decision.potBefore + decision.toCall), so you needed about \(Int((decision.potOdds * 100).rounded()))% equity to break even.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.backgroundElevated))
    }

    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func actionLabel(_ action: PlayerAction) -> String {
        switch action.kind {
        case .fold: return "Fold"
        case .check: return "Check"
        case .call: return "Call"
        case .bet: return "Bet \(action.toAmount)"
        case .raise: return "Raise to \(action.toAmount)"
        }
    }
}
