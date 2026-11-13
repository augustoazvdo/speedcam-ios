import UIKit

@MainActor
final class Haptics: HapticsPlaying {
    private let impact = UIImpactFeedbackGenerator(style: .medium)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let notification = UINotificationFeedbackGenerator()

    func recordStarted() { impact.impactOccurred() }
    func recordStopped() { rigid.impactOccurred() }
    func selection() { selectionGenerator.selectionChanged() }
    func success() { notification.notificationOccurred(.success) }
    func warning() { notification.notificationOccurred(.warning) }
}
