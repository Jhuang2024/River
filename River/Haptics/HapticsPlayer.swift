import Foundation
import UIKit

/// Thin wrapper over the system feedback generators.
final class HapticsPlayer {
    enum Effect {
        case cardDeal
        case actionConfirm
        case raise
        case allIn
        case bigWin
        case bigLoss
    }

    var enabled: Bool = true

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notify = UINotificationFeedbackGenerator()

    func play(_ effect: Effect) {
        guard enabled else { return }
        switch effect {
        case .cardDeal:
            light.impactOccurred(intensity: 0.6)
        case .actionConfirm:
            light.impactOccurred()
        case .raise:
            medium.impactOccurred()
        case .allIn:
            heavy.impactOccurred()
        case .bigWin:
            notify.notificationOccurred(.success)
        case .bigLoss:
            notify.notificationOccurred(.warning)
        }
    }
}
