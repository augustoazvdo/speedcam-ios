import XCTest

@MainActor
final class CameraScreenUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    // AC-012 / AC-090 / AC-011: idle screen shows preview with live overlay and the four controls.
    func test_AC012_idleScreenShowsControlsAndEmptyState() {
        let app = UIArgs.launch()
        let preview = app.waitFor("preview")
        XCTAssertTrue(waitUntil { (preview.value as? String ?? "").contains("50 km/h") }, "live overlay: \(String(describing: preview.value))")
        for id in ["record.button", "unit.button", "thumbnail.empty", "settings.button"] {
            XCTAssertTrue(app.waitFor(id).isHittable, id)
        }
        XCTAssertTrue(app.text("No clips yet").exists)
        XCTAssertEqual(app.element("unit.button").label, "km/h")
    }

    // AC-020 / AC-021 / AC-060 / AC-094: record → red dot + timer → stop → Saving… → ✓ Saved to Photos.
    func test_AC094_recordStopSavedFlow() {
        let app = UIArgs.launch()
        let record = app.waitFor("record.button")
        XCTAssertEqual(record.label, "Record")
        record.tap()
        XCTAssertTrue(app.waitFor("recording.indicator", timeout: 1).exists) // AC-020
        let timer = app.waitFor("recording.timer")
        XCTAssertTrue(timer.label.hasPrefix("00:0"), timer.label)
        XCTAssertEqual(record.label, "Stop")
        XCTAssertTrue(waitUntil(timeout: 4) { timer.label >= "00:02" })

        record.tap()
        XCTAssertTrue(app.waitFor("saving.indicator", timeout: 2).exists) // AC-021
        XCTAssertTrue(app.text("✓ Saved to Photos").waitForExistence(timeout: 8)) // AC-060
        XCTAssertFalse(app.element("recording.indicator").exists)
        XCTAssertEqual(record.label, "Record")
        XCTAssertTrue(app.waitFor("thumbnail.button").exists) // AC-061
    }

    // AC-061: the thumbnail opens the Photos app (no in-app library).
    func test_AC061_thumbnailOpensPhotosApp() {
        let app = UIArgs.launch()
        app.waitFor("record.button").tap()
        _ = app.waitFor("recording.indicator")
        sleep(2)
        app.element("record.button").tap()
        let thumbnail = app.waitFor("thumbnail.button", timeout: 10)
        thumbnail.tap()
        let photos = XCUIApplication(bundleIdentifier: "com.apple.mobileslideshow")
        XCTAssertTrue(photos.wait(for: .runningForeground, timeout: 10))
        app.activate()
    }

    // AC-082 / AC-110: the unit indicator toggles immediately.
    func test_AC082_unitToggleIsLive() {
        let app = UIArgs.launch()
        let unit = app.waitFor("unit.button")
        let preview = app.waitFor("preview")
        XCTAssertTrue(waitUntil { (preview.value as? String ?? "").contains("50 km/h") })
        app.waitFor("record.button").tap()
        _ = app.waitFor("recording.indicator")
        unit.tap()
        XCTAssertTrue(waitUntil(timeout: 1) { unit.label == "mph" })
        XCTAssertTrue(waitUntil(timeout: 1) { (preview.value as? String ?? "").contains("31 mph") })
        app.element("record.button").tap()
    }

    // AC-003 / AC-113 / AC-111: camera denied → designed state with one "Open Settings" and record disabled.
    func test_AC003_cameraDeniedState() {
        let app = UIArgs.launch(permissions: "camera=denied")
        let state = app.waitFor("state.cameraDenied")
        XCTAssertTrue(app.text("Camera access is off. SpeedCam needs it to record.").exists)
        let action = app.waitFor("state.action")
        XCTAssertEqual(action.label, "Open Settings")
        XCTAssertEqual(state.buttons.count, 1)
        XCTAssertFalse(app.element("record.button").isEnabled)
    }

    // AC-004: mic off badge offers Open Settings.
    func test_AC004_micOffBadge() {
        let app = UIArgs.launch(permissions: "microphone=denied")
        let badge = app.waitFor("badge.mic")
        XCTAssertEqual(badge.label, "No audio — Mic off")
        badge.tap()
        XCTAssertTrue(app.buttons["Open Settings"].waitForExistence(timeout: 2))
    }

    // AC-005 / AC-113: location off → "--", GPS off and a banner with Open Settings; record still enabled.
    func test_AC005_locationOffBanner() {
        let app = UIArgs.launch(location: nil, permissions: "location=denied")
        let banner = app.waitFor("banner.location")
        XCTAssertTrue(app.text("Location is off — speed won't be recorded").exists)
        XCTAssertEqual(app.element("banner.location.action").label, "Open Settings")
        XCTAssertTrue(banner.exists)
        let preview = app.element("preview")
        XCTAssertTrue(waitUntil { (preview.value as? String ?? "").contains("-- km/h, GPS off") }, String(describing: preview.value))
        XCTAssertTrue(app.element("record.button").isEnabled)
    }

    // AC-075 / AC-113: no fix → non-blocking banner, recording works.
    func test_AC075_noFixBannerDoesNotBlock() {
        let app = UIArgs.launch(location: "noFix")
        XCTAssertTrue(app.waitFor("banner.noFix").exists)
        XCTAssertTrue(app.text("Searching for GPS — you can still record").exists)
        XCTAssertEqual(app.alerts.count, 0)
        app.element("record.button").tap()
        XCTAssertTrue(app.waitFor("recording.indicator").exists)
        app.element("record.button").tap()
    }

    // AC-006 / AC-078: Photos denied → specific message with Open Settings.
    func test_AC006_photosDeniedNotice() {
        let app = UIArgs.launch(["-SpeedCamFakePhotos", "denied"])
        app.waitFor("record.button").tap()
        _ = app.waitFor("recording.indicator")
        sleep(1)
        app.element("record.button").tap()
        XCTAssertTrue(app.text("Couldn't save to Photos — access is off").waitForExistence(timeout: 8))
        XCTAssertEqual(app.element("notice.action").label, "Open Settings")
    }

    // AC-070 / AC-078 / AC-111: low storage blocks recording with one "OK".
    func test_AC070_lowStorageNotice() {
        let app = UIArgs.launch(["-SpeedCamFakeFreeMB", "300"])
        app.waitFor("record.button").tap()
        XCTAssertTrue(app.text("Not enough storage — free up space to record").waitForExistence(timeout: 2))
        XCTAssertFalse(app.element("recording.indicator").exists)
        let ok = app.element("notice.action")
        XCTAssertEqual(ok.label, "OK")
        ok.tap()
        XCTAssertTrue(waitUntil(timeout: 2) { !app.element("notice").exists })
    }

    // AC-012 / AC-110: settings sheet holds only the unit toggle and the corner picker.
    func test_AC012_settingsSheetContents() {
        let app = UIArgs.launch()
        app.waitFor("settings.button").tap()
        XCTAssertTrue(app.waitFor("settings.unit").exists)
        for corner in ["topLeft", "topRight", "bottomLeft", "bottomRight"] {
            XCTAssertTrue(app.element("settings.corner.\(corner)").exists, corner)
        }
        XCTAssertEqual(app.switches.count, 0)
        XCTAssertEqual(app.textFields.count, 0)
        app.element("settings.done").tap()
    }

    // AC-001 / AC-002: fresh install shows onboarding; Continue requests permissions then shows the camera.
    func test_AC001_onboardingOnFreshInstall() {
        let app = XCUIApplication()
        app.launchArguments = ["-SpeedCamSyntheticCamera", "YES", "-SpeedCamResetDefaults", "YES",
                               "-SpeedCamFakePermissions", "camera=notDetermined,microphone=notDetermined,location=notDetermined,photos=notDetermined",
                               "-SpeedCamSimulatedLocation", "constant50kmh", "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.waitFor("onboarding.continue").exists)
        for title in ["Camera", "Microphone", "Location (While Using)", "Photos (add only)"] {
            XCTAssertTrue(app.text(title).exists, title)
        }
        XCTAssertFalse(app.element("record.button").exists)
        app.element("onboarding.continue").tap()
        XCTAssertTrue(app.waitFor("record.button", timeout: 5).isEnabled)
    }
}
