import CoreImage
import XCTest
@testable import SpeedCam

final class OverlayRendererTests: XCTestCase {
    private let renderer = OverlayRenderer()
    private let gray = (64.0 / 255, 64.0 / 255, 64.0 / 255)
    private let date = Date(timeIntervalSince1970: 1_794_573_360) // 2026-11-13 12:36:00 UTC
    private let utc = TimeZone(identifier: "UTC")!

    private func model(_ value: Int? = 50, unit: SpeedUnit = .kmh, gps: GPSStatus = .good,
                       orientation: CaptureOrientation = .landscapeRight, corner: OverlayCorner = .bottomLeft) -> OverlayModel {
        OverlayModel(reading: SpeedReading(value: value, unit: unit, gps: gps), date: date,
                     orientation: orientation, corner: corner, locale: Locale(identifier: "en_US"), timeZone: utc)
    }

    private func renderUpright(_ model: OverlayModel, gray level: UInt8 = 64) throws -> Bitmap {
        let input = TestImages.solidBuffer(gray: level)
        let output = try XCTUnwrap(renderer.render(input, model: model))
        return TestImages.upright(output, orientation: model.orientation)
    }

    private func cornerRect(_ corner: OverlayCorner, in size: CGSize) -> CGRect {
        let w = size.width * 0.45, h = size.height * 0.45
        switch corner {
        case .topLeft: return CGRect(x: 0, y: 0, width: w, height: h)
        case .topRight: return CGRect(x: size.width - w, y: 0, width: w, height: h)
        case .bottomLeft: return CGRect(x: 0, y: size.height - h, width: w, height: h)
        case .bottomRight: return CGRect(x: size.width - w, y: size.height - h, width: w, height: h)
        }
    }

    // AC-030
    func test_AC030_overlayRegionHasNonBackgroundPixels() throws {
        let m = model()
        let bitmap = try renderUpright(m)
        let plate = renderer.plateRect(for: m, uprightSize: CGSize(width: 1920, height: 1080))
        XCTAssertGreaterThan(bitmap.nonBackgroundFraction(in: plate, background: gray), 0.5)
        XCTAssertLessThan(bitmap.nonBackgroundFraction(in: cornerRect(.topRight, in: CGSize(width: 1920, height: 1080)), background: gray), 0.001)
    }

    // AC-030: speed number, unit, GPS indicator and timestamp are in the pixels (OCR).
    func test_AC030_overlayTextIsRecognizable() throws {
        let m = model()
        let input = TestImages.solidBuffer()
        let output = try XCTUnwrap(renderer.render(input, model: m))
        let image = TestImages.cgImage(CIImage(cvPixelBuffer: output))
        let text = try TestImages.recognizedText(image).joined(separator: " ")
        XCTAssertTrue(text.contains("50"), text)
        XCTAssertTrue(text.contains("km/h"), text)
        XCTAssertTrue(text.contains("GPS"), text)
        XCTAssertTrue(text.contains("13/11/2026"), text)
        XCTAssertTrue(text.contains("12:36:00"), text)
    }

    // AC-030 / AC-040: placeholder and mph label are rendered.
    func test_AC030_placeholderAndMphAreRendered() throws {
        let output = try XCTUnwrap(renderer.render(TestImages.solidBuffer(), model: model(nil, unit: .mph, gps: .noFix)))
        let text = try TestImages.recognizedText(TestImages.cgImage(CIImage(cvPixelBuffer: output))).joined(separator: " ")
        XCTAssertTrue(text.contains("mph"), text)
        XCTAssertFalse(text.contains("50"), text)

        // OCR does not read dashes reliably; check the speed row has white dash pixels instead.
        let size = CGSize(width: 1920, height: 1080)
        let dashes = Bitmap(cgImage: renderer.overlayImage(for: model(nil, unit: .mph, gps: .noFix), uprightSize: size))
        let speedRow = CGRect(x: 0, y: 0, width: dashes.width, height: dashes.height / 2)
        let white = dashes.luminances(in: speedRow).filter { $0 > 0.9 }.count
        XCTAssertGreaterThan(white, 100, "\"--\" not drawn")
        let fifty = Bitmap(cgImage: renderer.overlayImage(for: model(50, unit: .mph, gps: .noFix), uprightSize: size))
        XCTAssertNotEqual(dashes.bytes, fifty.bytes)
    }

    // AC-041 / AC-042 / AC-005: each GPS state draws a distinct indicator.
    func test_AC041_gpsStatesRenderDifferently() throws {
        var images: [GPSStatus: [UInt8]] = [:]
        for gps in [GPSStatus.good, .weak, .noFix, .off] {
            images[gps] = Bitmap(cgImage: renderer.overlayImage(for: model(nil, gps: gps), uprightSize: CGSize(width: 1920, height: 1080))).bytes
        }
        XCTAssertEqual(Set(images.values.map { $0.hashValue }).count, 4)
    }

    // AC-034: semi-opaque plate keeps text contrast on bright and dark scenes.
    func test_AC034_legibleOnBrightAndDarkScenes() throws {
        for level: UInt8 in [255, 0] {
            let m = model()
            let bitmap = try renderUpright(m, gray: level)
            let lum = bitmap.luminances(in: renderer.plateRect(for: m, uprightSize: CGSize(width: 1920, height: 1080)))
            let dark = lum[Int(Double(lum.count) * 0.05)]
            let bright = lum[Int(Double(lum.count) * 0.995)]
            XCTAssertGreaterThan((bright + 0.05) / (dark + 0.05), 4.5, "background \(level)")
            XCTAssertLessThan(dark, 0.6, "plate must darken a white sky")
        }
    }

