import CoreGraphics
import Foundation
import Observation

enum RecordingResult: Equatable, Sendable {
    case finished(URL)
    /// No frame was written (e.g. stop right after start); nothing to save (AC-023).
    case empty
    case failed
}

@MainActor
protocol RecordingEngine: AnyObject {
    var onPreview: ((CGImage) -> Void)? { get set }
    func startPreview()
    func stopPreview()
    func beginRecording(to url: URL, orientation: CaptureOrientation, corner: OverlayCorner, includeAudio: Bool) throws
    func finishRecording() async -> RecordingResult
}

enum SaveOutcome: Equatable, Sendable {
    case saved
    case denied
    case failed
}

@MainActor
protocol ClipSaving: AnyObject {
    func process(_ url: URL) async -> SaveOutcome
}

protocol ClipURLProviding: Sendable {
    func newRecordingURL() -> URL
}

enum StopReason: CaseIterable, Sendable {
    case user
    case interruption
    case background
    case storage
    case thermal
    case cameraRevoked
    case cameraFailed
}

enum RecordingState: Equatable, Sendable {
    case idle
    case starting
    case recording(since: Date)
    case finishing
    case saving
}

enum NoticeAction: Equatable, Sendable {
    case ok
    case openSettings
    case retrySave
}

/// Every failure names its cause and offers exactly one action (R-15, AC-078).
enum NoticeKind: CaseIterable, Equatable, Sendable {
    case storageTooLow
    case storageStopped
    case stoppedByCall
    case stoppedByBackground
    case cameraRevoked
    case cameraFailed
    case phoneHot
    case phoneTooHot
    case photosDenied
    case photosFailed
    case writeFailed
    case recovered
    case unrecoverable

    var message: String {
        switch self {
        case .storageTooLow: L10n.storageTooLow
        case .storageStopped: L10n.storageStopped
        case .stoppedByCall: L10n.stoppedByCall
        case .stoppedByBackground: L10n.stoppedByBackground
        case .cameraRevoked: L10n.cameraRevoked
        case .cameraFailed: L10n.cameraFailed
        case .phoneHot: L10n.phoneHot
        case .phoneTooHot: L10n.phoneTooHot
        case .photosDenied: L10n.photosDenied
        case .photosFailed: L10n.photosFailed
        case .writeFailed: L10n.writeFailed
        case .recovered: L10n.recovered
        case .unrecoverable: L10n.unrecoverable
        }
    }

    var action: NoticeAction {
        switch self {
        case .cameraRevoked, .photosDenied: .openSettings
        case .photosFailed: .retrySave
        default: .ok
        }
    }

    var actionTitle: String {
        switch action {
        case .ok: L10n.ok
        case .openSettings: L10n.openSettings
        case .retrySave: L10n.tryAgain
        }
    }

    /// SF Symbol for the designed state (AC-113).
    var icon: String {
        switch self {
        case .storageTooLow, .storageStopped: "externaldrive.badge.exclamationmark"
        case .stoppedByCall: "phone.badge.waveform"
        case .stoppedByBackground: "rectangle.portrait.and.arrow.right"
        case .cameraRevoked, .cameraFailed: "video.slash"
        case .phoneHot, .phoneTooHot: "thermometer.high"
        case .photosDenied, .photosFailed: "photo.badge.exclamationmark"
        case .writeFailed: "exclamationmark.triangle"
        case .recovered: "arrow.counterclockwise.circle"
        case .unrecoverable: "xmark.octagon"
        }
    }
}

struct Notice: Equatable, Identifiable, Sendable {
    let id = UUID()
    let kind: NoticeKind
}

enum Toast: Equatable, Sendable {
    case savedToPhotos
}

/// State machine idle → starting → recording → finishing → saving → idle (design §3).
/// Finalizes the writer on every stop path (R-09).
@MainActor
@Observable
final class RecordingCoordinator {
    static let minimumStartBytes: Int64 = 500_000_000
    static let minimumContinueBytes: Int64 = 200_000_000
    static let debounceInterval: TimeInterval = 0.5

    private(set) var state: RecordingState = .idle
    private(set) var notice: Notice?
    private(set) var toast: Toast?
    var onClipSaved: (() -> Void)?
    var onRecordingModeChanged: ((Bool) -> Void)?

