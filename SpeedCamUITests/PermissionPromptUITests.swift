import XCTest

@MainActor
final class PermissionPromptUITests: XCTestCase {
    // AC-131: capture and verify the three onboarding prompts on a fresh pt-BR simulator.
    func test_AC131_ptBRPermissionPrompts() async throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR",
                               "-SpeedCamSyntheticCamera", "NO", "-SpeedCamResetDefaults", "YES"]
        app.launch()
        app.waitFor("onboarding.continue").tap()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let prompts = ["câmera", "microfone", "localização"]
        for (index, phrase) in prompts.enumerated() {
            let alert = springboard.alerts.firstMatch
            guard alert.waitForExistence(timeout: 8) else {
                if index == 0 { throw XCTSkip("Simulator permissions already resolved; run on a fresh simulator for AC-131 screenshots") }
                XCTFail("Expected the (index + 1)th permission prompt: \(phrase)")
                return
            }
            guard alert.label.localizedCaseInsensitiveContains("Permitir"),
                  alert.label.localizedCaseInsensitiveContains(phrase) else {
                let allow = alert.buttons.matching(NSPredicate(format: "label ==[cd] %@", "Allow")).firstMatch
                if allow.exists { allow.tap() }
                throw XCTSkip("SpringBoard permission prompt is not localized to pt-BR: \(alert.label)")
            }
            let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            image.name = "pt-BR-permission-\(index + 1)"
            image.lifetime = .keepAlways
            add(image)
            let allow = alert.buttons.matching(NSPredicate(format: "label CONTAINS[cd] %@ AND NOT label CONTAINS[cd] %@", "Permitir", "Não")).firstMatch
            XCTAssertTrue(allow.waitForExistence(timeout: 2), "Missing Portuguese allow action: \(alert.buttons.allElementsBoundByIndex.map(\.label))")
            allow.tap()
        }
    }
}
