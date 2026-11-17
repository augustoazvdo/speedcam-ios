import AVFoundation
import CoreVideo
import Foundation

// All hardware access sits behind these protocols and is injected by AppEnvironment (R-03).

struct VideoFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let time: CMTime
}

struct AudioSample: @unchecked Sendable {
    let sampleBuffer: CMSampleBuffer
}

protocol FrameSource: AnyObject, Sendable {
    /// Buffer size in sensor orientation (landscape, e.g. 1920×1080).
    var dimensions: CGSize { get }
    var isAvailable: Bool { get }
    func start(onFrame: @escaping @Sendable (VideoFrame) -> Void)
    func stop()
}

protocol AudioSampleSource: AnyObject, Sendable {
    /// Output settings for the AAC writer input.
    var writerSettings: [String: any Sendable] { get }
    func start(onAudio: @escaping @Sendable (AudioSample) -> Void)
    func stop()
}

@MainActor
protocol LocationProvider: AnyObject {
    var authorization: LocationAuthorization { get }
    var onSample: ((LocationSample) -> Void)? { get set }
    var onAuthorizationChange: ((LocationAuthorization) -> Void)? { get set }
    var isRunning: Bool { get }
    func start()
    func stop()
    func setRecordingMode(_ recording: Bool)
}

enum PhotoSaveError: Error, Equatable {
    case denied
    case failed
}

protocol PhotoLibrarySaving: Sendable {
    func save(videoAt url: URL) async throws(PhotoSaveError)
}

enum PermissionKind: String, Sendable, CaseIterable {
    case camera
    case microphone
    case location
    case photos
}

enum PermissionStatus: Sendable, Equatable {
    case notDetermined
    case denied
    case granted
}

@MainActor
protocol PermissionsProviding: AnyObject {
    func status(_ kind: PermissionKind) -> PermissionStatus
    func request(_ kind: PermissionKind) async -> PermissionStatus
}

@MainActor
protocol SystemOpening: AnyObject {
    func openSettings()
    func openPhotos()
}

protocol StorageMonitoring: Sendable {
    func freeBytes() -> Int64
}

enum ThermalLevel: Sendable, Equatable {
    case nominal
    case fair
    case serious
    case critical
}

@MainActor
protocol ThermalMonitoring: AnyObject {
    var level: ThermalLevel { get }
    var onChange: ((ThermalLevel) -> Void)? { get set }
}

protocol WallClock: Sendable {
    func now() -> Date
}

struct SystemClock: WallClock {
    func now() -> Date { Date() }
}

@MainActor
protocol IdleTimerControlling: AnyObject {
    var isIdleTimerDisabled: Bool { get set }
}

@MainActor
protocol HapticsPlaying: AnyObject {
    func recordStarted()
    func recordStopped()
    func selection()
    func success()
    func warning()
}
