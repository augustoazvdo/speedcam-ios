import Foundation
import Observation

enum OverlayCorner: String, Sendable, CaseIterable, Codable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    static let `default`: OverlayCorner = .bottomLeft
}

/// Persisted user settings (US-09, US-12).
@MainActor
@Observable
final class SettingsStore {
    private enum Key {
        static let unit = "speedcam.unit"
        static let corner = "speedcam.overlayCorner"
        static let onboarding = "speedcam.onboardingCompleted"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var unit: SpeedUnit {
        didSet { defaults.set(unit.rawValue, forKey: Key.unit) }
    }

    var overlayCorner: OverlayCorner {
        didSet { defaults.set(overlayCorner.rawValue, forKey: Key.corner) }
    }

    var onboardingCompleted: Bool {
        didSet { defaults.set(onboardingCompleted, forKey: Key.onboarding) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        unit = defaults.string(forKey: Key.unit).flatMap(SpeedUnit.init(rawValue:)) ?? .kmh
        overlayCorner = defaults.string(forKey: Key.corner).flatMap(OverlayCorner.init(rawValue:)) ?? .default
        onboardingCompleted = defaults.bool(forKey: Key.onboarding)
    }

    func reset() {
        for key in [Key.unit, Key.corner, Key.onboarding] { defaults.removeObject(forKey: key) }
        unit = .kmh
        overlayCorner = .default
        onboardingCompleted = false
    }
}
