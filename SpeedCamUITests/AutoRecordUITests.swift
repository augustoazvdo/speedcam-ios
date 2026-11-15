import AVFoundation
import Vision
import XCTest

@MainActor
final class AutoRecordUITests: XCTestCase {
    // AC-093 / AC-094 / AC-030
    func test_AC093_autoRecordExportsPlayableClipWithOverlayFrame() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("speedcam-uitest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let app = UIArgs.launch(["-SpeedCamAutoRecordSeconds", "5", "-SpeedCamExportPath", directory.path])
        _ = app.waitFor("preview")
        let deadline = Date().addingTimeInterval(25)
        var clips: [URL] = []
        while Date() < deadline {
            clips = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?
                .filter { $0.pathExtension == "mov" } ?? []
            if let clip = clips.first, (try? await AVURLAsset(url: clip).load(.isPlayable)) == true { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        let clip = try XCTUnwrap(clips.first, "auto-record did not export a .mov")
        let asset = AVURLAsset(url: clip)
        let playable = try await asset.load(.isPlayable)
        XCTAssertTrue(playable)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let frame = try await generator.image(at: CMTime(seconds: 2, preferredTimescale: 600)).image

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: frame).perform([request])
        let recognized = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string.lowercased() }
        XCTAssertTrue(recognized.contains { $0.contains("50") }, "overlay speed missing: \(recognized)")
        XCTAssertTrue(recognized.contains { $0.contains("km/h") || $0.contains("kmh") }, "overlay unit missing: \(recognized)")
        // AC-135: GPS status is app UI/accessibility state, never burned into the speed gauge.
        XCTAssertFalse(recognized.contains { $0.contains("gps") }, "unexpected extra overlay text: \(recognized)")

        // Compare the bottom-left overlay region against a flat patch away from the plate.
        let left = try XCTUnwrap(frame.cropping(to: CGRect(x: 0, y: 0, width: frame.width / 2, height: frame.height / 2)))
        XCTAssertGreaterThan(Self.luminanceSpread(left), 12, "overlay region is blank")
        let attachment = XCTAttachment(image: UIImage(cgImage: frame))
        attachment.name = "auto-record-overlay-frame"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private static func luminanceSpread(_ image: CGImage) -> Double {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return 0 }
        let step = max(1, image.bitsPerPixel / 8)
        var minValue = 255.0, maxValue = 0.0
        for y in stride(from: 0, to: image.height, by: 4) {
            for x in stride(from: 0, to: image.width, by: 4) {
                let i = y * image.bytesPerRow + x * step
                let value = 0.2126 * Double(bytes[i + 2]) + 0.7152 * Double(bytes[i + 1]) + 0.0722 * Double(bytes[i])
                minValue = min(minValue, value)
                maxValue = max(maxValue, value)
            }
        }
        return maxValue - minValue
    }
}
