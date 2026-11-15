import XCTest
@testable import SpeedCam

final class CameraZoomOptionTests: XCTestCase {
    // AC-136
    func test_AC136_offersSupportedNativeStopsAndFormatsDeviceDisplayValues() {
        let options = CameraZoomOption.available(minimum: 0.5, maximum: 8,
                                                 switchOvers: [1.2, 2, 5], displayMultiplier: 1)

        XCTAssertEqual(options.map(\.factor), [0.5, 1, 1.2, 2, 5])
        XCTAssertEqual(options.map(\.label), ["0.5×", "1×", "1.2×", "2×", "5×"])
    }

    // AC-136
    func test_AC136_neverOffersStopsOutsideCurrentCameraRange() {
        let options = CameraZoomOption.available(minimum: 1.2, maximum: 3,
                                                 switchOvers: [1, 2, 5], displayMultiplier: 1)

        XCTAssertEqual(options.map(\.factor), [1.2, 2])
        XCTAssertEqual(options.map(\.label), ["1.2×", "2×"])
    }

    // AC-136
    func test_AC136_usesTheDeviceDisplayMultiplierForLabels() {
        let options = CameraZoomOption.available(minimum: 1, maximum: 5,
                                                 switchOvers: [2.5], displayMultiplier: 2)

        XCTAssertEqual(options.map(\.label), ["2×", "5×"])
    }
}
