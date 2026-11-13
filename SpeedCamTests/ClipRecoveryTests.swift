import AVFoundation
import XCTest
@testable import SpeedCam

#if DEBUG
final class ClipRecoveryTests: XCTestCase {
    private var root: URL!
    private var store: ClipStore!

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("clips-\(UUID().uuidString)")
        store = ClipStore(root: root)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    /// Simulates a crash: frames written with movie fragments, writer never finished.
    private func writeCrashedClip(seconds: Double) throws -> URL {
        let url = store.newRecordingURL()
        let size = CGSize(width: 1920, height: 1080)
        var writer: RecordingWriter? = try RecordingWriter(url: url, videoSize: size, transform: .identity, audioSettings: nil,
                                                           fragmentInterval: CMTime(seconds: 1, preferredTimescale: 600))
        let generator = SyntheticFrameGenerator(size: size)
        for i in 0..<Int(seconds * 30) {
            while !(writer!.isReadyForVideo) { usleep(500) }
            writer!.appendVideo(generator.frame(index: i, date: Date(), orientation: .landscapeRight)!,
                                at: CMTime(value: CMTimeValue(i), timescale: 30))
        }
        Thread.sleep(forTimeInterval: 1)
        writer = nil
        return url
    }

    // AC-077
    func test_AC077_playablePartialClipIsRecoveredToPending() async throws {
        let url = try writeCrashedClip(seconds: 3.5)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let report = await ClipRecovery.recover(store: store)
        XCTAssertEqual(report, RecoveryReport(recovered: 1, unrecoverable: 0))
        XCTAssertTrue(store.inProgressClips().isEmpty)
        XCTAssertEqual(store.pendingClips().count, 1)
        let asset = AVURLAsset(url: store.pendingClips()[0])
        let playable = try await asset.load(.isPlayable)
        XCTAssertTrue(playable)
    }

    // AC-077
    func test_AC077_corruptClipIsReportedUnrecoverable() async throws {
        let url = store.newRecordingURL()
        try Data("not a movie".utf8).write(to: url)
        let report = await ClipRecovery.recover(store: store)
        XCTAssertEqual(report, RecoveryReport(recovered: 0, unrecoverable: 1))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(store.pendingClips().isEmpty)
    }

    // AC-077: nothing to recover → no message.
    func test_AC077_cleanLaunchReportsNothing() async {
        let report = await ClipRecovery.recover(store: store)
        XCTAssertEqual(report, RecoveryReport(recovered: 0, unrecoverable: 0))
        XCTAssertNil(report.notice)
        XCTAssertEqual(RecoveryReport(recovered: 1, unrecoverable: 0).notice, .recovered)
        XCTAssertEqual(RecoveryReport(recovered: 0, unrecoverable: 2).notice, .unrecoverable)
    }

    // AC-105: clips live only in the app sandbox, excluded from backup.
    func test_AC105_clipsStayInSandboxExcludedFromBackup() throws {
        let url = store.newRecordingURL()
        XCTAssertTrue(url.path.hasPrefix(root.path))
        let values = try root.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
        XCTAssertTrue(ClipStore.defaultRoot.path.hasPrefix(NSHomeDirectory()), "default root must be inside the sandbox")
    }

    // AC-006 / AC-062: pending queue survives across store instances.
    func test_AC006_pendingClipsPersist() throws {
        let url = store.newRecordingURL()
        try Data([0]).write(to: url)
        let pending = try store.markPending(url)
        XCTAssertEqual(ClipStore(root: root).pendingClips(), [pending])
        store.remove(pending)
        XCTAssertTrue(store.pendingClips().isEmpty)
    }
}
#endif
