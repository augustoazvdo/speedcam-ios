import Foundation

enum SpeedUnit: String, Sendable, CaseIterable, Codable {
    case kmh
    case mph

    /// Unit labels are the same in every language (AC-133).
    var label: String {
        switch self {
        case .kmh: "km/h"
        case .mph: "mph"
        }
    }

    func convert(metersPerSecond mps: Double) -> Double {
        switch self {
        case .kmh: mps * 3.6
        case .mph: mps * 3.6 / 1.609344
        }
    }

    var toggled: SpeedUnit { self == .kmh ? .mph : .kmh }
}

enum GPSStatus: String, Sendable, Equatable {
    case good
    case weak
    case noFix
    case off
}

enum LocationAuthorization: Sendable, Equatable {
    case notDetermined
    case denied
    case authorized
}

/// Raw CoreLocation values; negative accuracy/speed means "invalid" as in `CLLocation`.
struct LocationSample: Sendable, Equatable {
    var speedMps: Double
    var speedAccuracy: Double
    var horizontalAccuracy: Double
    var timestamp: Date
}

struct SpeedReading: Sendable, Equatable {
    static let placeholder = "--"

    /// Rounded whole number in `unit`, or nil when there is no trustworthy speed.
    var value: Int?
    var unit: SpeedUnit
    var gps: GPSStatus

    var display: String { display(locale: .current) }

    func display(locale: Locale) -> String {
        guard let value else { return Self.placeholder }
        return value.formatted(.number.grouping(.never).locale(locale))
    }

    static func unavailable(_ unit: SpeedUnit, gps: GPSStatus) -> SpeedReading {
        SpeedReading(value: nil, unit: unit, gps: gps)
    }
}
