import XCTest
@testable import SpeedCam

final class ScaffoldTests: XCTestCase {
    // AC-101
    func test_AC101_bundleHasAllFourUsageDescriptions() {
        let info = Bundle.main.infoDictionary ?? [:]
        for key in ["NSCameraUsageDescription", "NSMicrophoneUsageDescription",
                    "NSLocationWhenInUseUsageDescription", "NSPhotoLibraryAddUsageDescription"] {
            let value = info[key] as? String ?? ""
            XCTAssertGreaterThan(value.count, 40, "\(key) must be a specific what+why sentence")
        }
    }

    // AC-101
    func test_AC101_noAlwaysLocationKeysOrBackgroundModes() {
        let info = Bundle.main.infoDictionary ?? [:]
        XCTAssertNil(info["NSLocationAlwaysUsageDescription"])
        XCTAssertNil(info["NSLocationAlwaysAndWhenInUseUsageDescription"])
        XCTAssertNil(info["UIBackgroundModes"])
    }
}
