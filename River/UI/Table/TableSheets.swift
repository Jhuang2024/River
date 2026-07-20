import SwiftUI
import RiverKit

// MARK: - Action history (§16)

/// Builds the chronological street-grouped history from the event log.
enum ActionHistoryBuilder {
    struct Line: Identifiable, Equatable {
        let id: Int
        let text: String
    }

    struct HistorySection: Identifiable, Equatable {
        let id: Int
        let title: String
        let lines: [Line]
    }

    static func sections(events: [HandEvent], names: [String], heroSeat: Int) -> [HistorySection] {
        func name(_ seat: Int) -> String {
            if seat == heroSeat { return "You" }
            if names.indices.contains(seat) { return names[seat] }
            return "Seat \(seat + 1)"
        }
        var sections: [HistorySection] = []
        var currentTitle = "Preflop"
        var currentLines: [Line] = []
        var lineID = 0
        var sectionID = 0

        func flush() {
            if !currentLines.isEmpty {
                sections.append(HistorySection(id: sectionID, title: currentTitle, lines: currentLines))
                sectionID += 1
                currentLines = []
            }
        }

        func add(_ text: String) {
            currentLines.append(Line(id: lineID, text: text))
            lineID += 1
        }

        for event in events {
            switch event {
            case .postedAnte(let seat, let amount):
                add("\(name(seat)) posts ante \(amount)")
            case .postedSmallBlind(let seat, let amount):
                add("\(name(seat)) posts small blind \(amount)")
            case .postedBigBlind(let seat, let amount):
                add("\(name(seat)) posts big blind \(amount)")
            case .action(let seat, _, let kind, let added, let toTotal, let isAllIn):
                let suffix = isAllIn ? " (all-in)" : ""
                switch kind {
                case .fold: add("\(name(seat)) folds")
                case .check: add("\(name(seat)) checks")
                case .call: add("\(name(seat)) calls \(added)\(suffix)")
                case .bet: add("\(name(seat)) bets \(toTotal)\(suffix)")
                case .raise: add("\(name(seat)) raises to \(toTotal)\(suffix)")
                }
            case .dealtBoard(let street, let cards):
                flush()
                currentTitle = "\(street.name) — \(cards.map { $0.description }.joined(separator: " "))"
            case .refundedUncalledBet(let seat, let amount):
                add("\(name(seat)) takes back \(amount)")
            case .wonWithoutShowdown(let seat, let amount):
                add("\(name(seat)) wins \(amount)")
            case .showedHand(let seat, let cards, let value):
                add("\(name(seat)) shows \(cards.map { $0.description }.joined(separator: " ")) — \(value)")
            case .wonPot(let seat, let amount, let potIndex, _):
                add("\(name(seat)) wins \(amount)\(potIndex > 0 ? " (side pot)" : "")")
            default:
                break
            }
        }
        flush()
        return sections
    }
}

