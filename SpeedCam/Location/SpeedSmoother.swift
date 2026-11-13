import Foundation

/// Pure speed logic (ASM-006): validity filtering, EMA smoothing, stationary clamp,
/// staleness and unit conversion. Never reports a stale or fabricated value (R-08).
struct SpeedSmoother: Sendable {
    static let maxHorizontalAccuracy = 50.0
    static let maxSpeedAccuracy = 5.0
    static let staleAfter: TimeInterval = 3
    static let alpha = 0.5
    static let stationaryKmh = 2.0

    var authorization: LocationAuthorization = .authorized

    private var smoothedMps: Double?
    private var lastFixAt: Date?
    private var lastSampleWasGood = false

    mutating func ingest(_ sample: LocationSample) {
        // ASM-014: any update with a fix (horizontalAccuracy >= 0) counts as a location update.
        guard sample.horizontalAccuracy >= 0 else { return }
        if let lastFixAt, sample.timestamp.timeIntervalSince(lastFixAt) > Self.staleAfter {
            smoothedMps = nil
        }
        lastFixAt = sample.timestamp

        let isGood = sample.speedMps >= 0
            && sample.speedAccuracy >= 0
            && sample.speedAccuracy <= Self.maxSpeedAccuracy
            && sample.horizontalAccuracy <= Self.maxHorizontalAccuracy
        lastSampleWasGood = isGood
        guard isGood else {
            smoothedMps = nil
            return
        }
        if let previous = smoothedMps {
            smoothedMps = previous + Self.alpha * (sample.speedMps - previous)
        } else {
            smoothedMps = sample.speedMps
        }
    }

    func reading(at now: Date, unit: SpeedUnit) -> SpeedReading {
        guard authorization == .authorized else { return .unavailable(unit, gps: .off) }
        guard let lastFixAt, now.timeIntervalSince(lastFixAt) <= Self.staleAfter else {
            return .unavailable(unit, gps: .noFix)
        }
        guard lastSampleWasGood, let smoothedMps else { return .unavailable(unit, gps: .weak) }

        if SpeedUnit.kmh.convert(metersPerSecond: smoothedMps) < Self.stationaryKmh {
            return SpeedReading(value: 0, unit: unit, gps: .good)
        }
        let value = Int(unit.convert(metersPerSecond: smoothedMps).rounded())
        return SpeedReading(value: value, unit: unit, gps: .good)
    }
}
