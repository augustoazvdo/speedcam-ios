import XCTest
@testable import SpeedCam

final class SpeedSmootherTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func sample(kmh: Double, at offset: TimeInterval, hAcc: Double = 5, sAcc: Double = 0.5) -> LocationSample {
        LocationSample(speedMps: kmh / 3.6, speedAccuracy: sAcc, horizontalAccuracy: hAcc, timestamp: t0 + offset)
    }

    private func raw(mps: Double, at offset: TimeInterval, hAcc: Double = 5, sAcc: Double = 0.5) -> LocationSample {
        LocationSample(speedMps: mps, speedAccuracy: sAcc, horizontalAccuracy: hAcc, timestamp: t0 + offset)
    }

    // AC-040
    func test_AC040_invalidSpeedShowsPlaceholderNotZero() {
        var smoother = SpeedSmoother()
        smoother.ingest(raw(mps: -1, at: 0, sAcc: -1))
        let reading = smoother.reading(at: t0 + 0.5, unit: .kmh)
        XCTAssertEqual(reading.display, "--")
        XCTAssertNil(reading.value)
    }

    // AC-040: a previous valid value is never shown once invalid data arrives (R-08).
    func test_AC040_invalidAfterValidDoesNotKeepLastValue() {
        var smoother = SpeedSmoother()
        smoother.ingest(sample(kmh: 60, at: 0))
        XCTAssertEqual(smoother.reading(at: t0 + 0.2, unit: .kmh).display, "60")
        smoother.ingest(raw(mps: -1, at: 1, sAcc: -1))
        XCTAssertEqual(smoother.reading(at: t0 + 1.2, unit: .kmh).display, "--")
        XCTAssertEqual(smoother.reading(at: t0 + 4.5, unit: .kmh).display, "--")
    }

    // AC-041
    func test_AC041_poorHorizontalAccuracyIsWeak() {
        var smoother = SpeedSmoother()
        smoother.ingest(sample(kmh: 50, at: 0, hAcc: 51))
        let reading = smoother.reading(at: t0 + 0.1, unit: .kmh)
        XCTAssertEqual(reading.display, "--")
        XCTAssertEqual(reading.gps, .weak)
    }

    // AC-041
    func test_AC041_poorOrInvalidSpeedAccuracyIsWeak() {
        for sAcc in [5.1, -1.0] {
            var smoother = SpeedSmoother()
            smoother.ingest(sample(kmh: 50, at: 0, sAcc: sAcc))
            let reading = smoother.reading(at: t0 + 0.1, unit: .kmh)
            XCTAssertEqual(reading.display, "--", "speedAccuracy \(sAcc)")
            XCTAssertEqual(reading.gps, .weak, "speedAccuracy \(sAcc)")
        }
    }

    // AC-041: thresholds are inclusive of the limits.
    func test_AC041_accuracyAtLimitIsGood() {
        var smoother = SpeedSmoother()
        smoother.ingest(sample(kmh: 50, at: 0, hAcc: 50, sAcc: 5))
        let reading = smoother.reading(at: t0 + 0.1, unit: .kmh)
        XCTAssertEqual(reading.display, "50")
        XCTAssertEqual(reading.gps, .good)
    }

    // AC-042
    func test_AC042_noUpdateForMoreThanThreeSecondsIsNoFix() {
        var smoother = SpeedSmoother()
        smoother.ingest(sample(kmh: 50, at: 0))
        XCTAssertEqual(smoother.reading(at: t0 + 3.0, unit: .kmh).display, "50")
        let stale = smoother.reading(at: t0 + 3.01, unit: .kmh)
        XCTAssertEqual(stale.display, "--")
        XCTAssertEqual(stale.gps, .noFix)
    }

    // AC-042
    func test_AC042_neverReceivedIsNoFix() {
        let reading = SpeedSmoother().reading(at: t0, unit: .kmh)
        XCTAssertEqual(reading.display, "--")
        XCTAssertEqual(reading.gps, .noFix)
    }

    // AC-042 / R-08: after a stale gap, the next value is not blended with the stale one.
    func test_AC042_smoothingRestartsAfterStaleGap() {
        var smoother = SpeedSmoother()
        smoother.ingest(sample(kmh: 100, at: 0))
        smoother.ingest(sample(kmh: 20, at: 10))
        XCTAssertEqual(smoother.reading(at: t0 + 10.1, unit: .kmh).display, "20")
    }

    // AC-043
    func test_AC043_noisySpeedsAreSmoothedWithinBound() {
        var smoother = SpeedSmoother()
        let noise: [Double] = [2, -2, 1.5, -1.8, 2, -2, 0.5, 1.9, -1.9, 2, -1, 1.7, -2, 2, -0.4, 1.2, -1.6, 2, -2, 1]
        var previousDisplayed: Int?
        var previousTrue: Double?
        for (i, n) in noise.enumerated() {
            let trueKmh = 50 + Double(i) * 0.5
            smoother.ingest(sample(kmh: trueKmh + n, at: Double(i)))
            let reading = smoother.reading(at: t0 + Double(i) + 0.1, unit: .kmh)
            let value = try! XCTUnwrap(reading.value)
            if let previousDisplayed, let previousTrue {
                let jump = abs(Double(value - previousDisplayed))
                XCTAssertLessThanOrEqual(jump, abs(trueKmh - previousTrue) + 3, "step \(i)")
            }
            previousDisplayed = value
            previousTrue = trueKmh
        }
    }

    // AC-043
    func test_AC043_valueIsRoundedToWholeNumber() {
        var smoother = SpeedSmoother()
        smoother.ingest(sample(kmh: 49.6, at: 0))
        XCTAssertEqual(smoother.reading(at: t0 + 0.1, unit: .kmh).display, "50")
        var other = SpeedSmoother()
        other.ingest(sample(kmh: 49.4, at: 0))
        XCTAssertEqual(other.reading(at: t0 + 0.1, unit: .kmh).display, "49")
    }

    // AC-044
    func test_AC044_belowTwoKmhShowsZero() {
        var smoother = SpeedSmoother()
        smoother.ingest(sample(kmh: 1.9, at: 0))
        XCTAssertEqual(smoother.reading(at: t0 + 0.1, unit: .kmh).display, "0")
        XCTAssertEqual(smoother.reading(at: t0 + 0.1, unit: .mph).display, "0")
    }

    // AC-044
    func test_AC044_twoKmhIsShown() {
        var smoother = SpeedSmoother()
        smoother.ingest(sample(kmh: 2.0, at: 0))
        XCTAssertEqual(smoother.reading(at: t0 + 0.1, unit: .kmh).display, "2")
    }

    // AC-045
    func test_AC045_unitConversion() {
        var smoother = SpeedSmoother()
        smoother.ingest(raw(mps: 13.89, at: 0))
        XCTAssertEqual(smoother.reading(at: t0 + 0.1, unit: .kmh).display, "50")
        XCTAssertEqual(smoother.reading(at: t0 + 0.1, unit: .mph).display, "31")
        XCTAssertEqual(smoother.reading(at: t0 + 0.1, unit: .kmh).unit, .kmh)
        XCTAssertEqual(smoother.reading(at: t0 + 0.1, unit: .mph).unit, .mph)
    }

    // AC-005: location permission off shows "--" with the GPS-off indicator.
    func test_AC005_locationDeniedIsOff() {
        var smoother = SpeedSmoother()
        smoother.ingest(sample(kmh: 50, at: 0))
        smoother.authorization = .denied
        let reading = smoother.reading(at: t0 + 0.1, unit: .kmh)
        XCTAssertEqual(reading.display, "--")
        XCTAssertEqual(reading.gps, .off)
    }

    // AC-133
    func test_AC133_numbersUseLocaleFormatting() {
        let reading = SpeedReading(value: 1234, unit: .kmh, gps: .good)
        XCTAssertEqual(reading.display(locale: Locale(identifier: "pt_BR")), "1234")
        XCTAssertEqual(SpeedReading(value: 7, unit: .kmh, gps: .good).display(locale: Locale(identifier: "ar_EG")), 7.formatted(.number.locale(Locale(identifier: "ar_EG"))))
    }
}
