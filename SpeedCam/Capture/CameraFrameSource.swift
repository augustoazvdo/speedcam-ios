import AVFoundation
import Foundation

/// Back wide camera frames in sensor orientation (ASM-002).
final class CameraFrameSource: FrameSource, @unchecked Sendable {
    let service: CaptureSessionService
    private let includeAudio: @Sendable () -> Bool

    init(service: CaptureSessionService, includeAudio: @escaping @Sendable () -> Bool) {
        self.service = service
        self.includeAudio = includeAudio
    }

    var dimensions: CGSize { CGSize(width: 1920, height: 1080) }
    var isAvailable: Bool { CaptureSessionService.hasCamera }

    func start(onFrame: @escaping @Sendable (VideoFrame) -> Void) {
        service.setVideoHandler(onFrame)
        service.start(includeAudio: includeAudio())
    }

    func stop() {
        service.setVideoHandler(nil)
        service.stop()
    }
}
