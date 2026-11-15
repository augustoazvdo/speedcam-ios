import AVFoundation
import CoreGraphics
import Foundation

struct PreviewImage: @unchecked Sendable {
    let image: CGImage
}

/// Frame path on the video queue: frame → OverlayRenderer → RecordingWriter + preview (design §5).
final class PipelineCore: @unchecked Sendable {
    private let overlay: OverlayStateBox
    private let renderer: OverlayRenderer
    private let lock = NSLock()
    private var writer: RecordingWriter?
    private var previewInFlight = false
    var previewSink: (@Sendable (PreviewImage) -> Void)?

    init(overlay: OverlayStateBox, renderer: OverlayRenderer) {
        self.overlay = overlay
        self.renderer = renderer
    }

    func setWriter(_ writer: RecordingWriter?) {
        lock.withLock { self.writer = writer }
    }

    func takeWriter() -> RecordingWriter? {
        lock.withLock {
            defer { writer = nil }
            return writer
        }
    }

    func handle(_ frame: VideoFrame) {
        let model = overlay.snapshot()
        guard let composited = renderer.render(frame.pixelBuffer, model: model) else { return }
        let writer = lock.withLock { self.writer }
        writer?.appendVideo(composited, at: frame.time)

        // Drop preview frames while the main thread is still showing the previous one (R-10).
        let shouldPublish: Bool = lock.withLock {
            guard !previewInFlight, previewSink != nil else { return false }
            previewInFlight = true
            return true
        }
        guard shouldPublish else { return }
        if let image = renderer.previewImage(from: composited, orientation: overlay.displayOrientation, maxDimension: 1280) {
            previewSink?(PreviewImage(image: image))
        } else {
            previewDelivered()
        }
    }

    func previewDelivered() {
        lock.withLock { previewInFlight = false }
    }

    func handle(_ audio: AudioSample) {
        let writer = lock.withLock { self.writer }
        writer?.appendAudio(audio.sampleBuffer)
    }
}

@MainActor
final class RecordingPipeline: RecordingEngine {
    let frames: FrameSource
    let audio: AudioSampleSource?
    private let overlay: OverlayStateBox
    private let core: PipelineCore
    private var running = false
    var onPreview: ((CGImage) -> Void)?

    init(frames: FrameSource, audio: AudioSampleSource?, overlay: OverlayStateBox, renderer: OverlayRenderer) {
        self.frames = frames
        self.audio = audio
        self.overlay = overlay
        core = PipelineCore(overlay: overlay, renderer: renderer)
    }

    var isRunning: Bool { running }

    func startPreview() {
        guard !running else { return }
        running = true
        let core = core
        core.previewSink = { [weak self] preview in
            Task { @MainActor in
                self?.onPreview?(preview.image)
                core.previewDelivered()
            }
        }
        frames.start { core.handle($0) }
        audio?.start { core.handle($0) }
    }

    func stopPreview() {
        guard running else { return }
        running = false
        frames.stop()
        audio?.stop()
        core.previewSink = nil
    }

    func beginRecording(to url: URL, orientation: CaptureOrientation, corner: OverlayCorner, includeAudio: Bool) throws {
        let size = frames.dimensions
        let writer = try RecordingWriter(url: url, videoSize: size, transform: orientation.trackTransform(bufferSize: size),
                                         audioSettings: includeAudio ? audio?.writerSettings : nil)
        overlay.lock(orientation: orientation, corner: corner)
        core.setWriter(writer)
    }

    func finishRecording() async -> RecordingResult {
        let writer = core.takeWriter()
        overlay.unlock()
        guard let writer else { return .failed }
        return await writer.finish()
    }
}
