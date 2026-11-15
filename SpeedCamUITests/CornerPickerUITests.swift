import XCTest

@MainActor
final class CornerPickerUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    /// Mean luminance (0…1) of a 50×50 pt box inset 14 pt from a corner of `rect`, in a screenshot.
    private func luminance(_ shot: XCUIScreenshot, _ rect: CGRect, top: Bool, left: Bool) -> Double {
        guard let cg = shot.image.cgImage else { return -1 }
        let scale = CGFloat(cg.width) / shot.image.size.width
        let box = CGRect(x: left ? rect.minX + 14 : rect.maxX - 64, y: top ? rect.minY + 14 : rect.maxY - 64, width: 50, height: 50)
        let px = CGRect(x: box.minX * scale, y: box.minY * scale, width: box.width * scale, height: box.height * scale).integral
        let w = Int(px.width), h = Int(px.height)
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: -px.minX, y: -(CGFloat(cg.height) - px.maxY), width: CGFloat(cg.width), height: CGFloat(cg.height)))
        var values: [Double] = []
        for i in stride(from: 0, to: data.count, by: 4) {
            values.append((0.2126 * Double(data[i]) + 0.7152 * Double(data[i + 1]) + 0.0722 * Double(data[i + 2])) / 255)
        }
        return values.sorted()[values.count / 2]
    }

    /// The translucent plate darkens the frame behind it, so the median of its corner is clearly darker than the
    /// opposite corner in the same row (the median ignores the plate text and the synthetic road dashes).
    private func plateCorner(_ app: XCUIApplication) -> String {
        let rect = app.element("preview").frame
        let shot = app.screenshot()
        var corners: [(String, Double)] = []
        for (name, top, left) in [("topLeft", true, true), ("topRight", true, false), ("bottomLeft", false, true), ("bottomRight", false, false)] {
            corners.append((name, luminance(shot, rect, top: top, left: left)))
        }
        let rows = [(corners[0], corners[1]), (corners[2], corners[3])]
        let found = rows.compactMap { a, b -> (String, Double)? in
            if a.1 < b.1 * 0.7 { return (a.0, b.1 / max(a.1, 0.001)) }
            if b.1 < a.1 * 0.7 { return (b.0, a.1 / max(b.1, 0.001)) }
            return nil
        }
        return found.max { $0.1 < $1.1 }?.0 ?? "none \(corners)"
    }

    private func openSettings(_ app: XCUIApplication) {
        app.waitFor("settings.button").tap()
        _ = app.waitFor("settings.corner.topLeft")
    }

    private func closeSettings(_ app: XCUIApplication) {
        app.element("settings.done").tap()
        XCTAssertTrue(waitUntil(timeout: 3) { !app.element("settings.done").exists })
    }

    // AC-120 / AC-121: each corner choice moves the live preview overlay to that corner.
    func test_AC121_cornerPickerMovesPreviewOverlay() {
        let app = UIArgs.launch()
        _ = app.waitFor("preview")
        XCTAssertTrue(waitUntil(timeout: 5) { self.plateCorner(app) == "bottomLeft" }, plateCorner(app)) // AC-120
        for corner in ["topRight", "topLeft", "bottomRight", "bottomLeft"] {
            openSettings(app)
            app.element("settings.corner.\(corner)").tap()
            XCTAssertTrue(app.element("settings.corner.\(corner)").isSelected, corner)
            closeSettings(app)
            XCTAssertTrue(waitUntil(timeout: 1) { self.plateCorner(app) == corner }, "\(corner): \(plateCorner(app))")
        }
    }

    // AC-123: the chosen corner survives a relaunch (settings, preview).
    func test_AC123_cornerPersistsAfterRelaunch() {
        var app = UIArgs.launch()
        openSettings(app)
        app.element("settings.corner.topRight").tap()
        closeSettings(app)
        app.terminate()

        app = UIArgs.launch(reset: false)
        _ = app.waitFor("preview")
        XCTAssertTrue(waitUntil(timeout: 5) { self.plateCorner(app) == "topRight" }, plateCorner(app))
        openSettings(app)
        XCTAssertTrue(app.element("settings.corner.topRight").isSelected)
        XCTAssertFalse(app.element("settings.corner.bottomLeft").isSelected)
    }

    // AC-124: while recording the picker is disabled with the hint, and the overlay stays put.
    func test_AC124_cornerPickerDisabledWhileRecording() {
        let app = UIArgs.launch()
        app.waitFor("record.button").tap()
        _ = app.waitFor("recording.indicator")
        openSettings(app)
        XCTAssertTrue(app.waitFor("settings.cornerHint").exists)
        XCTAssertEqual(app.element("settings.cornerHint").label, "Applies to the next recording")
        XCTAssertFalse(app.element("settings.corner.topRight").isEnabled)
        app.element("settings.corner.topRight").tap()
        XCTAssertTrue(app.element("settings.corner.bottomLeft").isSelected)
        closeSettings(app)
        XCTAssertEqual(plateCorner(app), "bottomLeft")
        app.element("record.button").tap()
        XCTAssertTrue(app.text("✓ Saved to Photos").waitForExistence(timeout: 8))
        openSettings(app)
        XCTAssertTrue(waitUntil(timeout: 2) { !app.element("settings.cornerHint").exists })
        XCTAssertTrue(app.element("settings.corner.topRight").isEnabled)
    }
}
