import Foundation
import UIKit

/// Consistent haptic language (§38). One meaning per pattern; small
/// animations get no haptics at all.
final class HapticsPlayer {
    enum Effect {
        case cardDeal       // soft impact
        case actionConfirm  // light tap
        case raise          // rigid impact
        case allIn          // heavy impact
        case bigWin         // success
        case bigLoss        // warning notification
        case yourTurn       // double light pulse
        case warning        // timer nearly expired
        case error          // invalid input
    }

    var enabled: Bool = true
    /// 0 = off, 0.5 = minimal, 1 = standard, 1.3 = strong (§48).
    var intensityScale: Double = 1.0

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notify = UINotificationFeedbackGenerator()

    func play(_ effect: Effect) {
        guard enabled, intensityScale > 0 else { return }
        // Minimal mode drops the heavy effects entirely (§48).
        if intensityScale < 0.75 {
            switch effect {
            case .allIn, .bigWin, .bigLoss, .raise: return
            default: break
            }
        }
        switch effect {
        case .cardDeal:
            light.impactOccurred(intensity: 0.55)
        case .actionConfirm:
            light.impactOccurred()
        case .raise:
            rigid.impactOccurred()
        case .allIn:
            heavy.impactOccurred()
        case .bigWin:
            notify.notificationOccurred(.success)
        case .bigLoss:
            notify.notificationOccurred(.warning)
        case .yourTurn:
            light.impactOccurred(intensity: 0.7)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                guard let self, self.enabled else { return }
                self.light.impactOccurred(intensity: 0.9)
            }
        case .warning:
            medium.impactOccurred(intensity: 0.8)
        case .error:
            notify.notificationOccurred(.error)
        }
    }
}
