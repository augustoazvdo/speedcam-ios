import CoreGraphics
import Foundation
import Observation
import SwiftUI
import UIKit

enum CameraState: Equatable {
    case ready
    case notDetermined
    case denied
    case unavailable
}

/// The single obvious next step for the current state (AC-111).
enum NextStep: Equatable {
    case continueOnboarding
    case allowCamera
    case openSettings
    case retryCamera
    case record
    case stop
    case wait
    case noticeAction(NoticeAction)
}

struct OnboardingItem: Identifiable {
    let kind: PermissionKind
    let icon: String
    let title: String
    let reason: String
    var id: PermissionKind { kind }

    static var all: [OnboardingItem] {
        [
            OnboardingItem(kind: .camera, icon: "video.fill", title: L10n.permCamera, reason: L10n.permCameraReason),
            OnboardingItem(kind: .microphone, icon: "mic.fill", title: L10n.permMicrophone, reason: L10n.permMicrophoneReason),
            OnboardingItem(kind: .location, icon: "location.fill", title: L10n.permLocation, reason: L10n.permLocationReason),
            OnboardingItem(kind: .photos, icon: "photo.badge.plus", title: L10n.permPhotos, reason: L10n.permPhotosReason),
        ]
    }
}

/// Designed empty/denied/offline states: icon, one line, one action (AC-113).
enum DesignedState: CaseIterable {
    case cameraDenied
    case cameraNotDetermined
    case cameraUnavailable
    case micOff
    case locationOff
    case noFix
    case empty

    var icon: String {
        switch self {
        case .cameraDenied: "video.slash.fill"
        case .cameraNotDetermined: "video.fill"
        case .cameraUnavailable: "video.slash"
        case .micOff: "mic.slash.fill"
        case .locationOff: "location.slash.fill"
        case .noFix: "antenna.radiowaves.left.and.right.slash"
        case .empty: "film.stack"
        }
    }

    var message: String {
        switch self {
        case .cameraDenied: L10n.cameraDenied
        case .cameraNotDetermined: L10n.cameraNotDetermined
        case .cameraUnavailable: L10n.cameraUnavailable
        case .micOff: L10n.micOffDetail
        case .locationOff: L10n.locationOffBanner
        case .noFix: L10n.noFixBanner
        case .empty: L10n.noClipsYet
        }
    }

    var actionTitle: String {
        switch self {
        case .cameraDenied, .micOff, .locationOff: L10n.openSettings
        case .cameraNotDetermined: L10n.allowCamera
        case .cameraUnavailable: L10n.tryAgain
        case .noFix: L10n.ok
        case .empty: L10n.record
        }
    }
}

