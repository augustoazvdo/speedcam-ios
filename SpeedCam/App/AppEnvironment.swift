import AVFoundation
import Foundation

/// Composition root: picks real or DEBUG implementations for every hardware dependency (R-03).
@MainActor
struct AppEnvironment {
    let viewModel: CameraViewModel
    let store: ClipStore
    #if DEBUG
    let autoRecordSeconds: Int?
    #endif

    static func live() -> AppEnvironment {
        let settings = SettingsStore()
        let store = ClipStore()
        let overlay = OverlayStateBox()
        let renderer = OverlayRenderer()
        let captureService = CaptureSessionService()

        var frames: FrameSource = CameraFrameSource(service: captureService, includeAudio: {
            AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        })
        var audio: AudioSampleSource? = AudioSource(service: captureService)
        var location: LocationProvider = CoreLocationProvider()
        var photos: PhotoLibrarySaving = PhotoLibrarySaver()
        var permissions: PermissionsProviding = PermissionsService()
        var storage: StorageMonitoring = StorageMonitor()

        #if DEBUG
        // Test hooks (ASM-010, ASM-015). Compiled out of Release, so the arguments are ignored there (AC-103).
        let args = LaunchArguments()
        if args.resetDefaults {
            settings.reset()
            for url in store.pendingClips() + store.inProgressClips() { store.remove(url) }
            store.remove(store.thumbnailURL)
        }
        if args.skipOnboarding { settings.onboardingCompleted = true }
        var overrides: [PermissionKind: PermissionStatus] = [:]
        if args.syntheticCamera {
            frames = SyntheticFrameSource(orientation: { overlay.displayOrientation })
            audio = SilentAudioSource()
            overrides[.camera] = .granted
            overrides[.microphone] = .granted
        }
        if let scenario = args.simulatedLocation {
            location = SimulatedLocationProvider(scenario: scenario)
            overrides[.location] = .granted
        }
        if let fake = args.fakePermissions {
            overrides = fake
            if fake[.location] == .denied {
                location = SimulatedLocationProvider(scenario: .noFix, authorization: .denied)
            }
            if fake[.microphone] == .denied { audio = nil }
        }
        if !overrides.isEmpty { permissions = OverridingPermissions(base: permissions, overrides: overrides) }
        if let fakePhotos = args.fakePhotos { photos = FakePhotoLibrarySaver(error: fakePhotos) }
        if let mb = args.fakeFreeMegabytes { storage = FixedStorage(bytes: mb * 1_000_000) }
        let saveService = ClipSaveService(store: store, saver: photos, exportDirectory: args.exportDirectory)
        #else
        let saveService = ClipSaveService(store: store, saver: photos)
        #endif

        let pipeline = RecordingPipeline(frames: frames, audio: audio, overlay: overlay, renderer: renderer)
        let coordinator = RecordingCoordinator(engine: pipeline, saver: saveService, urls: store, storage: storage,
                                               clock: SystemClock(), haptics: Haptics(), idleTimer: IdleTimerController())
        let viewModel = CameraViewModel(permissions: permissions, opener: SystemOpener(), location: location,
                                        engine: pipeline, coordinator: coordinator, saveService: saveService,
                                        settings: settings, overlay: overlay, haptics: Haptics(),
                                        thermal: ThermalMonitor(), clock: SystemClock(),
                                        cameraAvailable: frames.isAvailable, cameraZoom: captureService)
        captureService.onEvent = { [weak viewModel] event in
            Task { @MainActor in await viewModel?.handle(event) }
        }
        #if DEBUG
        return AppEnvironment(viewModel: viewModel, store: store, autoRecordSeconds: args.autoRecordSeconds)
        #else
        return AppEnvironment(viewModel: viewModel, store: store)
        #endif
    }
}
