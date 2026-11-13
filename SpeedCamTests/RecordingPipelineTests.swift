import AVFoundation
import XCTest
@testable import SpeedCam

#if DEBUG
@MainActor
final class RecordingPipelineTests: XCTestCase {
    private var box: OverlayStateBox!
    private var pipeline: RecordingPipeline!
    private var url: URL!

    override func setUp() async throws {
        box = OverlayStateBox()
        box.update(reading: SpeedReading(value: 50, unit: .kmh, gps: .good))
        box.update(orientation: .landscapeRight)
        let orientationBox = box!
        pipeline = RecordingPipeline(frames: SyntheticFrameSource(orientation: { orientationBox.displayOrientation }),
                                     audio: SilentAudioSource(), overlay: box, renderer: OverlayRenderer())
        url = FileManager.default.temporaryDirectory.appendingPathComponent("pipeline-\(UUID().uuidString).mov")
    }

    override func tearDown() async throws {
        pipeline.stopPreview()
        try? FileManager.default.removeItem(at: url)
    }

    private func frame(at seconds: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }

    // AC-011: the live preview is the composited frame, so it shows the same overlay as the file.
    func test_AC011_previewShowsOverlayWhenIdle() async throws {
        var previews: [CGImage] = []
        pipeline.onPreview = { previews.append($0) }
        pipeline.startPreview()
        try await Task.sleep(for: .seconds(0.8))
        XCTAssertGreaterThan(previews.count, 5)
        let text = try TestImages.recognizedText(try XCTUnwrap(previews.last)).joined(separator: " ")
        XCTAssertTrue(text.contains("50"), text)
        XCTAssertTrue(text.contains("km/h"), text)
    }

    // AC-011: preview and recorded frame have the plate at the same relative position and size.
    func test_AC011_previewMatchesRecordedLayout() async throws {
        var last: CGImage?
        pipeline.onPreview = { last = $0 }
        pipeline.startPreview()
        try pipeline.beginRecording(to: url, orientation: .landscapeRight, corner: .bottomLeft, includeAudio: false)
        try await Task.sleep(for: .seconds(1))
        _ = await pipeline.finishRecording()
        let preview = Bitmap(cgImage: try XCTUnwrap(last))
        let recorded = Bitmap(cgImage: try await frame(at: 0.5))
        let renderer = OverlayRenderer()
        let model = box.snapshot(date: Date())
        let plate = renderer.plateRect(for: model, uprightSize: CGSize(width: 1920, height: 1080))
        let scale = CGFloat(preview.width) / 1920
        let previewPlate = CGRect(x: plate.minX * scale, y: plate.minY * scale, width: plate.width * scale, height: plate.height * scale)
        // Plate interior is darker than the synthetic scene around it in both images.
        let inner = { (r: CGRect) in r.insetBy(dx: r.width * 0.3, dy: r.height * 0.45) }
        XCTAssertLessThan(preview.luminances(in: inner(previewPlate)).first!, 0.1)
        XCTAssertLessThan(recorded.luminances(in: inner(plate)).first!, 0.1)
    }

    // AC-082: unit changes apply to the recorded overlay immediately.
    func test_AC082_unitChangeDuringRecordingAppliesToFile() async throws {
        pipeline.startPreview()
        try pipeline.beginRecording(to: url, orientation: .landscapeRight, corner: .bottomLeft, includeAudio: false)
        try await Task.sleep(for: .seconds(1))
        box.update(reading: SpeedReading(value: 31, unit: .mph, gps: .good))
        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(await pipeline.finishRecording(), .finished(url))
        let early = try TestImages.recognizedText(try await frame(at: 0.4)).joined(separator: " ")
        let late = try TestImages.recognizedText(try await frame(at: 1.6)).joined(separator: " ")
        XCTAssertTrue(early.contains("km/h"), early)
        XCTAssertTrue(late.contains("mph"), late)
        XCTAssertTrue(late.contains("31"), late)
    }

    // AC-124 / ASM-013: changing the corner mid-recording does not move the file's overlay.
    func test_AC124_cornerLockedDuringRecording() async throws {
        pipeline.startPreview()
        try pipeline.beginRecording(to: url, orientation: .landscapeRight, corner: .bottomLeft, includeAudio: false)
        box.update(corner: .topRight)
        try await Task.sleep(for: .seconds(1))
        _ = await pipeline.finishRecording()
        let bitmap = Bitmap(cgImage: try await frame(at: 0.7))
        let bottomLeft = CGRect(x: 100, y: 1080 - 200, width: 200, height: 120)
        let topRight = CGRect(x: 1920 - 300, y: 80, width: 200, height: 120)
        XCTAssertLessThan(bitmap.luminances(in: bottomLeft)[10], 0.1, "plate stays bottom-left")
        XCTAssertGreaterThan(bitmap.luminances(in: topRight)[10], 0.1, "no plate top-right")
        XCTAssertEqual(box.snapshot(date: Date()).corner, .topRight, "preview uses the new corner after recording")
    }

    // AC-052: rotating mid-recording keeps the file's orientation locked at start.
    func test_AC052_rotationDuringRecordingDoesNotRotateFile() async throws {
        box.update(orientation: .portrait)
        pipeline.startPreview()
        try pipeline.beginRecording(to: url, orientation: .portrait, corner: .bottomLeft, includeAudio: false)
        try await Task.sleep(for: .seconds(0.5))
        box.update(orientation: .landscapeRight)
        try await Task.sleep(for: .seconds(0.7))
        _ = await pipeline.finishRecording()
        let track = try await AVURLAsset(url: url).loadTracks(withMediaType: .video)[0]
        let transform = try await track.load(.preferredTransform)
        XCTAssertEqual(transform, CaptureOrientation.portrait.trackTransform(bufferSize: CGSize(width: 1920, height: 1080)))
        let late = try TestImages.recognizedText(try await frame(at: 1.0)).joined(separator: " ")
        XCTAssertTrue(late.contains("50"), "overlay still upright in the locked orientation: \(late)")
    }

    // AC-031: audio track recorded when mic is available.
    func test_AC031_pipelineRecordsAudioWhenRequested() async throws {
        pipeline.startPreview()
        try pipeline.beginRecording(to: url, orientation: .landscapeRight, corner: .bottomLeft, includeAudio: true)
        try await Task.sleep(for: .seconds(1))
        _ = await pipeline.finishRecording()
        let asset = AVURLAsset(url: url)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let video = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(audio.count, 1)
        let offset = try await (video[0].load(.timeRange).start - audio[0].load(.timeRange).start).seconds
        XCTAssertLessThanOrEqual(abs(offset), 0.1)
    }

    // AC-023: stop immediately after start leaves no empty file.
    func test_AC023_immediateStopProducesNoFile() async throws {
        try pipeline.beginRecording(to: url, orientation: .landscapeRight, corner: .bottomLeft, includeAudio: false)
        XCTAssertEqual(await pipeline.finishRecording(), .empty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
#endif