enum ElapsedFormat {
    static func string(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

@MainActor
@Observable
final class CameraViewModel {
    let coordinator: RecordingCoordinator
    let settings: SettingsStore

    private(set) var permissions: [PermissionKind: PermissionStatus] = [:]
    private(set) var reading: SpeedReading
    private(set) var previewImage: CGImage?
    private(set) var thumbnail: UIImage?
    private(set) var orientation: CaptureOrientation = .portrait
    var showSettings = false
    var showMicDialog = false
    private(set) var noFixDismissed = false
    private(set) var showOnboarding: Bool

    @ObservationIgnored private let permissionsProvider: PermissionsProviding
    @ObservationIgnored private let opener: SystemOpening
    @ObservationIgnored private let location: LocationProvider
    @ObservationIgnored private let engine: RecordingEngine
    @ObservationIgnored private let saveService: ClipSaveService
    @ObservationIgnored private let overlay: OverlayStateBox
    @ObservationIgnored private let haptics: HapticsPlaying
    @ObservationIgnored private let thermal: ThermalMonitoring
    @ObservationIgnored private let clock: WallClock
    @ObservationIgnored private let cameraAvailable: Bool
    @ObservationIgnored private let speedTickInterval: TimeInterval?
    @ObservationIgnored private var smoother = SpeedSmoother()
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var launched = false

    init(permissions: PermissionsProviding, opener: SystemOpening, location: LocationProvider, engine: RecordingEngine,
         coordinator: RecordingCoordinator, saveService: ClipSaveService, settings: SettingsStore, overlay: OverlayStateBox,
         haptics: HapticsPlaying, thermal: ThermalMonitoring, clock: WallClock, cameraAvailable: Bool,
         speedTickInterval: TimeInterval? = 0.25) {
        permissionsProvider = permissions
        self.opener = opener
        self.location = location
        self.engine = engine
        self.coordinator = coordinator
        self.saveService = saveService
        self.settings = settings
        self.overlay = overlay
        self.haptics = haptics
        self.thermal = thermal
        self.clock = clock
        self.cameraAvailable = cameraAvailable
        self.speedTickInterval = speedTickInterval
        showOnboarding = !settings.onboardingCompleted
        reading = .unavailable(settings.unit, gps: .noFix)
        thumbnail = saveService.lastThumbnail
        overlay.update(corner: settings.overlayCorner)
        overlay.update(reading: reading)

        engine.onPreview = { [weak self] image in self?.previewImage = image }
        location.onSample = { [weak self] sample in
            self?.smoother.ingest(sample)
            self?.refreshReading()
        }
        location.onAuthorizationChange = { [weak self] _ in
            self?.refreshPermissions()
            self?.refreshReading()
        }
        thermal.onChange = { [weak self] level in
            Task { await self?.thermalChanged(level) }
        }
        coordinator.onClipSaved = { [weak self] in
            guard let self else { return }
            thumbnail = saveService.lastThumbnail
        }
    }

    // MARK: Derived state

    var cameraState: CameraState {
        guard cameraAvailable else { return .unavailable }
        switch permissions[.camera] ?? .notDetermined {
        case .granted: return .ready
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        }
    }

    var canRecord: Bool { cameraState == .ready && !showOnboarding }
    var showMicOffBadge: Bool { permissions[.microphone] == .denied }
    var showLocationOffBanner: Bool { permissions[.location] == .denied }
    var showNoFixBanner: Bool {
        !showLocationOffBanner && reading.gps == .noFix && !noFixDismissed && cameraState == .ready
    }
    var isCornerPickerEnabled: Bool { coordinator.state == .idle }
    var selectedCorner: OverlayCorner { settings.overlayCorner }
    var hasClips: Bool { thumbnail != nil }

    var nextStep: NextStep {
        if showOnboarding { return .continueOnboarding }
        if let notice = coordinator.notice { return .noticeAction(notice.kind.action) }
        switch cameraState {
        case .denied: return .openSettings
        case .notDetermined: return .allowCamera
        case .unavailable: return .retryCamera
        case .ready: break
        }
        switch coordinator.state {
        case .idle: return .record
        case .recording: return .stop
        case .starting, .finishing, .saving: return .wait
        }
    }

    func elapsedText(at date: Date? = nil) -> String {
        guard let start = coordinator.recordingStart else { return ElapsedFormat.string(0) }
        return ElapsedFormat.string((date ?? clock.now()).timeIntervalSince(start))
    }

    // MARK: Lifecycle

    /// Once per launch: recover clips left by a crash, then retry pending saves (AC-077, AC-006).
    func launch(store: ClipStore) async {
        guard !launched else { return }
        launched = true
        let report = await ClipRecovery.recover(store: store)
        if let kind = report.notice { coordinator.show(kind) }
        await flushPendingIfAllowed()
    }

    func scenePhaseChanged(_ phase: ScenePhase) async {
        switch phase {
        case .active:
            refreshPermissions()
            if coordinator.isRecording && permissions[.camera] == .denied {
                await coordinator.stop(.cameraRevoked)
            }
            guard !showOnboarding else { return }
            startForeground()
            await flushPendingIfAllowed()
        case .background:
            if let reason = InterruptionMonitor.stopReason(for: phase) { await coordinator.stop(reason) }
            stopForeground()
        default:
            break
        }
    }

    func handle(_ event: CaptureEvent) async {
        if let reason = InterruptionMonitor.stopReason(for: event) { await coordinator.stop(reason) }
    }

    func thermalChanged(_ level: ThermalLevel) async {
        await coordinator.thermalChanged(level)
    }

    private func startForeground() {
        if location.authorization != .denied { location.start() }
        if cameraState == .ready { engine.startPreview() }
        refreshReading()
        startTicking()
    }

    private func stopForeground() {
        location.stop()
        engine.stopPreview()
        tickTask?.cancel()
        tickTask = nil
    }

    private func startTicking() {
        guard tickTask == nil, let speedTickInterval else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(speedTickInterval))
                self?.refreshReading()
            }
        }
    }

    private func refreshPermissions() {
        var map: [PermissionKind: PermissionStatus] = [:]
        for kind in PermissionKind.allCases { map[kind] = permissionsProvider.status(kind) }
        permissions = map
        smoother.authorization = location.authorization == .denied || map[.location] == .denied ? .denied : .authorized
    }

    func refreshReading() {
        let newReading = smoother.reading(at: clock.now(), unit: settings.unit)
        if newReading.gps != .noFix { noFixDismissed = false }
        if newReading != reading { reading = newReading }
        overlay.update(reading: newReading)
    }

    private func flushPendingIfAllowed() async {
        guard permissionsProvider.status(.photos) != .denied, saveService.hasPending,
              let outcome = await saveService.flushPending() else { return }
        thumbnail = saveService.lastThumbnail
        switch outcome {
        case .saved:
            haptics.success()
            coordinator.showToast(.savedToPhotos)
            if coordinator.notice?.kind == .photosDenied || coordinator.notice?.kind == .photosFailed {
                coordinator.dismissNotice()
            }
        case .denied: coordinator.show(.photosDenied)
        case .failed: coordinator.show(.photosFailed)
        }
    }

    // MARK: Intents

    func continueOnboarding() async {
        for kind in [PermissionKind.camera, .microphone, .location, .photos] {
            _ = await permissionsProvider.request(kind)
        }
        settings.onboardingCompleted = true
        showOnboarding = false
        refreshPermissions()
        startForeground()
    }

    func tapRecord() {
        Task { await tapRecordAsync() }
    }

    func tapRecordAsync() async {
        guard canRecord else { return }
        await coordinator.toggle(orientation: orientation, corner: settings.overlayCorner,
                                 includeAudio: permissions[.microphone] == .granted)
    }

    func toggleUnit() {
        settings.unit = settings.unit.toggled
        haptics.selection()
        refreshReading()
    }

    func selectUnit(_ unit: SpeedUnit) {
        guard unit != settings.unit else { return }
        toggleUnit()
    }

    func selectCorner(_ corner: OverlayCorner) {
        guard isCornerPickerEnabled, corner != settings.overlayCorner else { return }
        settings.overlayCorner = corner
        overlay.update(corner: corner)
        haptics.selection()
    }

    func orientationChanged(_ orientation: CaptureOrientation) {
        guard orientation != self.orientation else { return }
        self.orientation = orientation
        overlay.update(orientation: orientation)
    }

    func openLastClip() {
        haptics.selection()
        opener.openPhotos()
    }

    func presentSettings() {
        haptics.selection()
        showSettings = true
    }

    func openSystemSettings() {
        opener.openSettings()
    }

    func requestCamera() async {
        _ = await permissionsProvider.request(.camera)
        refreshPermissions()
        startForeground()
    }

    func retryCamera() {
        engine.stopPreview()
        engine.startPreview()
    }

    func dismissNoFix() {
        noFixDismissed = true
    }

    func performNoticeAction() {
        guard let notice = coordinator.notice else { return }
        switch notice.kind.action {
        case .ok:
            coordinator.dismissNotice()
        case .openSettings:
            coordinator.dismissNotice()
            opener.openSettings()
        case .retrySave:
            coordinator.dismissNotice()
            Task { await flushPendingIfAllowed() }
        }
    }
}
