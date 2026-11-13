import Foundation

@MainActor
final class ThermalMonitor: ThermalMonitoring {
    var onChange: ((ThermalLevel) -> Void)?
    private var observer: (any NSObjectProtocol)?

    init() {
        observer = NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.onChange?(self.level)
            }
        }
    }

    var level: ThermalLevel {
        Self.map(ProcessInfo.processInfo.thermalState)
    }

    nonisolated static func map(_ state: ProcessInfo.ThermalState) -> ThermalLevel {
        switch state {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .serious
        }
    }
}
