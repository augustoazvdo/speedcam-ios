import XCTest

enum UIArgs {
    static let base = ["-SpeedCamSyntheticCamera", "YES", "-SpeedCamSkipOnboarding", "YES",
                       "-SpeedCamFakePhotos", "success", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]

    static func launch(_ extra: [String] = [], reset: Bool = true, location: String? = "constant50kmh",
                       permissions: String = "granted", language: [String]? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        var args = base + ["-SpeedCamFakePermissions", permissions]
        if let location { args += ["-SpeedCamSimulatedLocation", location] }
        if reset { args += ["-SpeedCamResetDefaults", "YES"] }
        if let language {
            args.removeAll { $0 == "(en)" || $0 == "en_US" || $0 == "-AppleLanguages" || $0 == "-AppleLocale" }
            args += language
        }
        app.launchArguments = args + extra
        app.launch()
        return app
    }
}

extension XCUIApplication {
    func element(_ id: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @discardableResult
    func waitFor(_ id: String, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let element = element(id)
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "\(id) did not appear", file: file, line: line)
        return element
    }

    func text(_ label: String) -> XCUIElement {
        descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }
}

extension XCTestCase {
    func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }
}