struct ActionHistorySheet: View {
    let sections: [ActionHistoryBuilder.HistorySection]

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections) { section in
                    Section(section.title) {
                        ForEach(section.lines) { line in
                            Text(line.text)
                                .font(Theme.Fonts.body)
                                .monospacedDigit()
                                .foregroundStyle(Theme.textPrimary)
                                .listRowBackground(Theme.backgroundElevated)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Hand so far")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Hint sheet (§17 Level 2, §18)

struct HintSheet: View {
    let advice: Advice
    var accent: Color

    /// Honest confidence from the equity-to-price gap: close decisions say so.
    private var confidence: String {
        if advice.potOdds > 0 {
            let gap = abs(advice.equity - advice.potOdds)
            if gap < 0.05 { return "Close decision" }
            if gap < 0.14 { return "Moderate" }
            return "High"
        }
        return advice.equity > 0.6 || advice.equity < 0.35 ? "High" : "Moderate"
    }

    private var alternative: String? {
        if advice.potOdds > 0 && abs(advice.equity - advice.potOdds) < 0.05 {
            return advice.kind == .fold ? "Call" : "Fold"
        }
        if advice.kind == .raise { return "Call" }
        if advice.kind == .bet { return "Check" }
        return nil
    }

    private var title: String {
        switch advice.kind {
        case .fold: return "Fold"
        case .check: return "Check"
        case .call: return "Call"
        case .bet: return "Bet — around \(advice.toAmount ?? 0)"
        case .raise: return "Raise — to about \(advice.toAmount ?? 0)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(accent)
                Text(title)
                    .font(Theme.Fonts.screenTitle)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
            }
            HStack(spacing: Theme.Spacing.l) {
                labelled("Confidence", confidence)
                if let alternative {
                    labelled("Alternative", alternative)
                }
            }
            Text(advice.explanation)
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.textPrimary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Theme.Spacing.l) {
                statPill("Equity", "\(Int((advice.equity * 100).rounded()))%")
                if advice.potOdds > 0 {
                    statPill("Needs", "\(Int((advice.potOdds * 100).rounded()))%")
                }
            }
            Text("Estimates come from simulation against unknown hands — a guide, not gospel.")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background)
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
    }

    private func labelled(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased()).sectionHeader()
            Text(value)
                .font(Theme.Fonts.secondaryAction)
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private func statPill(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Theme.Fonts.potValue)
                .monospacedDigit()
                .foregroundStyle(accent)
            Text(label)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.backgroundElevated))
    }
}

// MARK: - Opponent read (§19)

/// Only observed or publicly-known information — never hidden AI parameters.
struct OpponentRead: Identifiable, Equatable {
    let id: Int
    let name: String
    let symbolName: String
    let archetypeName: String
    let note: String
    let handsObserved: Int
    let vpipPercent: Double
    let pfrPercent: Double
    let showdownsSeen: Int
}

struct OpponentReadSheet: View {
    let read: OpponentRead

    private var confidence: String {
        if read.handsObserved < 15 { return "Low — small sample" }
        if read.handsObserved < 50 { return "Moderate" }
        return "Good"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            HStack(spacing: Theme.Spacing.m) {
                ZStack {
                    Circle().fill(Theme.backgroundElevated).frame(width: 46, height: 46)
                    Image(systemName: read.symbolName)
                        .font(.system(size: 19))
                        .foregroundStyle(Theme.textSecondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(read.name)
                        .font(Theme.Fonts.screenTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text(read.archetypeName)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }
            Text(read.note)
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.textPrimary.opacity(0.85))
            if read.handsObserved > 0 {
                HStack(spacing: Theme.Spacing.xl) {
                    metric("VPIP", String(format: "%.0f%%", read.vpipPercent))
                    metric("PFR", String(format: "%.0f%%", read.pfrPercent))
                    metric("Showdowns", "\(read.showdownsSeen)")
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("SAMPLE").sectionHeader()
                Text("\(read.handsObserved) hands · Confidence: \(confidence)")
                    .font(Theme.Fonts.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background)
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Theme.Fonts.potValue)
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

// MARK: - Pot breakdown (§10)

struct PotBreakdownEntry: Identifiable, Equatable {
    let id: Int
    let title: String
    let amount: Int
    let eligibleNames: [String]
}

struct PotBreakdownSheet: View {
    let entries: [PotBreakdownEntry]
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Text("Pot — \(total)")
                .font(Theme.Fonts.screenTitle)
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(entry.title)
                            .font(Theme.Fonts.secondaryAction)
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text("\(entry.amount)")
                            .font(Theme.Fonts.potValue)
                            .monospacedDigit()
                            .foregroundStyle(Theme.metallic)
                    }
                    Text("Eligible: \(entry.eligibleNames.joined(separator: ", "))")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(Theme.Spacing.m)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.control).fill(Theme.backgroundElevated))
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background)
        .presentationDetents([.height(min(420, CGFloat(140 + entries.count * 80)))])
        .presentationDragIndicator(.visible)
    }
}
