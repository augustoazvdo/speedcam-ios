import XCTest
@testable import SpeedCam

final class LocalizationBundleTests: XCTestCase {
    private let usageKeys = ["NSCameraUsageDescription", "NSMicrophoneUsageDescription",
                             "NSLocationWhenInUseUsageDescription", "NSPhotoLibraryAddUsageDescription"]

    private func infoPlistStrings(_ localization: String) -> [String: String] {
        guard let path = Bundle.main.path(forResource: "InfoPlist", ofType: "strings", inDirectory: nil, forLocalization: localization),
              let dict = NSDictionary(contentsOfFile: path) as? [String: String] else { return [:] }
        return dict
    }

    // AC-131
    func test_AC131_usageStringsLocalizedInPortuguese() {
        let pt = infoPlistStrings("pt-BR")
        for key in usageKeys {
            let value = pt[key] ?? ""
            XCTAssertTrue(value.hasPrefix("O SpeedCam"), "\(key) missing pt-BR translation: \(value)")
        }
    }

    // AC-131
    func test_AC131_usageStringsLocalizedInEnglish() {
        let en = infoPlistStrings("en")
        for key in usageKeys {
            XCTAssertTrue((en[key] ?? "").hasPrefix("SpeedCam"), "\(key) missing en value")
        }
    }

    // AC-130
    func test_AC130_bundleDeclaresEnglishAndPortuguese() {
        let localizations = Set(Bundle.main.localizations)
        XCTAssertTrue(localizations.isSuperset(of: ["en", "pt-BR"]), "\(localizations)")
        XCTAssertEqual(Bundle.preferredLocalizations(from: Bundle.main.localizations, forPreferences: ["fr-FR"]).first, "en")
    }
}
