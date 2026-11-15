import SwiftUI
import XCTest
@testable import SpeedCam

#if DEBUG
private final class FakeCameraZoom: CameraZoomControlling, @unchecked Sendable {
    let zoomOptions: [CameraZoomOption]
    private(set) var selectedFactor: CGFloat?

    init(options: [CameraZoomOption]) { zoomOptions = options }
    func selectZoom(factor: CGFloat) { selectedFactor = factor }
}

@MainActor
final class CameraViewModelTests: XCTestCase {
    private var permissions: FakePermissions!
    private var opener: FakeOpener!
    private var location: FakeLocation!
    private var engine: FakeEngine!
    private var clipSaver: FakeClipSaver!
    private var photos: FakePhotoSaver!
    private var haptics: FakeHaptics!
    private var idle: FakeIdleTimer!
    private var thermal: FakeThermal!
    private var clock: ManualClock!
    private var storage: FakeStorage!
    private var settings: SettingsStore!
    private var overlay: OverlayStateBox!
    private var store: ClipStore!
    private var root: URL!

    override func setUp() async throws {
        permissions = FakePermissions()
        opener = FakeOpener()
        location = FakeLocation()
        engine = FakeEngine()
        clipSaver = FakeClipSaver()
        photos = FakePhotoSaver()
        haptics = FakeHaptics()
        idle = FakeIdleTimer()
        thermal = FakeThermal()
        clock = ManualClock(Date())
        storage = FakeStorage()
        settings = SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        overlay = OverlayStateBox()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("vm-\(UUID().uuidString)")
        store = ClipStore(root: root)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeVM(onboarded: Bool = true, useRealSaveService: Bool = false,
                        cameraZoom: CameraZoomControlling? = nil) -> CameraViewModel {
        settings.onboardingCompleted = onboarded
        let saveService = ClipSaveService(store: store, saver: photos)
        let saver: ClipSaving = useRealSaveService ? saveService : clipSaver
        let coordinator = RecordingCoordinator(engine: engine, saver: saver, urls: FakeClipURLs(), storage: storage,
                                               clock: clock, haptics: haptics, idleTimer: idle, storagePollInterval: nil)
        return CameraViewModel(permissions: permissions, opener: opener, location: location, engine: engine,
                               coordinator: coordinator, saveService: saveService, settings: settings, overlay: overlay,
                               haptics: haptics, thermal: thermal, clock: clock, cameraAvailable: true,
                               cameraZoom: cameraZoom,
                               speedTickInterval: nil)
    }

    private func record(_ vm: CameraViewModel) async {
        await vm.tapRecordAsync()
    }

    // AC-136
    func test_AC136_selectingAvailableZoomUpdatesCaptureAndSelectionFeedback() {
        let option = CameraZoomOption(factor: 2, label: "2×")
        let zoom = FakeCameraZoom(options: [CameraZoomOption(factor: 1, label: "1×"), option])
        let vm = makeVM(cameraZoom: zoom)

        vm.selectCameraZoom(option)

        XCTAssertEqual(vm.selectedCameraZoom, 2)
        XCTAssertEqual(zoom.selectedFactor, 2)
        XCTAssertEqual(haptics.events, ["selection"])
    }

    // AC-001
    func test_AC001_onboardingFirstWithNoSystemPrompts() async {
        permissions = FakePermissions(.notDetermined)
        let vm = makeVM(onboarded: false)
        await vm.scenePhaseChanged(.active)
        XCTAssertTrue(vm.showOnboarding)
        XCTAssertTrue(permissions.requests.isEmpty)
        XCTAssertEqual(OnboardingItem.all.map(\.kind), [.camera, .microphone, .location, .photos])
        XCTAssertTrue(OnboardingItem.all.allSatisfy { !$0.reason.isEmpty })
    }

    // AC-002
    func test_AC002_continueRequestsEachPermissionInOrder() async {
        permissions = FakePermissions(.notDetermined)
        permissions.answers = [.camera: .granted, .microphone: .granted, .location: .granted, .photos: .granted]
        let vm = makeVM(onboarded: false)
        await vm.continueOnboarding()
        XCTAssertEqual(permissions.requests, [.camera, .microphone, .location, .photos])
        XCTAssertFalse(vm.showOnboarding)
        XCTAssertTrue(settings.onboardingCompleted)
    }

    // AC-002 / R-06 / R-07: only When In Use location and add-only Photos are ever requested.
    func test_AC002_realServiceRequestsWhenInUseAndAddOnly() {
        XCTAssertEqual(PermissionsService.photoAccessLevel, .addOnly)
        XCTAssertEqual(PermissionsService.locationRequest, .whenInUse)
    }

    // AC-003
    func test_AC003_cameraDeniedShowsDeniedStateAndDisablesRecord() async {
        permissions.statuses[.camera] = .denied
        let vm = makeVM()
        await vm.scenePhaseChanged(.active)
        XCTAssertEqual(vm.cameraState, .denied)
        XCTAssertFalse(vm.canRecord)
        await record(vm)
        XCTAssertTrue(engine.beginCalls.isEmpty)
        vm.openSystemSettings()
        XCTAssertEqual(opener.opened, ["settings"])
        XCTAssertEqual(L10n.cameraDenied, "Camera access is off. SpeedCam needs it to record.")
    }

    // AC-004
    func test_AC004_micDeniedRecordsWithoutAudioAndShowsBadge() async {
        permissions.statuses[.microphone] = .denied
        let vm = makeVM()
        await vm.scenePhaseChanged(.active)
        XCTAssertTrue(vm.showMicOffBadge)
        XCTAssertEqual(L10n.micOffBadge, "No audio — Mic off")
        await record(vm)
        XCTAssertEqual(engine.beginCalls.first?.audio, false)
    }

    // AC-005
    func test_AC005_locationDeniedShowsBannerAndAllowsRecording() async {
        permissions.statuses[.location] = .denied
        location.authorization = .denied
        let vm = makeVM()
        await vm.scenePhaseChanged(.active)
        XCTAssertTrue(vm.showLocationOffBanner)
        XCTAssertEqual(vm.reading.gps, .off)
        XCTAssertEqual(vm.reading.display, "--")
        XCTAssertTrue(vm.canRecord)
        XCTAssertEqual(L10n.locationOffBanner, "Location is off — speed won't be recorded")
    }

    // AC-006: pending clips are saved automatically once Photos access is granted and the app is active again.
    func test_AC006_pendingSavedAfterAccessGranted() async throws {
        let vm = makeVM(useRealSaveService: true)
        await vm.scenePhaseChanged(.active)
        let clip = store.newRecordingURL()
        try Data([1, 2, 3]).write(to: clip)
        _ = try store.markPending(clip)
        photos.result = .denied
        permissions.statuses[.photos] = .denied
        await vm.scenePhaseChanged(.active)
        XCTAssertEqual(store.pendingClips().count, 1)

        photos.result = nil
        permissions.statuses[.photos] = .granted
        await vm.scenePhaseChanged(.active)
        XCTAssertTrue(store.pendingClips().isEmpty)
        XCTAssertEqual(vm.coordinator.toast, .savedToPhotos)
    }

    // AC-007
    func test_AC007_deniedStateClearsWhenGrantedInSettings() async {
        permissions.statuses[.camera] = .denied
        let vm = makeVM()
        await vm.scenePhaseChanged(.active)
        XCTAssertEqual(vm.cameraState, .denied)
        permissions.statuses[.camera] = .granted
        await vm.scenePhaseChanged(.active)
        XCTAssertEqual(vm.cameraState, .ready)
        XCTAssertTrue(engine.previewRunning)
    }

    // AC-102
    func test_AC102_locationOnlyWhileForeground() async {
        let vm = makeVM()
        await vm.scenePhaseChanged(.active)
        XCTAssertTrue(location.isRunning)
        await vm.scenePhaseChanged(.background)
        XCTAssertFalse(location.isRunning)
        XCTAssertFalse(engine.previewRunning)
        await vm.scenePhaseChanged(.active)
        XCTAssertTrue(location.isRunning)
    }

    // AC-073
    func test_AC073_backgroundStopsAndSaves() async {
        let vm = makeVM()
        await vm.scenePhaseChanged(.active)
        await record(vm)
        clock.advance(1)
        await vm.scenePhaseChanged(.background)
        XCTAssertEqual(engine.finishCount, 1)
        XCTAssertEqual(vm.coordinator.notice?.kind, .stoppedByBackground)
    }

    // AC-072
    func test_AC072_captureInterruptionStopsAndSaves() async {
        let vm = makeVM()
        await vm.scenePhaseChanged(.active)
        await record(vm)
        clock.advance(1)
        await vm.handle(.interrupted)
        XCTAssertEqual(engine.finishCount, 1)
        XCTAssertEqual(vm.coordinator.notice?.kind, .stoppedByCall)
    }

    // AC-074
    func test_AC074_cameraRevokedStopsLocationRevokedContinues() async {
        let vm = makeVM()
        await vm.scenePhaseChanged(.active)
        await record(vm)
        clock.advance(1)
        location.authorization = .denied
        location.onAuthorizationChange?(.denied)
        permissions.statuses[.location] = .denied
        await vm.scenePhaseChanged(.active)
        XCTAssertTrue(vm.coordinator.isRecording)
        XCTAssertEqual(vm.reading.gps, .off)
        XCTAssertTrue(vm.showLocationOffBanner)

        permissions.statuses[.camera] = .denied
        await vm.scenePhaseChanged(.active)
        XCTAssertFalse(vm.coordinator.isRecording)
        XCTAssertEqual(vm.coordinator.notice?.kind, .cameraRevoked)
    }

    // AC-075 / AC-042
    func test_AC075_noFixRecordsWithoutBlockingAlert() async {
        let vm = makeVM()
        await vm.scenePhaseChanged(.active)
        vm.refreshReading()
        XCTAssertEqual(vm.reading.gps, .noFix)
        XCTAssertTrue(vm.showNoFixBanner)
        await record(vm)
        XCTAssertTrue(vm.coordinator.isRecording)
        XCTAssertNil(vm.coordinator.notice)
    }

    // AC-076: thermal monitor feeds the coordinator.
    func test_AC076_thermalCriticalStops() async {
        let vm = makeVM()
        await vm.scenePhaseChanged(.active)
        await record(vm)
        clock.advance(1)
        await vm.thermalChanged(.critical)
        XCTAssertEqual(vm.coordinator.notice?.kind, .phoneTooHot)
    }

    // AC-045 / AC-082: unit toggle updates the reading and overlay immediately, also while recording.
    func test_AC082_unitToggleAppliesImmediately() async {
        let vm = makeVM()
        await vm.scenePhaseChanged(.active)
        location.emit(kmh: 50, at: clock.now())
        vm.refreshReading()
        XCTAssertEqual(vm.reading.display, "50")
        await record(vm)
        vm.toggleUnit()
        XCTAssertEqual(settings.unit, .mph)
        XCTAssertEqual(vm.reading.display, "31")
        XCTAssertEqual(overlay.snapshot().reading.unit, .mph)
        XCTAssertEqual(haptics.events.last, "selection")
    }

    // AC-081: unit persists for new view models (relaunch).
    func test_AC081_unitUsedAfterRelaunch() async {
        settings.unit = .mph
        let vm = makeVM()
        await vm.scenePhaseChanged(.active)
        XCTAssertEqual(vm.reading.unit, .mph)
        XCTAssertEqual(overlay.snapshot().reading.unit, .mph)
    }

    // AC-121
    func test_AC121_cornerSelectionMovesOverlayWithHaptic() async {
        let vm = makeVM()
        await vm.scenePhaseChanged(.active)
        vm.selectCorner(.topRight)
        XCTAssertEqual(settings.overlayCorner, .topRight)
        XCTAssertEqual(overlay.snapshot().corner, .topRight)
        XCTAssertEqual(haptics.events.last, "selection")
    }

    // AC-123
    func test_AC123_cornerRestoredOnLaunch() async {
        settings.overlayCorner = .bottomRight
        let vm = makeVM()
        await vm.scenePhaseChanged(.active)
        XCTAssertEqual(overlay.snapshot().corner, .bottomRight)
        XCTAssertEqual(vm.selectedCorner, .bottomRight)
    }

    // AC-124
    func test_AC124_cornerPickerDisabledWhileRecording() async {
        let vm = makeVM()
        await vm.scenePhaseChanged(.active)
        await record(vm)
        XCTAssertFalse(vm.isCornerPickerEnabled)
        vm.selectCorner(.topLeft)
        XCTAssertEqual(settings.overlayCorner, .bottomLeft)
        XCTAssertEqual(engine.beginCalls.first?.corner, .bottomLeft)
        XCTAssertEqual(L10n.appliesNextRecording, "Applies to the next recording")
    }

    // AC-020
    func test_AC020_elapsedTimerFormat() {
        XCTAssertEqual(ElapsedFormat.string(0), "00:00")
        XCTAssertEqual(ElapsedFormat.string(65), "01:05")
        XCTAssertEqual(ElapsedFormat.string(3599), "59:59")
        XCTAssertEqual(ElapsedFormat.string(3600), "1:00:00")
        XCTAssertEqual(ElapsedFormat.string(3725), "1:02:05")
    }

    // AC-020
    func test_AC020_elapsedFollowsRecordingStart() async {
        let vm = makeVM()
        await vm.scenePhaseChanged(.active)
        await record(vm)
        clock.advance(65)
        XCTAssertEqual(vm.elapsedText(), "01:05")
    }

    // AC-061: tapping the thumbnail opens Photos; no in-app library.
    func test_AC061_thumbnailOpensPhotos() async {
        let vm = makeVM()
        vm.openLastClip()
        XCTAssertEqual(opener.opened, ["photos"])
        XCTAssertEqual(haptics.events.last, "selection")
    }

    // AC-110: every action yields immediate visible or haptic feedback.
    func test_AC110_everyActionGivesFeedback() async {
        let vm = makeVM()
        await vm.scenePhaseChanged(.active)
        await record(vm)
        XCTAssertEqual(haptics.events.last, "start")
        clock.advance(1)
        await record(vm)
        XCTAssertTrue(haptics.events.contains("stop"))
        let before = haptics.events.count
        vm.toggleUnit()
        XCTAssertEqual(haptics.events.count, before + 1)
        vm.openLastClip()
        XCTAssertEqual(haptics.events.count, before + 2)
        vm.presentSettings()
        XCTAssertTrue(vm.showSettings)
        XCTAssertEqual(haptics.events.count, before + 3)
    }

    // AC-111: each state presents exactly one obvious next step.
    func test_AC111_oneNextStepPerState() async {
        permissions = FakePermissions(.notDetermined)
        var vm = makeVM(onboarded: false)
        XCTAssertEqual(vm.nextStep, .continueOnboarding)

        permissions = FakePermissions()
        permissions.statuses[.camera] = .denied
        vm = makeVM()
        await vm.scenePhaseChanged(.active)
        XCTAssertEqual(vm.nextStep, .openSettings)

        permissions.statuses[.camera] = .granted
        await vm.scenePhaseChanged(.active)
        XCTAssertEqual(vm.nextStep, .record)
        await record(vm)
        XCTAssertEqual(vm.nextStep, .stop)

        storage.set(megabytes: 10)
        clock.advance(1)
        await record(vm)
        clock.advance(1)
        await record(vm)
        XCTAssertEqual(vm.nextStep, .noticeAction(.ok))
    }

    // AC-077: recovery outcome is told to the user on launch.
    func test_AC077_recoveryOutcomeShown() async throws {
        let url = store.newRecordingURL()
        try Data("broken".utf8).write(to: url)
        let vm = makeVM(useRealSaveService: true)
        await vm.launch(store: store)
        XCTAssertEqual(vm.coordinator.notice?.kind, .unrecoverable)
    }

    // AC-113: empty, denied and GPS-offline states each have icon, one-line text and one action.
    func test_AC113_designedStatesHaveIconTextAndOneAction() {
        for state in DesignedState.allCases {
            XCTAssertFalse(state.icon.isEmpty, "\(state)")
            XCTAssertFalse(state.message.isEmpty, "\(state)")
            XCTAssertFalse(state.message.contains("\n"), "\(state) must be one line")
            XCTAssertFalse(state.actionTitle.isEmpty, "\(state)")
        }
    }
}
#endif
