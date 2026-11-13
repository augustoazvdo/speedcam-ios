import XCTest
@testable import SpeedCam

@MainActor
final class SettingsStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    // AC-080
    func test_AC080_defaultUnitIsKmhRegardlessOfRegion() {
        XCTAssertEqual(SettingsStore(defaults: defaults).unit, .kmh)
    }

    // AC-081
    func test_AC081_mphPersistsAcrossInstances() {
        let store = SettingsStore(defaults: defaults)
        store.unit = .mph
        XCTAssertEqual(SettingsStore(defaults: defaults).unit, .mph)
    }

    // AC-120
    func test_AC120_defaultCornerIsBottomLeft() {
        XCTAssertEqual(SettingsStore(defaults: defaults).overlayCorner, .bottomLeft)
    }

    // AC-123
    func test_AC123_cornerPersistsAcrossInstances() {
        for corner in OverlayCorner.allCases {
            let store = SettingsStore(defaults: defaults)
            store.overlayCorner = corner
            XCTAssertEqual(SettingsStore(defaults: defaults).overlayCorner, corner)
        }
    }

    // AC-001: onboarding is shown until completed once.
    func test_AC001_onboardingCompletionPersists() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertFalse(store.onboardingCompleted)
        store.onboardingCompleted = true
        XCTAssertTrue(SettingsStore(defaults: defaults).onboardingCompleted)
    }
}
