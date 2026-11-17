#if DEBUG
import Foundation

/// Deterministic speed scripts for the Simulator (AC-091). DEBUG only (R-04).
enum SimulatedLocationScenario: String, Sendable, CaseIterable {
    case constant50kmh
    case accelerate
    case invalid
    case noFix
    case weak

    /// The sample emitted `elapsed` seconds after `start`, or nil when the scenario has no fix.
    func sample(elapsed: TimeInterval, start: Date) -> LocationSample? {
        let timestamp = start + elapsed
        switch self {
        case .constant50kmh:
            return LocationSample(speedMps: 50 / 3.6, speedAccuracy: 0.5, horizontalAccuracy: 5, timestamp: timestamp)
        case .accelerate:
            // 0 → 100 km/h over 20 s, then +1 km/h per second.
            let kmh = elapsed <= 20 ? elapsed * 5 : 100 + (elapsed - 20)
            return LocationSample(speedMps: kmh / 3.6, speedAccuracy: 0.5, horizontalAccuracy: 5, timestamp: timestamp)
        case .invalid:
            return LocationSample(speedMps: -1, speedAccuracy: -1, horizontalAccuracy: 10, timestamp: timestamp)
        case .noFix:
            return nil
        case .weak:
            return LocationSample(speedMps: 50 / 3.6, speedAccuracy: 0.5, horizontalAccuracy: 80, timestamp: timestamp)
        }
    }
}

@MainActor
final class SimulatedLocationProvider: LocationProvider {
    let scenario: SimulatedLocationScenario
    private let interval: TimeInterval
    private var task: Task<Void, Never>?

    var onSample: ((LocationSample) -> Void)?
    var onAuthorizationChange: ((LocationAuthorization) -> Void)?
    let authorization: LocationAuthorization
    var isRunning: Bool { task != nil }

    init(scenario: SimulatedLocationScenario, interval: TimeInterval = 1, authorization: LocationAuthorization = .authorized) {
        self.scenario = scenario
        self.interval = interval
        self.authorization = authorization
    }

    func start() {
        guard task == nil, authorization == .authorized else { return }
        let start = Date()
        task = Task { [weak self, scenario, interval] in
            var tick = 0
            while !Task.isCancelled {
                // Scenario time advances 1 s per tick regardless of the tick interval.
                if let sample = scenario.sample(elapsed: Double(tick), start: start) {
                    let now = Date()
                    self?.onSample?(LocationSample(speedMps: sample.speedMps, speedAccuracy: sample.speedAccuracy,
                                                   horizontalAccuracy: sample.horizontalAccuracy, timestamp: now))
                }
                tick += 1
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func setRecordingMode(_ recording: Bool) {}

    func stop() {
        task?.cancel()
        task = nil
    }
}
#endif
