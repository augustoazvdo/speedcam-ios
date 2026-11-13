import CoreLocation
import XCTest
@testable import SpeedCam

@MainActor
final class CoreLocationProviderTests: XCTestCase {
    // AC-102: When In Use only, no background updates, stops when told to.
    func test_AC102_providerIsForegroundOnlyAndStops() {
        let provider = CoreLocationProvider()
        XCTAssertFalse(provider.manager.allowsBackgroundLocationUpdates)
        XCTAssertEqual(provider.manager.desiredAccuracy, kCLLocationAccuracyBestForNavigation)
        XCTAssertEqual(provider.manager.activityType, .automotiveNavigation)
        provider.start()
        XCTAssertTrue(provider.isRunning)
        provider.stop()
        XCTAssertFalse(provider.isRunning)
    }

    // AC-092: CLLocation values (as driven by `simctl location`) map 1:1 to samples.
    func test_AC092_locationMapsToSample() {
        let location = CLLocation(coordinate: .init(latitude: -23.5, longitude: -46.6), altitude: 0,
                                  horizontalAccuracy: 5, verticalAccuracy: 5, course: 0, courseAccuracy: 1,
                                  speed: 13.89, speedAccuracy: 0.5, timestamp: Date(timeIntervalSince1970: 100))
        let sample = CoreLocationProvider.sample(from: location)
        XCTAssertEqual(sample.speedMps, 13.89)
        XCTAssertEqual(sample.speedAccuracy, 0.5)
        XCTAssertEqual(sample.horizontalAccuracy, 5)
        XCTAssertEqual(sample.timestamp, Date(timeIntervalSince1970: 100))
    }
}
