import Observation
import UIKit

/// Keeps the screen awake only while recording (AC-022).
@MainActor
@Observable
final class IdleTimerController: IdleTimerControlling {
    private(set) var disabled = UIApplication.shared.isIdleTimerDisabled

    var isIdleTimerDisabled: Bool {
        get { disabled }
        set {
            disabled = newValue
            UIApplication.shared.isIdleTimerDisabled = newValue
        }
    }
}
