import SwiftUI
import RiverKit

/// The hero's primary action row: Fold | Check/Call | Bet/Raise.
/// Fold sits apart on the left so it cannot be fat-fingered.
struct ActionBar: View {
    let actions: AvailableActions
    let heroStack: Int
    let confirmAllIn: Bool
    let onAction: (PlayerAction) -> Void
    let onOpenBetPanel: () -> Void

    @State private var confirmingAllInCall = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                onAction(.fold)
            } label: {
                Text("Fold")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Theme.danger)
                    .padding(.vertical, 14)
                    .frame(width: 86)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Theme.backgroundElevated)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Theme.danger.opacity(0.4))
                            )
                    )
            }

            Spacer(minLength: 14)

            if actions.canCheck {
                Button {
                    onAction(.check)
                } label: {
                    Text("Check").riverButton(prominent: false)
                }
            } else if actions.canCall {
                Button {
                    if confirmAllIn && actions.callCost >= heroStack {
                        confirmingAllInCall = true
                    } else {
                        onAction(.call)
                    }
                } label: {
                    Text(actions.callCost >= heroStack ? "Call \(actions.callCost) (all-in)" : "Call \(actions.callCost)")
                        .riverButton(prominent: false)
                }
            }

            if actions.betRaise != nil {
                Button {
                    onOpenBetPanel()
                } label: {
                    Text(actions.betRaise?.kind == .bet ? "Bet" : "Raise")
                        .riverButton()
                }
            }
        }
        .confirmationDialog("Call all-in for \(actions.callCost)?", isPresented: $confirmingAllInCall, titleVisibility: .visible) {
            Button("Call all-in", role: .destructive) {
                onAction(.call)
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
