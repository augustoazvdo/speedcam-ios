import CoreGraphics
import Foundation
@testable import SpeedCam

final class ManualClock: WallClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ start: Date = Date(timeIntervalSince1970: 1_800_000_000)) { current = start }
    func now() -> Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current += seconds } }
}

final class FakeStorage: StorageMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: Int64
    init(megabytes: Int64 = 10_000) { bytes = megabytes * 1_000_000 }
    func set(megabytes: Int64) { lock.withLock { bytes = megabytes * 1_000_000 } }
    func freeBytes() -> Int64 { lock.withLock { bytes } }
}

@MainActor
final class FakeHaptics: HapticsPlaying {
    var events: [String] = []
    func recordStarted() { events.append("start") }
    func recordStopped() { events.append("stop") }
    func selection() { events.append("selection") }
    func success() { events.append("success") }
    func warning() { events.append("warning") }
}

@MainActor
final class FakeIdleTimer: IdleTimerControlling {
    var isIdleTimerDisabled = false
}

@MainActor
final class FakeEngine: RecordingEngine {
    var onPreview: ((CGImage) -> Void)?
    private(set) var previewRunning = false
    func startPreview() { previewRunning = true }
    func stopPreview() { previewRunning = false }

    var beginCalls: [(url: URL, orientation: CaptureOrientation, corner: OverlayCorner, audio: Bool)] = []
    var finishCount = 0
    var beginError: Error?
    var result: RecordingResult?
    /// When set, finishRecording suspends until `resumeFinish()` is called.
    var holdFinish = false
    private var pending: CheckedContinuation<Void, Never>?

    func beginRecording(to url: URL, orientation: CaptureOrientation, corner: OverlayCorner, includeAudio: Bool) throws {
        if let beginError { throw beginError }
        beginCalls.append((url, orientation, corner, includeAudio))
    }

    func finishRecording() async -> RecordingResult {
        finishCount += 1
        if holdFinish {
            await withCheckedContinuation { pending = $0 }
        }
        return result ?? .finished(beginCalls.last?.url ?? URL(fileURLWithPath: "/tmp/x.mov"))
    }

    func resumeFinish() {
        pending?.resume()
        pending = nil
    }
}

@MainActor
final class FakeClipSaver: ClipSaving {
    var processed: [URL] = []
    var outcome: SaveOutcome = .saved
    func process(_ url: URL) async -> SaveOutcome {
        processed.append(url)
        return outcome
    }
}

final class FakeClipURLs: ClipURLProviding, @unchecked Sendable {
    private var n = 0
    func newRecordingURL() -> URL {
        n += 1
        return URL(fileURLWithPath: "/tmp/clip-\(n).mov")
    }
}

@MainActor
final class FakePermissions: PermissionsProviding {
    var statuses: [PermissionKind: PermissionStatus]
    /// Status each kind becomes when requested.
    var answers: [PermissionKind: PermissionStatus] = [:]
    var requests: [PermissionKind] = []

    init(_ all: PermissionStatus = .granted) {
        statuses = Dictionary(uniqueKeysWithValues: PermissionKind.allCases.map { ($0, all) })
    }

    func status(_ kind: PermissionKind) -> PermissionStatus { statuses[kind] ?? .notDetermined }

    func request(_ kind: PermissionKind) async -> PermissionStatus {
        requests.append(kind)
        if let answer = answers[kind] { statuses[kind] = answer }
        return status(kind)
    }
}

@MainActor
final class FakeOpener: SystemOpening {
    var opened: [String] = []
    func openSettings() { opened.append("settings") }
    func openPhotos() { opened.append("photos") }
}

@MainActor
final class FakeLocation: LocationProvider {
    var authorization: LocationAuthorization = .authorized
    var onSample: ((LocationSample) -> Void)?
    var onAuthorizationChange: ((LocationAuthorization) -> Void)?
    private(set) var isRunning = false
    func start() { isRunning = true }
    func stop() { isRunning = false }
    func emit(kmh: Double, at date: Date) {
        onSample?(LocationSample(speedMps: kmh / 3.6, speedAccuracy: 0.5, horizontalAccuracy: 5, timestamp: date))
    }
}

@MainActor
final class FakeThermal: ThermalMonitoring {
    var level: ThermalLevel = .nominal
    var onChange: ((ThermalLevel) -> Void)?
}

/// Yields so `Task`s spawned on the main actor can run.
@MainActor
func settle(_ times: Int = 20) async {
    for _ in 0..<times { await Task.yield() }
}