    // AC-050 / AC-122: 3 orientations × 4 corners, overlay upright in the viewer's corner.
    func test_AC122_overlayInEachCornerForEachOrientation() throws {
        for orientation in [CaptureOrientation.portrait, .landscapeLeft, .landscapeRight] {
            for corner in OverlayCorner.allCases {
                try assertOverlay(orientation: orientation, corner: corner)
            }
        }
    }

    // AC-050
    func test_AC050_portraitAndLandscapeAreUpright() throws {
        try assertOverlay(orientation: .portrait, corner: .bottomLeft)
        try assertOverlay(orientation: .landscapeLeft, corner: .bottomLeft)
        try assertOverlay(orientation: .landscapeRight, corner: .bottomLeft)
    }

    // AC-120: default corner bottom-left in the upright frame.
    func test_AC120_defaultCornerRendersBottomLeft() throws {
        XCTAssertEqual(OverlayCorner.default, .bottomLeft)
        try assertOverlay(orientation: .portrait, corner: .default)
        try assertOverlay(orientation: .landscapeRight, corner: .default)
    }

    private func assertOverlay(orientation: CaptureOrientation, corner: OverlayCorner, file: StaticString = #filePath, line: UInt = #line) throws {
        let m = model(orientation: orientation, corner: corner)
        let bitmap = try renderUpright(m)
        let size = CGSize(width: bitmap.width, height: bitmap.height)
        XCTAssertEqual(size, orientation.uprightSize(for: CGSize(width: 1920, height: 1080)), file: file, line: line)
        for other in OverlayCorner.allCases {
            let fraction = bitmap.nonBackgroundFraction(in: cornerRect(other, in: size), background: gray)
            if other == corner {
                XCTAssertGreaterThan(fraction, 0.1, "\(orientation) \(corner)", file: file, line: line)
            } else {
                XCTAssertLessThan(fraction, 0.001, "\(orientation) \(corner): leaked into \(other)", file: file, line: line)
            }
        }
        // Upright: the plate pixels match the reference overlay drawn upright.
        let plate = renderer.plateRect(for: m, uprightSize: size)
        let reference = Bitmap(cgImage: renderer.overlayImage(for: m, uprightSize: size))
        var diff = 0.0, n = 0
        for y in stride(from: 0, to: reference.height, by: 3) {
            for x in stride(from: 0, to: reference.width, by: 3) {
                let (r, g, b) = reference.rgb(x, y)
                let a = Double(reference.bytes[(y * reference.width + x) * 4 + 3]) / 255
                // premultiplied reference over gray
                let expected = (r + gray.0 * (1 - a), g + gray.1 * (1 - a), b + gray.2 * (1 - a))
                let actual = bitmap.rgb(Int(plate.minX) + x, Int(plate.minY) + y)
                diff += abs(expected.0 - actual.0) + abs(expected.1 - actual.1) + abs(expected.2 - actual.2)
                n += 3
            }
        }
        XCTAssertLessThan(diff / Double(n), 0.03, "\(orientation) \(corner) not upright", file: file, line: line)
    }

    // AC-031 / AC-052: track transform follows the iPhone convention for the locked orientation.
    func test_AC052_trackTransformForOrientation() {
        let size = CGSize(width: 1920, height: 1080)
        XCTAssertEqual(CaptureOrientation.landscapeRight.trackTransform(bufferSize: size), .identity)
        XCTAssertEqual(CaptureOrientation.portrait.trackTransform(bufferSize: size), CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0))
        XCTAssertEqual(CaptureOrientation.landscapeLeft.trackTransform(bufferSize: size), CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 1920, ty: 1080))
        XCTAssertEqual(CaptureOrientation.portrait.uprightSize(for: size), CGSize(width: 1080, height: 1920))
    }

    // AC-030 / AC-133: dd/MM/yyyy HH:mm:ss in device local time (ASM-016).
    func test_AC133_timestampFormatPtBR() {
        let saoPaulo = TimeZone(identifier: "America/Sao_Paulo")!
        XCTAssertEqual(OverlayFormat.timestamp(date, timeZone: saoPaulo, locale: Locale(identifier: "pt_BR")), "13/11/2026 09:36:00")
        XCTAssertEqual(OverlayFormat.timestamp(date, timeZone: utc, locale: Locale(identifier: "en_US")), "13/11/2026 12:36:00")
    }

    // AC-133: unit label stays "km/h"/"mph" in pt-BR.
    func test_AC133_unitLabelIsNotTranslated() {
        XCTAssertEqual(SpeedUnit.kmh.label, "km/h")
        XCTAssertEqual(SpeedUnit.mph.label, "mph")
    }

    // AC-034 / R-21: overlay image is cached while text/state is unchanged.
    func test_AC034_overlayImageCachedForSameContent() {
        let size = CGSize(width: 1920, height: 1080)
        let a = renderer.overlayImage(for: model(), uprightSize: size)
        let b = renderer.overlayImage(for: model(corner: .topRight), uprightSize: size)
        XCTAssertTrue(a === b)
        let c = renderer.overlayImage(for: model(51), uprightSize: size)
        XCTAssertFalse(a === c)
    }
}
