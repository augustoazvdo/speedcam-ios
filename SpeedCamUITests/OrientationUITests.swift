import XCTest

@MainActor
final class OrientationUITests: XCTestCase {
    private let controlIDs = ["thumbnail.empty", "record.button", "unit.button", "settings.button"]

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    private func frames(_ app: XCUIApplication) -> [CGRect] {
        controlIDs.map { app.waitFor($0).frame }
    }

    /// Controls sit on one line and keep the same order along it.
    private func assertSameOrder(_ frames: [CGRect], _ context: String, file: StaticString = #filePath, line: UInt = #line) {
        let xs = frames.map(\.midX), ys = frames.map(\.midY)
        let spreadX = xs.max()! - xs.min()!, spreadY = ys.max()! - ys.min()!
        let axis = spreadX > spreadY ? xs : ys
        let increasing = zip(axis, axis.dropFirst()).allSatisfy { $0 < $1 }
        let decreasing = zip(axis, axis.dropFirst()).allSatisfy { $0 > $1 }
        XCTAssertTrue(increasing || decreasing, "\(context): controls out of order \(frames)", file: file, line: line)
        let cross = spreadX > spreadY ? ys : xs
        XCTAssertLessThan(cross.max()! - cross.min()!, 30, "\(context): controls not aligned \(frames)", file: file, line: line)
    }

    // AC-051 / AC-112: portrait, landscape left and right keep the same controls, order, labels and size.
    func test_AC051_AC112_controlsSameOrderInEveryOrientation() {
        let app = UIArgs.launch()
        let portrait = frames(app)
        assertSameOrder(portrait, "portrait")
        let labels = controlIDs.map { app.element($0).label }
        for orientation in [UIDeviceOrientation.landscapeLeft, .landscapeRight] {
            XCUIDevice.shared.orientation = orientation
            XCTAssertTrue(waitUntil(timeout: 3) { app.element("debug.orientation").value as? String != "live=portrait locked=none" })
            let rotated = frames(app)
            assertSameOrder(rotated, "\(orientation.rawValue)")
            XCTAssertEqual(controlIDs.map { app.element($0).label }, labels)
            for (a, b) in zip(portrait, rotated) {
                XCTAssertEqual(a.width * a.height, b.width * b.height, accuracy: a.width * a.height * 0.05, "control size changed")
            }
            XCTAssertTrue(app.element("record.button").isHittable)
        }
    }

    // AC-052: rotating mid-recording rotates the UI but not the file; the lock is released after stop.
    func test_AC052_orientationLockedAtRecordStart() {
        let app = UIArgs.launch()
        let probe = app.waitFor("debug.orientation")
        XCTAssertEqual(probe.value as? String, "live=portrait locked=none")
        app.waitFor("record.button").tap()
        _ = app.waitFor("recording.indicator")
        XCTAssertTrue(waitUntil(timeout: 2) { probe.value as? String == "live=portrait locked=portrait" }, String(describing: probe.value))

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(waitUntil(timeout: 3) { probe.value as? String == "live=landscapeRight locked=portrait" }, String(describing: probe.value))
        XCTAssertTrue(app.element("record.button").isHittable)

        app.element("record.button").tap()
        XCTAssertTrue(waitUntil(timeout: 5) { probe.value as? String == "live=landscapeRight locked=none" }, String(describing: probe.value))
    }
}
