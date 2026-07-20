import SwiftUI
import RiverKit

/// Contextual action row (§11): only currently-legal actions, amounts in the
/// labels, Fold spatially separated (§12), left-handed mirroring (§43).
struct ActionBar: View {
    let actions: AvailableActions
    var accent: Color
    var leftHanded: Bool
    /// Fold requests route through the caller so Protect Strong Hands can
    /// intercept them; the bar itself never applies actions.
    let onFold: () -> Void
    let onCheck: () -> Void
    let onCall: () -> Void
    let onOpenBetSheet: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            if leftHanded {
                aggressive
                passive
                Spacer(minLength: Theme.Spacing.l)
                foldButton.frame(width: 84)
            } else {
                foldButton.frame(width: 84)
                Spacer(minLength: Theme.Spacing.l)
                passive
                aggressive
            }
        }
    }

    @ViewBuilder
    private var foldButton: some View {
        ActionButton(title: "Fold", role: .destructive, accent: accent, identifier: "action.fold", action: onFold)
    }

    @ViewBuilder
    private var passive: some View {
        if actions.canCheck {
            ActionButton(title: "Check", role: .secondary, accent: accent, identifier: "action.check", action: onCheck)
        } else if actions.canCall {
            ActionButton(
                title: "Call \(actions.callCost)",
                subtitle: actions.isCallAllIn ? "All-in" : nil,
                role: .secondary,
                accent: accent,
                identifier: "action.call",
                action: onCall
            )
        }
    }

    @ViewBuilder
    private var aggressive: some View {
        if let options = actions.betRaise {
            ActionButton(
                title: options.kind == .bet ? "Bet" : "Raise",
                role: .primary,
                accent: accent,
                identifier: "action.betraise",
                action: onOpenBetSheet
            )
        }
    }
}

/// Optional decision timer (§24): thin progress bar over the action area.
struct DecisionTimerView: View {
    /// Remaining fraction, 1...0.
    let fraction: Double
    var accent: Color

    private var color: Color {
        if fraction < 0.2 { return Theme.danger }
        if fraction < 0.45 { return Theme.caution }
        return accent
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(color)
                    .frame(width: max(0, proxy.size.width * fraction))
            }
        }
        .frame(height: 3)
        .animation(.linear(duration: 0.2), value: fraction)
        .accessibilityHidden(true)
    }
}
