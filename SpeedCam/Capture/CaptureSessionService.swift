import AVFoundation
import Foundation

/// Owns the AVCaptureSession. All configuration/start/stop runs on `sessionQueue` (R-11);
/// sample buffers arrive on `videoQueue` / `audioQueue`. Device-only (the Simulator has no camera).
final class CaptureSessionService: NSObject, CameraZoomControlling, @unchecked Sendable {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.augusto.speedcam.session")
    let videoQueue = DispatchQueue(label: "com.augusto.speedcam.video", qos: .userInteractive)
    let audioQueue = DispatchQueue(label: "com.augusto.speedcam.audio", qos: .userInitiated)
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let lock = NSLock()
    private let preferredCamera: AVCaptureDevice?
    private var configured = false
    private var audioConfigured = false
    private var videoHandler: (@Sendable (VideoFrame) -> Void)?
    private var audioHandler: (@Sendable (AudioSample) -> Void)?
    private var observers: [any NSObjectProtocol] = []
    var onEvent: (@Sendable (CaptureEvent) -> Void)?

    private static let rearCameraTypes: [AVCaptureDevice.DeviceType] = [
        .builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera,
    ]

    private static var rearCamera: AVCaptureDevice? {
        rearCameraTypes.lazy.compactMap {
            AVCaptureDevice.default($0, for: .video, position: .back)
        }.first
    }

    static var hasCamera: Bool { rearCamera != nil }

    var zoomOptions: [CameraZoomOption] {
        guard let device = preferredCamera else { return [] }
        return CameraZoomOption.available(minimum: device.minAvailableVideoZoomFactor,
                                          maximum: device.maxAvailableVideoZoomFactor,
                                          switchOvers: device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat($0.doubleValue) },
                                          displayMultiplier: Self.displayZoomMultiplier(for: device))
    }

    private static func displayZoomMultiplier(for device: AVCaptureDevice) -> CGFloat {
        if #available(iOS 18.0, *) { return device.displayVideoZoomFactorMultiplier }
        return 1
    }

    func selectZoom(factor: CGFloat) {
        guard zoomOptions.contains(where: { abs($0.factor - factor) < 0.01 }) else { return }
        sessionQueue.async { [weak self] in
            guard let self, let camera = preferredCamera,
                  (try? camera.lockForConfiguration()) != nil else { return }
            camera.ramp(toVideoZoomFactor: factor, withRate: 6)
            camera.unlockForConfiguration()
        }
    }

    override init() {
        preferredCamera = Self.rearCamera
        super.init()
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { [weak self] _ in
                self?.onEvent?(.interrupted)
            },
            center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil) { [weak self] _ in
                self?.onEvent?(.interruptionEnded)
            },
            center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] _ in
                self?.onEvent?(.runtimeError)
            },
        ]
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    var audioWriterSettings: [String: any Sendable] {
        guard let settings = audioOutput.recommendedAudioSettingsForAssetWriter(writingTo: .mov) else {
            return RecordingWriter.aacSettings
        }
        var result: [String: any Sendable] = [:]
        for (key, value) in settings {
            if let number = value as? NSNumber { result[key] = number }
            else if let data = value as? Data { result[key] = data }
            else if let string = value as? String { result[key] = string }
        }
        return result.isEmpty ? RecordingWriter.aacSettings : result
    }

    func setVideoHandler(_ handler: (@Sendable (VideoFrame) -> Void)?) {
        lock.withLock { videoHandler = handler }
    }

    func setAudioHandler(_ handler: (@Sendable (AudioSample) -> Void)?) {
        lock.withLock { audioHandler = handler }
    }

    func start(includeAudio: Bool) {
        sessionQueue.async { [self] in
            configureIfNeeded(includeAudio: includeAudio)
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configureIfNeeded(includeAudio: Bool) {
        if configured && (audioConfigured || !includeAudio) { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if !configured {
            session.sessionPreset = .hd1920x1080
            guard let camera = preferredCamera,
                  let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input) else { return }
            session.addInput(input)
            if (try? camera.lockForConfiguration()) != nil {
                camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
                camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
                camera.unlockForConfiguration()
            }
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
            if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
            configured = true
        }
        if includeAudio && !audioConfigured,
           let mic = AVCaptureDevice.default(for: .audio),
           let input = try? AVCaptureDeviceInput(device: mic), session.canAddInput(input) {
            session.addInput(input)
            audioOutput.setSampleBufferDelegate(self, queue: audioQueue)
            if session.canAddOutput(audioOutput) { session.addOutput(audioOutput) }
            audioConfigured = true
        }
    }
}

extension CaptureSessionService: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output === videoOutput {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let handler = lock.withLock { videoHandler }
            handler?(VideoFrame(pixelBuffer: pixelBuffer, time: CMSampleBufferGetPresentationTimeStamp(sampleBuffer)))
        } else {
            let handler = lock.withLock { audioHandler }
            handler?(AudioSample(sampleBuffer: sampleBuffer))
        }
    }
}
