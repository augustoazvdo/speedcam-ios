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
    private var previewSink: (@Sendable (PreviewImage) -> Void)?
    private var lastIdlePreviewTime: TimeInterval?

    init(overlay: OverlayStateBox, renderer: OverlayRenderer) {
        self.overlay = overlay
        self.renderer = renderer
    }

    func setWriter(_ writer: RecordingWriter?) {
        lock.withLock { self.writer = writer }
    }

    func setPreviewSink(_ sink: (@Sendable (PreviewImage) -> Void)?) {
        lock.withLock { previewSink = sink }
    }

    func takeWriter() -> RecordingWriter? {
        lock.withLock {
            defer { writer = nil }
            return writer
        }
    }

    func handle(_ frame: VideoFrame) {
        let work: (RecordingWriter?, (@Sendable (PreviewImage) -> Void)?)? = lock.withLock {
            guard let writer else {
                guard let previewSink, !previewInFlight else { return nil }
                let now = ProcessInfo.processInfo.systemUptime
                if let lastIdlePreviewTime, now - lastIdlePreviewTime < 1.0 / 15.0 { return nil }
                lastIdlePreviewTime = now
                previewInFlight = true
                return (nil, previewSink)
            }
            let sink: (@Sendable (PreviewImage) -> Void)?
            if !previewInFlight, let previewSink {
                previewInFlight = true
                sink = previewSink
            } else {
                sink = nil
            }
            return (writer, sink)
        }
        guard let (writer, sink) = work else { return }
        let model = overlay.snapshot()
        guard let composited = renderer.render(frame.pixelBuffer, model: model) else {
            if work?.1 != nil { previewDelivered() }
            return
        }
        writer?.appendVideo(composited, at: frame.time)
        guard let sink else { return }
        if let image = renderer.previewImage(from: composited, orientation: overlay.displayOrientation, maxDimension: 1280) {
            sink(PreviewImage(image: image))
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
        core.setPreviewSink { [weak self] preview in
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
        core.setPreviewSink(nil)
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
