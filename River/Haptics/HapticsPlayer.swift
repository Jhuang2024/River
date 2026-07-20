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

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notify = UINotificationFeedbackGenerator()

    func play(_ effect: Effect) {
        guard enabled else { return }
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
