import SwiftUI
import RiverKit

/// Bet-sizing panel (§13): exact target, chips added, pot percentage,
/// remaining stack, integer-snapping slider, numeric entry, and presets that
/// adapt to the street and context. Only legal amounts can be confirmed; the
/// table (and hero cards) stay visible above.
struct BetSizingSheet: View {
    let options: BetRaiseOptions
    let pot: Int
    let callCost: Int
    let myCommitted: Int
    let myStack: Int
    let bigBlind: Int
    let currentBet: Int
    let street: Street
    var accent: Color
    let onConfirm: (Int) -> Void
    let onCancel: () -> Void

    @State private var amount: Double = 0
    @State private var textEntry: String = ""
    @FocusState private var textFocused: Bool

    private var intAmount: Int {
        return legalize(Int(amount.rounded()))
    }

    /// Clamp into the legal range: any amount >= the full minimum, or exactly
    /// all-in. Values in the dead zone snap to the nearest legal endpoint.
    private func legalize(_ value: Int) -> Int {
        var v = max(options.minTo, min(value, options.maxTo))
        if !options.isLegal(toAmount: v) {
            v = v < options.minFullTo ? options.minTo : options.maxTo
        }
        return v
    }

    private struct Preset: Identifiable {
        let id: String
        let label: String
        let amount: Int
        var destructive: Bool = false
    }

    /// "To" amount for a bet of the given fraction of the pot after calling.
    private func potFraction(_ fraction: Double) -> Int {
        let potAfterCall = pot + callCost
        return legalize(myCommitted + callCost + Int((Double(potAfterCall) * fraction).rounded()))
    }

    /// Context-adaptive presets (§13), deduplicated by resulting amount.
    private var presets: [Preset] {
        var raw: [Preset] = [Preset(id: "min", label: "Min", amount: options.minTo)]
        if street == .preflop && currentBet <= bigBlind {
            // Opening raise: big-blind multiples.
            raw.append(Preset(id: "2x", label: "2×", amount: legalize(bigBlind * 2)))
            raw.append(Preset(id: "2.5x", label: "2.5×", amount: legalize(Int((Double(bigBlind) * 2.5).rounded()))))
            raw.append(Preset(id: "3x", label: "3×", amount: legalize(bigBlind * 3)))
            raw.append(Preset(id: "pot", label: "Pot", amount: potFraction(1.0)))
        } else if street == .preflop {
            // Three-bet and beyond: multiples of the current raise.
            raw.append(Preset(id: "2.2x", label: "2.2×", amount: legalize(Int((Double(currentBet) * 2.2).rounded()))))
            raw.append(Preset(id: "3x", label: "3×", amount: legalize(currentBet * 3)))
            raw.append(Preset(id: "pot", label: "Pot", amount: potFraction(1.0)))
        } else {
            raw.append(Preset(id: "33", label: "33%", amount: potFraction(0.33)))
            raw.append(Preset(id: "50", label: "50%", amount: potFraction(0.5)))
            raw.append(Preset(id: "66", label: "66%", amount: potFraction(0.66)))
            raw.append(Preset(id: "75", label: "75%", amount: potFraction(0.75)))
            raw.append(Preset(id: "pot", label: "Pot", amount: potFraction(1.0)))
        }
        raw.append(Preset(id: "allin", label: "All-in", amount: options.maxTo, destructive: true))
        // Drop presets that collapse onto an earlier amount (short stacks).
        var seen = Set<Int>()
        var result: [Preset] = []
        for preset in raw {
            if seen.insert(preset.amount).inserted || preset.id == "allin" {
                if preset.id == "allin" && result.contains(where: { $0.amount == preset.amount && $0.id != "allin" }) {
                    result.removeAll { $0.amount == preset.amount && $0.id != "allin" }
                }
                result.append(preset)
            }
        }
        return result
    }

    private var verb: String {
        return options.kind == .bet ? "Bet" : "Raise to"
    }

    private var chipsAdded: Int {
        return intAmount - myCommitted
    }

    private var potPercent: Int {
        let base = pot + callCost
        guard base > 0 else { return 0 }
        let extra = chipsAdded - callCost
        return max(0, Int((Double(extra) / Double(base) * 100).rounded()))
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            // Header: target and live telemetry.
            HStack(alignment: .firstTextBaseline) {
                Text("\(verb) \(intAmount)")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.textSecondary)
                }
                .accessibilityIdentifier("bet.cancel")
            }
            HStack(spacing: Theme.Spacing.l) {
                telemetry("Adds", "\(chipsAdded)")
                telemetry("Pot", "\(potPercent)%")
                telemetry("Behind", "\(max(0, myStack - chipsAdded))")
                Spacer()
                Text("\(options.minTo)–\(options.maxTo)")
                    .font(Theme.Fonts.telemetry)
                    .foregroundStyle(Theme.textTertiary)
            }

            if options.maxTo > options.minTo {
                Slider(
                    value: $amount,
                    in: Double(options.minTo)...Double(options.maxTo),
                    step: 1
                )
                .tint(accent)
                .accessibilityIdentifier("bet.slider")
            }

            HStack(spacing: 6) {
                ForEach(presets) { preset in
                    presetButton(preset)
                }
            }

            HStack(spacing: Theme.Spacing.m) {
                TextField("Exact", text: $textEntry)
                    .keyboardType(.numberPad)
                    .focused($textFocused)
                    .font(Theme.Fonts.body)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.backgroundElevated))
                    .frame(width: 100)
                    .accessibilityIdentifier("bet.exact")
                    .onChange(of: textEntry) { _, newValue in
                        if let value = Int(newValue) {
                            amount = Double(legalize(value))
                        }
                    }
                ActionButton(
                    title: "\(verb) \(intAmount)",
                    role: .primary,
                    accent: accent,
                    identifier: "bet.confirm"
                ) {
                    onConfirm(intAmount)
                }
            }
        }
        .padding(Theme.Spacing.l)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sheet, style: .continuous)
                .fill(Color.black.opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.sheet, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1))
                )
        )
        .onAppear {
            amount = Double(options.minTo)
        }
    }

    private func telemetry(_ label: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(Theme.Fonts.telemetry)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func presetButton(_ preset: Preset) -> some View {
        Button {
            amount = Double(preset.amount)
            textEntry = ""
            textFocused = false
        } label: {
            Text(preset.label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(preset.destructive ? Theme.danger : Theme.textPrimary)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(intAmount == preset.amount ? Color.white.opacity(0.14) : Theme.backgroundElevated)
                )
        }
        .accessibilityIdentifier("bet.preset.\(preset.id)")
    }
}
