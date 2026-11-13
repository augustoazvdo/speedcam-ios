import AVFoundation
import CoreImage
import XCTest
@testable import SpeedCam

#if DEBUG
final class RecordingWriterTests: XCTestCase {
    private var url: URL!
    private let size = CGSize(width: 1920, height: 1080)

    override func setUp() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("writer-\(UUID().uuidString).mov")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
    }

    private func makeWriter(orientation: CaptureOrientation = .landscapeRight, audio: Bool = true) throws -> RecordingWriter {
        try RecordingWriter(url: url, videoSize: size, transform: orientation.trackTransform(bufferSize: size),
                            audioSettings: audio ? SilentAudioSource.writerSettings : nil)
    }

    /// Writes `seconds` of 30 fps synthetic video (+ silence), composited with `model(t)`.
    private func write(_ writer: RecordingWriter, seconds: Double, audio: Bool = true,
                       model: ((Double) -> OverlayModel)? = nil) {
        let generator = SyntheticFrameGenerator(size: size)
        let renderer = OverlayRenderer()
        let start = CMTime(seconds: 1000, preferredTimescale: 600)
        let frames = Int(seconds * 30)
        var audioTime = start
        for i in 0..<frames {
            let t = Double(i) / 30
            let pts = start + CMTime(seconds: t, preferredTimescale: 600)
            var buffer = generator.frame(index: i, date: Date(), orientation: .landscapeRight)!
            if let model { buffer = renderer.render(buffer, model: model(t))! }
            while !writer.isReadyForVideo { usleep(500) }
            XCTAssertTrue(writer.appendVideo(buffer, at: pts))
            if audio {
                while audioTime <= pts + CMTime(seconds: 1.0 / 30, preferredTimescale: 600) {
                    while !writer.isReadyForAudio { usleep(500) }
                    _ = writer.appendAudio(SilentAudioSource.silence(at: audioTime, frames: 1024))
                    audioTime = audioTime + CMTime(value: 1024, timescale: 44_100)
                }
            }
        }
    }

    // AC-031
    func test_AC031_writesOneVideoAndOneAudioTrackAt1080p30() async throws {
        let writer = try makeWriter()
        write(writer, seconds: 2)
        let result = await writer.finish()
        XCTAssertEqual(result, .finished(url))

        let asset = AVURLAsset(url: url)
        let video = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(video.count, 1)
        XCTAssertEqual(audio.count, 1)
        let (naturalSize, fps) = try await video[0].load(.naturalSize, .nominalFrameRate)
        XCTAssertEqual(naturalSize, size)
        XCTAssertEqual(Double(fps), 30, accuracy: 1.5)
        let videoFormat = try await video[0].load(.formatDescriptions).first!
        XCTAssertTrue([kCMVideoCodecType_H264, kCMVideoCodecType_HEVC].contains(CMFormatDescriptionGetMediaSubType(videoFormat)))
        let audioFormat = try await audio[0].load(.formatDescriptions).first!
        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(audioFormat), kAudioFormatMPEG4AAC)

        // A/V offset ≤ 100 ms
        let videoRange = try await video[0].load(.timeRange)
        let audioRange = try await audio[0].load(.timeRange)
        XCTAssertLessThanOrEqual(abs((videoRange.start - audioRange.start).seconds), 0.1)
        let playable = try await asset.load(.isPlayable)
        XCTAssertTrue(playable)
    }

    // AC-004 / AC-031: mic denied → video only, still playable.
    func test_AC004_recordsWithoutAudioTrack() async throws {
        let writer = try makeWriter(audio: false)
        write(writer, seconds: 1, audio: false)
        _ = await writer.finish()
        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(audioTracks.count, 0)
        XCTAssertEqual(videoTracks.count, 1)
    }

    // AC-052 / AC-050: the orientation locked at start is the track transform.
    func test_AC052_trackTransformIsLockedOrientation() async throws {
        let writer = try makeWriter(orientation: .portrait)
        write(writer, seconds: 0.5, audio: false)
        _ = await writer.finish()
        let track = try await AVURLAsset(url: url).loadTracks(withMediaType: .video)[0]
        let transform = try await track.load(.preferredTransform)
        XCTAssertEqual(transform, CaptureOrientation.portrait.trackTransform(bufferSize: size))
    }

    // AC-032 / AC-030: frames at different times show the speed of that time.
    func test_AC032_overlayValuesFollowSpeedOverTime() async throws {
        let writer = try makeWriter(audio: false)
        write(writer, seconds: 2, audio: false) { t in
            OverlayModel(reading: SpeedReading(value: t < 1 ? 30 : 80, unit: .kmh, gps: .good), date: Date(),
                         orientation: .landscapeRight, corner: .bottomLeft)
        }
        _ = await writer.finish()
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let early = try await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image
        let late = try await generator.image(at: CMTime(seconds: 1.5, preferredTimescale: 600)).image
        let earlyText = try TestImages.recognizedText(early).joined(separator: " ")
        let lateText = try TestImages.recognizedText(late).joined(separator: " ")
        XCTAssertTrue(earlyText.contains("30"), earlyText)
        XCTAssertTrue(lateText.contains("80"), lateText)
        XCTAssertTrue(lateText.contains("km/h"), lateText)
    }

    // AC-072 / AC-073: finishing mid-recording yields a playable file.
    func test_AC072_finishMidRecordingIsPlayable() async throws {
        let writer = try makeWriter()
        write(writer, seconds: 0.5)
        let result = await writer.finish()
        XCTAssertEqual(result, .finished(url))
        let asset = AVURLAsset(url: url)
        let playable = try await asset.load(.isPlayable)
        let duration = try await asset.load(.duration)
        XCTAssertTrue(playable)
        XCTAssertGreaterThan(duration.seconds, 0.3)
    }

    // AC-023: stopping before any frame leaves no empty/corrupt file.
    func test_AC023_finishWithoutFramesLeavesNoFile() async throws {
        let writer = try makeWriter()
        let result = await writer.finish()
        XCTAssertEqual(result, .empty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    // AC-077 / design §6: movie fragments are written so a crash leaves a recoverable file.
    func test_AC077_writerUsesMovieFragments() throws {
        let writer = try makeWriter()
        XCTAssertEqual(writer.movieFragmentInterval.seconds, 2, accuracy: 0.01)
    }

    // AC-090: synthetic frames are 1920×1080, moving, at 30 fps.
    func test_AC090_syntheticSourceDeliversMovingFramesAt30fps() async throws {
        let source = SyntheticFrameSource(orientation: { .landscapeRight })
        XCTAssertEqual(source.dimensions, size)
        let collector = FrameCollector()
        source.start { collector.add($0) }
        try await Task.sleep(for: .seconds(1.2))
        source.stop()
        let frames = collector.frames
        XCTAssertGreaterThanOrEqual(frames.count, 28)
        XCTAssertLessThanOrEqual(frames.count, 40)
        let first = frames[0], last = frames[frames.count - 1]
        XCTAssertEqual(CVPixelBufferGetWidth(first.pixelBuffer), 1920)
        XCTAssertEqual(CVPixelBufferGetHeight(first.pixelBuffer), 1080)
        XCTAssertGreaterThan((last.time - first.time).seconds, 0.8)
        let a = Bitmap(cgImage: TestImages.cgImage(CIImage(cvPixelBuffer: first.pixelBuffer)))
        let b = Bitmap(cgImage: TestImages.cgImage(CIImage(cvPixelBuffer: last.pixelBuffer)))
        XCTAssertNotEqual(a.bytes, b.bytes, "frames must move")
    }
}

final class FrameCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [VideoFrame] = []
    func add(_ frame: VideoFrame) { lock.withLock { storage.append(frame) } }
    var frames: [VideoFrame] { lock.withLock { storage } }
}
#endif
