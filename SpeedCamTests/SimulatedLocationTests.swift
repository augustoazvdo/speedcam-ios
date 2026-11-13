import XCTest
@testable import SpeedCam

#if DEBUG
final class SimulatedLocationTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    // AC-091
    func test_AC091_constant50kmhIsDeterministic() throws {
        for second in 0..<10 {
            let s = try XCTUnwrap(SimulatedLocationScenario.constant50kmh.sample(elapsed: Double(second), start: t0))
            XCTAssertEqual(s.speedMps * 3.6, 50, accuracy: 0.001)
            XCTAssertEqual(s.timestamp, t0 + Double(second))
        }
    }

    // AC-091
    func test_AC091_accelerateIncreasesMonotonically() throws {
        var last = -1.0
        for second in 0...20 {
            let s = try XCTUnwrap(SimulatedLocationScenario.accelerate.sample(elapsed: Double(second), start: t0))
            XCTAssertGreaterThan(s.speedMps, last)
            last = s.speedMps
        }
        // same input → same output
        XCTAssertEqual(SimulatedLocationScenario.accelerate.sample(elapsed: 7, start: t0),
                       SimulatedLocationScenario.accelerate.sample(elapsed: 7, start: t0))
    }

    // AC-091
    func test_AC091_invalidNoFixAndWeakScenariosDriveSmoother() {
        func reading(_ scenario: SimulatedLocationScenario) -> SpeedReading {
            var smoother = SpeedSmoother()
            for second in 0..<5 {
                if let s = scenario.sample(elapsed: Double(second), start: t0) { smoother.ingest(s) }
            }
            return smoother.reading(at: t0 + 4.5, unit: .kmh)
        }
        XCTAssertEqual(reading(.invalid).display, "--")
        XCTAssertEqual(reading(.noFix).gps, .noFix)
        XCTAssertEqual(reading(.weak).gps, .weak)
        XCTAssertEqual(reading(.constant50kmh).display, "50")
    }

    // AC-091
    @MainActor
    func test_AC091_providerEmitsScenarioSamples() async throws {
        let provider = SimulatedLocationProvider(scenario: .constant50kmh, interval: 0.05)
        var received: [LocationSample] = []
        provider.onSample = { received.append($0) }
        provider.start()
        try await Task.sleep(for: .milliseconds(300))
        provider.stop()
        XCTAssertGreaterThanOrEqual(received.count, 2)
        XCTAssertEqual(received.first?.speedMps ?? 0, 50 / 3.6, accuracy: 0.001)
        XCTAssertEqual(provider.authorization, .authorized)
        XCTAssertFalse(provider.isRunning)
    }
}
#endif
