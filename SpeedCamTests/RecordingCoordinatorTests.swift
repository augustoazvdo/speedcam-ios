import XCTest
@testable import SpeedCam

@MainActor
final class RecordingCoordinatorTests: XCTestCase {
    private var engine: FakeEngine!
    private var saver: FakeClipSaver!
    private var storage: FakeStorage!
    private var clock: ManualClock!
    private var haptics: FakeHaptics!
    private var idle: FakeIdleTimer!
    private var sut: RecordingCoordinator!

    override func setUp() async throws {
        engine = FakeEngine()
        saver = FakeClipSaver()
        storage = FakeStorage()
        clock = ManualClock()
        haptics = FakeHaptics()
        idle = FakeIdleTimer()
        sut = RecordingCoordinator(engine: engine, saver: saver, urls: FakeClipURLs(), storage: storage,
                                   clock: clock, haptics: haptics, idleTimer: idle, storagePollInterval: nil)
    }

    private func start(_ orientation: CaptureOrientation = .landscapeRight, corner: OverlayCorner = .bottomLeft) async {
        await sut.toggle(orientation: orientation, corner: corner, includeAudio: true)
    }

    // AC-020
    func test_AC020_startShowsRecordingStateAndHapticWithin500ms() async {
        let began = Date()
        await start()
        XCTAssertLessThan(Date().timeIntervalSince(began), 0.5)
        XCTAssertEqual(sut.state, .recording(since: clock.now()))
        XCTAssertEqual(haptics.events, ["start"])
        XCTAssertEqual(engine.beginCalls.count, 1)
    }

    // AC-020 / AC-052 / ASM-013: orientation and corner passed to the engine at start.
    func test_AC052_orientationAndCornerLockedAtStart() async {
        await start(.portrait, corner: .topRight)
        XCTAssertEqual(engine.beginCalls.first?.orientation, .portrait)
        XCTAssertEqual(engine.beginCalls.first?.corner, .topRight)
    }

    // AC-021
    func test_AC021_stopShowsSavingThenIdleWithHaptic() async {
        await start()
        clock.advance(2)
        engine.holdFinish = true
        let stopTask = Task { await sut.toggle(orientation: .landscapeRight, corner: .bottomLeft, includeAudio: true) }
        await settle()
        XCTAssertEqual(sut.state, .finishing)
        XCTAssertTrue(sut.isSaving)
        XCTAssertEqual(haptics.events, ["start", "stop"])
        engine.resumeFinish()
        await stopTask.value
        XCTAssertEqual(sut.state, .idle)
        XCTAssertFalse(sut.isSaving)
    }

    // AC-060
    func test_AC060_successfulSaveShowsToast() async {
        await start()
        clock.advance(2)
        await sut.stop(.user)
        XCTAssertEqual(saver.processed.count, 1)
        XCTAssertEqual(sut.toast, .savedToPhotos)
        XCTAssertEqual(L10n.savedToPhotos, "✓ Saved to Photos")
        XCTAssertNil(sut.notice)
    }

    // AC-022
    func test_AC022_idleTimerDisabledOnlyWhileRecording() async {
        XCTAssertFalse(idle.isIdleTimerDisabled)
        await start()
        XCTAssertTrue(idle.isIdleTimerDisabled)
        clock.advance(1)
        await sut.stop(.user)
        XCTAssertFalse(idle.isIdleTimerDisabled)
    }

    // AC-023
    func test_AC023_doubleTapIsDebounced() async {
        await start()
        clock.advance(0.2)
        await start()
        XCTAssertEqual(engine.beginCalls.count, 1)
        XCTAssertEqual(engine.finishCount, 0)
        XCTAssertEqual(sut.state, .recording(since: clock.now() - 0.2))
        clock.advance(0.5)
        await start()
        XCTAssertEqual(engine.finishCount, 1)
    }

    // AC-023: taps while finishing are ignored.
    func test_AC023_tapWhileFinishingIgnored() async {
        await start()
        clock.advance(1)
        engine.holdFinish = true
        let stopTask = Task { await sut.stop(.user) }
        await settle()
        clock.advance(1)
        await start()
        XCTAssertEqual(engine.beginCalls.count, 1)
        engine.resumeFinish()
        await stopTask.value
    }

    // AC-023: an empty recording produces no file to save and no error.
    func test_AC023_emptyRecordingIsDiscarded() async {
        await start()
        clock.advance(1)
        engine.result = .empty
        await sut.stop(.user)
        XCTAssertTrue(saver.processed.isEmpty)
        XCTAssertNil(sut.notice)
        XCTAssertEqual(sut.state, .idle)
    }

    // AC-070
    func test_AC070_lowStorageBlocksStart() async {
        storage.set(megabytes: 499)
        await start()
        XCTAssertTrue(engine.beginCalls.isEmpty)
        XCTAssertEqual(sut.state, .idle)
        XCTAssertEqual(sut.notice?.kind, .storageTooLow)
        XCTAssertEqual(sut.notice?.kind.message, "Not enough storage — free up space to record")
        XCTAssertEqual(sut.notice?.kind.action, .ok)
    }

