import SwiftUI
import RiverKit

/// Bet sizing panel: slider, quick pot-fraction shortcuts and exact entry.
/// Only legal amounts can be confirmed.
struct BetSizePanel: View {
    let options: BetRaiseOptions
    let pot: Int
    let callCost: Int
    let myCommitted: Int
    let onConfirm: (Int) -> Void
    let onCancel: () -> Void

    @State private var amount: Double = 0
    @State private var textEntry: String = ""
    @FocusState private var textFocused: Bool

    private var intAmount: Int {
        return legalize(Int(amount.rounded()))
    }

    /// Clamp into the legal range; amounts between max and the full minimum
    /// snap to whichever endpoint is closer in spirit (engine rule: any amount
    /// >= minFullTo, or exactly all-in).
    private func legalize(_ value: Int) -> Int {
        var v = max(options.minTo, min(value, options.maxTo))
        if !options.isLegal(toAmount: v) {
            v = v < options.minFullTo ? options.minTo : options.maxTo
        }
        return v
    }

    /// "To" amount that makes this a bet of the given fraction of the pot
    /// (after calling).
    private func potFraction(_ fraction: Double) -> Int {
        let potAfterCall = pot + callCost
        let addition = Double(potAfterCall) * fraction
        return legalize(myCommitted + callCost + Int(addition.rounded()))
    }

    private var verb: String {
        return options.kind == .bet ? "Bet" : "Raise to"
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("\(verb) \(intAmount)")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            if options.maxTo > options.minTo {
                Slider(
                    value: $amount,
                    in: Double(options.minTo)...Double(options.maxTo),
                    step: 1
                )
                .tint(Theme.accent)
            }

            HStack(spacing: 8) {
                quickButton("Min", value: options.minTo)
                quickButton("33%", value: potFraction(0.33))
                quickButton("50%", value: potFraction(0.5))
                quickButton("66%", value: potFraction(0.66))
                quickButton("Pot", value: potFraction(1.0))
                quickButton("All-in", value: options.maxTo, destructive: true)
            }

            HStack(spacing: 10) {
                TextField("Exact", text: $textEntry)
                    .keyboardType(.numberPad)
                    .focused($textFocused)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.backgroundElevated))
                    .frame(width: 110)
                    .onChange(of: textEntry) { _, newValue in
                        if let value = Int(newValue) {
                            amount = Double(legalize(value))
                        }
                    }
                Button {
                    onConfirm(intAmount)
                } label: {
                    Text("\(verb) \(intAmount)")
                        .riverButton()
                }
            }

            Text("Legal: \(options.minTo)–\(options.maxTo)\(options.minFullTo > options.minTo ? " (all-in only below \(options.minFullTo))" : "")")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1))
                )
        )
        .onAppear {
            amount = Double(options.minTo)
        }
    }

    private func quickButton(_ label: String, value: Int, destructive: Bool = false) -> some View {
        Button {
            amount = Double(legalize(value))
            textEntry = ""
            textFocused = false
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(destructive ? Theme.danger : Theme.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 9).fill(Theme.backgroundElevated))
        }
    }
}
