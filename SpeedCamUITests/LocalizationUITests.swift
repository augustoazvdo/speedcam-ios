import XCTest

@MainActor
final class LocalizationUITests: XCTestCase {
    // AC-130 / AC-132
    func test_AC130_ptBR_localizesCameraSettingsAndSavedToast() {
        let app = UIArgs.launch(language: ["-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"])
        XCTAssertTrue(app.text("Ainda não há clipes").waitForExistence(timeout: 8))
        app.waitFor("settings.button").tap()
        XCTAssertTrue(app.text("Ajustes").waitForExistence(timeout: 4))
        app.element("settings.done").tap()
        app.waitFor("record.button").tap()
        _ = app.waitFor("recording.indicator")
        app.element("record.button").tap()
        XCTAssertTrue(app.text("✓ Salvo em Fotos").waitForExistence(timeout: 8))
    }

    // AC-130
    func test_AC130_englishStringsRemainEnglish() {
        let app = UIArgs.launch(language: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"])
        XCTAssertTrue(app.text("No clips yet").waitForExistence(timeout: 8))
        app.waitFor("settings.button").tap()
        XCTAssertTrue(app.text("Settings").waitForExistence(timeout: 4))
    }

    // AC-130: unsupported languages fall back to English.
    func test_AC130_frenchFallsBackToEnglish() {
        let app = UIArgs.launch(language: ["-AppleLanguages", "(fr-FR)", "-AppleLocale", "fr_FR"])
        XCTAssertTrue(app.text("No clips yet").waitForExistence(timeout: 8))
        app.waitFor("settings.button").tap()
        XCTAssertTrue(app.text("Settings").waitForExistence(timeout: 4))
    }

    // AC-132: a save failure names the cause and offers one action in Portuguese.
    func test_AC132_ptBRPhotosFailureIsLocalized() {
        let app = UIArgs.launch(["-SpeedCamFakePhotos", "fail"],
                                language: ["-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"])
        app.waitFor("record.button").tap()
        _ = app.waitFor("recording.indicator")
        app.element("record.button").tap()
        XCTAssertTrue(app.text("Não foi possível salvar em Fotos — o clipe foi mantido neste iPhone").waitForExistence(timeout: 8))
        XCTAssertEqual(app.element("notice").buttons.count, 1)
        XCTAssertEqual(app.element("notice.action").label, "Tentar novamente")
    }
}