    // AC-071
    func test_AC071_storageDropBelow200MBStopsAndSaves() async {
        await start()
        storage.set(megabytes: 250)
        await sut.checkStorage()
        XCTAssertNotEqual(sut.state, .idle)
        storage.set(megabytes: 199)
        await sut.checkStorage()
        XCTAssertEqual(engine.finishCount, 1)
        XCTAssertEqual(saver.processed.count, 1)
        XCTAssertEqual(sut.notice?.kind, .storageStopped)
        XCTAssertEqual(sut.notice?.kind.message, "Recording stopped — storage almost full")
    }

    // AC-072
    func test_AC072_interruptionFinalizesAndSaves() async {
        await start()
        await sut.stop(.interruption)
        XCTAssertEqual(engine.finishCount, 1)
        XCTAssertEqual(saver.processed.count, 1)
        XCTAssertEqual(sut.notice?.kind.message, "Recording stopped by a call — clip saved")
    }

    // AC-073
    func test_AC073_backgroundFinalizesAndSaves() async {
        await start()
        await sut.stop(.background)
        XCTAssertEqual(engine.finishCount, 1)
        XCTAssertEqual(saver.processed.count, 1)
        XCTAssertEqual(sut.notice?.kind.message, "Recording stopped when the app closed — clip saved")
    }

    // AC-074
    func test_AC074_cameraRevokeStopsWithOpenSettings() async {
        await start()
        await sut.stop(.cameraRevoked)
        XCTAssertEqual(engine.finishCount, 1)
        XCTAssertEqual(saver.processed.count, 1)
        XCTAssertEqual(sut.notice?.kind, .cameraRevoked)
        XCTAssertEqual(sut.notice?.kind.action, .openSettings)
    }

    // AC-075: no GPS never blocks or stops recording (coordinator has no location input at all).
    func test_AC075_recordingIgnoresGPSState() async {
        await start()
        XCTAssertNil(sut.notice)
        XCTAssertEqual(sut.state, .recording(since: clock.now()))
    }

    // AC-076
    func test_AC076_thermalSeriousWarnsCriticalStops() async {
        await start()
        await sut.thermalChanged(.serious)
        XCTAssertEqual(sut.notice?.kind, .phoneHot)
        XCTAssertEqual(sut.notice?.kind.message, "Phone is hot — recording may stop")
        XCTAssertEqual(engine.finishCount, 0)
        await sut.thermalChanged(.critical)
        XCTAssertEqual(engine.finishCount, 1)
        XCTAssertEqual(saver.processed.count, 1)
        XCTAssertEqual(sut.notice?.kind.message, "Recording stopped — phone too hot")
    }

    // R-09 / AC-072 / AC-073 / AC-071 / AC-076 / AC-074: every stop path finalizes the writer exactly once.
    func test_AC078_everyStopReasonFinalizesOnce() async throws {
        for reason in StopReason.allCases {
            try await setUp()
            await start()
            clock.advance(1)
            await sut.stop(reason)
            XCTAssertEqual(engine.finishCount, 1, "\(reason)")
            XCTAssertEqual(sut.state, .idle, "\(reason)")
            await sut.stop(reason)
            XCTAssertEqual(engine.finishCount, 1, "second stop must be a no-op for \(reason)")
        }
    }

    // AC-006 / AC-062: Photos denied keeps the clip pending and explains with Open Settings.
    func test_AC006_photosDeniedShowsOpenSettings() async {
        saver.outcome = .denied
        await start()
        clock.advance(1)
        await sut.stop(.user)
        XCTAssertEqual(sut.notice?.kind, .photosDenied)
        XCTAssertEqual(sut.notice?.kind.message, "Couldn't save to Photos — access is off")
        XCTAssertEqual(sut.notice?.kind.action, .openSettings)
        XCTAssertNil(sut.toast)
    }

    // AC-078: writer failure is reported with a specific cause and one action.
    func test_AC078_writeFailureReported() async {
        await start()
        clock.advance(1)
        engine.result = .failed
        await sut.stop(.user)
        XCTAssertEqual(sut.notice?.kind, .writeFailed)
        XCTAssertTrue(saver.processed.isEmpty)
    }

    // AC-078: begin failure is reported, state returns to idle.
    func test_AC078_beginFailureReported() async {
        engine.beginError = NSError(domain: "x", code: 1)
        await start()
        XCTAssertEqual(sut.state, .idle)
        XCTAssertEqual(sut.notice?.kind, .writeFailed)
        XCTAssertFalse(idle.isIdleTimerDisabled)
    }

    // AC-078 / R-15: every notice names a specific cause and has exactly one primary action.
    func test_AC078_everyNoticeHasSpecificMessageAndOneAction() {
        let messages = NoticeKind.allCases.map(\.message)
        XCTAssertEqual(Set(messages).count, messages.count, "messages must be distinct (specific)")
        for kind in NoticeKind.allCases {
            XCTAssertGreaterThan(kind.message.count, 15, "\(kind)")
            XCTAssertFalse(kind.actionTitle.isEmpty, "\(kind)")
            XCTAssertFalse(kind.icon.isEmpty, "\(kind)")
        }
    }

    // AC-078: notices can be dismissed via their action.
    func test_AC078_dismissNotice() async {
        storage.set(megabytes: 10)
        await start()
        XCTAssertNotNil(sut.notice)
        sut.dismissNotice()
        XCTAssertNil(sut.notice)
    }
}
