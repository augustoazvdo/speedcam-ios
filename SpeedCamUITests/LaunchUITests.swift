import XCTest

final class LaunchUITests: XCTestCase {
    // AC-001
    func test_AC001_appLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertEqual(app.state, .runningForeground)
    }
}
