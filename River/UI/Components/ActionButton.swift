import SwiftUI

/// Shared action button (§45): explicit role, amount-bearing label, large
/// thumb target. Never mutates game state itself.
struct ActionButton: View {
    enum Role {
        case primary        // strongest action (bet / raise / confirm)
        case secondary      // check / call
        case destructive    // fold
        case quiet          // tertiary controls
    }

    let title: String
    var subtitle: String? = nil
    var role: Role = .secondary
    var accent: Color
    var identifier: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(title)
                    .font(role == .quiet ? Theme.Fonts.secondaryAction : Theme.Fonts.primaryAction)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Fonts.caption)
                        .monospacedDigit()
                        .opacity(0.75)
                }
            }
            .foregroundStyle(foreground)
            .padding(.vertical, subtitle == nil ? 15 : 9)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier ?? "")
    }

    private var foreground: Color {
        switch role {
        case .primary: return .black
        case .destructive: return Theme.danger
        default: return Theme.textPrimary
        }
    }

    private var background: Color {
        switch role {
        case .primary: return accent
        default: return Theme.backgroundElevated
        }
    }

    private var border: Color {
        switch role {
        case .destructive: return Theme.danger.opacity(0.4)
        case .primary: return .clear
        default: return Color.white.opacity(0.08)
        }
    }
}
