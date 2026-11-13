import AVFoundation
import Foundation

/// Microphone samples from the shared capture session; only used when mic access is granted (AC-004).
final class AudioSource: AudioSampleSource, @unchecked Sendable {
    let service: CaptureSessionService

    init(service: CaptureSessionService) {
        self.service = service
    }

    var writerSettings: [String: any Sendable] { service.audioWriterSettings }

    func start(onAudio: @escaping @Sendable (AudioSample) -> Void) {
        service.setAudioHandler(onAudio)
    }

    func stop() {
        service.setAudioHandler(nil)
    }
}