    @ObservationIgnored private let engine: RecordingEngine
    @ObservationIgnored private let saver: ClipSaving
    @ObservationIgnored private let urls: ClipURLProviding
    @ObservationIgnored private let storage: StorageMonitoring
    @ObservationIgnored private let clock: WallClock
    @ObservationIgnored private let haptics: HapticsPlaying
    @ObservationIgnored private let idleTimer: IdleTimerControlling
    @ObservationIgnored private let storagePollInterval: TimeInterval?
    @ObservationIgnored private var lastTap: Date?
    @ObservationIgnored private var storagePoll: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    init(engine: RecordingEngine, saver: ClipSaving, urls: ClipURLProviding, storage: StorageMonitoring,
         clock: WallClock, haptics: HapticsPlaying, idleTimer: IdleTimerControlling,
         storagePollInterval: TimeInterval? = 5) {
        self.engine = engine
        self.saver = saver
        self.urls = urls
        self.storage = storage
        self.clock = clock
        self.haptics = haptics
        self.idleTimer = idleTimer
        self.storagePollInterval = storagePollInterval
    }

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    var isSaving: Bool { state == .finishing || state == .saving }

    var isIdleTimerDisabled: Bool { idleTimer.isIdleTimerDisabled }

    var recordingStart: Date? {
        if case .recording(let since) = state { return since }
        return nil
    }

    /// Record/stop button (debounced, AC-023).
    func toggle(orientation: CaptureOrientation, corner: OverlayCorner, includeAudio: Bool) async {
        let now = clock.now()
        if let lastTap, now.timeIntervalSince(lastTap) < Self.debounceInterval { return }
        switch state {
        case .idle:
            lastTap = now
            start(orientation: orientation, corner: corner, includeAudio: includeAudio)
        case .recording:
            lastTap = now
            await stop(.user)
        case .starting, .finishing, .saving:
            return
        }
    }

    private func start(orientation: CaptureOrientation, corner: OverlayCorner, includeAudio: Bool) {
        guard storage.freeBytes() >= Self.minimumStartBytes else {
            haptics.warning()
            show(.storageTooLow)
            return
        }
        state = .starting
        do {
            try engine.beginRecording(to: urls.newRecordingURL(), orientation: orientation, corner: corner, includeAudio: includeAudio)
        } catch {
            state = .idle
            haptics.warning()
            show(.writeFailed)
            return
        }
        state = .recording(since: clock.now())
        onRecordingModeChanged?(true)
        notice = nil
        idleTimer.isIdleTimerDisabled = true
        haptics.recordStarted()
        startStoragePoll()
    }

    func stop(_ reason: StopReason) async {
        guard isRecording else { return }
        state = .finishing
        onRecordingModeChanged?(false)
        storagePoll?.cancel()
        storagePoll = nil
        idleTimer.isIdleTimerDisabled = false
        haptics.recordStopped()

        let result = await engine.finishRecording()
        switch result {
        case .empty:
            state = .idle
            return
        case .failed:
            state = .idle
            show(.writeFailed)
            return
        case .finished(let url):
            state = .saving
            let outcome = await saver.process(url)
            state = .idle
            switch outcome {
            case .saved:
                haptics.success()
                showToast(.savedToPhotos)
                onClipSaved?()
                if let kind = Self.notice(for: reason) { show(kind) }
            case .denied:
                show(.photosDenied)
            case .failed:
                show(.photosFailed)
            }
        }
    }

    func checkStorage() async {
        guard isRecording, storage.freeBytes() < Self.minimumContinueBytes else { return }
        await stop(.storage)
    }

    func thermalChanged(_ level: ThermalLevel) async {
        guard isRecording else { return }
        switch level {
        case .serious: show(.phoneHot)
        case .critical: await stop(.thermal)
        default: break
        }
    }

    func show(_ kind: NoticeKind) {
        notice = Notice(kind: kind)
    }

    func dismissNotice() {
        notice = nil
    }

    func showToast(_ toast: Toast) {
        self.toast = toast
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    private static func notice(for reason: StopReason) -> NoticeKind? {
        switch reason {
        case .user: nil
        case .interruption: .stoppedByCall
        case .background: .stoppedByBackground
        case .storage: .storageStopped
        case .thermal: .phoneTooHot
        case .cameraRevoked: .cameraRevoked
        case .cameraFailed: .cameraFailed
        }
    }

    private func startStoragePoll() {
        guard let storagePollInterval else { return }
        storagePoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(storagePollInterval))
                await self?.checkStorage()
            }
        }
    }
}
