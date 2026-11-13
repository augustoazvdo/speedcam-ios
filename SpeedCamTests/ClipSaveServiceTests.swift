import AVFoundation
import Photos
import XCTest
@testable import SpeedCam

final class FakePhotoSaver: PhotoLibrarySaving, @unchecked Sendable {
    private let lock = NSLock()
    private var _result: PhotoSaveError?
    private var _saved: [URL] = []
    var result: PhotoSaveError? {
        get { lock.withLock { _result } }
        set { lock.withLock { _result = newValue } }
    }
    var saved: [URL] { lock.withLock { _saved } }

    func save(videoAt url: URL) async throws(PhotoSaveError) {
        // The file must still exist while Photos imports it.
        guard FileManager.default.fileExists(atPath: url.path) else { throw .failed }
        if let error = result { throw error }
        lock.withLock { _saved.append(url) }
    }
}

#if DEBUG
@MainActor
final class ClipSaveServiceTests: XCTestCase {
    private var root: URL!
    private var store: ClipStore!
    private var photos: FakePhotoSaver!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("save-\(UUID().uuidString)")
        store = ClipStore(root: root)
        photos = FakePhotoSaver()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeClip() async throws -> URL {
        let url = store.newRecordingURL()
        let size = CGSize(width: 1920, height: 1080)
        let writer = try RecordingWriter(url: url, videoSize: size, transform: .identity, audioSettings: nil)
        let generator = SyntheticFrameGenerator(size: size)
        for i in 0..<15 {
            while !writer.isReadyForVideo { usleep(500) }
            writer.appendVideo(generator.frame(index: i, date: Date(), orientation: .landscapeRight)!, at: CMTime(value: CMTimeValue(i), timescale: 30))
        }
        _ = await writer.finish()
        return url
    }

    // AC-060 / AC-062: success saves to Photos then deletes the sandbox copy (R-18).
    func test_AC062_successDeletesSandboxCopy() async throws {
        let sut = ClipSaveService(store: store, saver: photos)
        let url = try await makeClip()
        let outcome = await sut.process(url)
        XCTAssertEqual(outcome, .saved)
        XCTAssertEqual(photos.saved.count, 1)
        XCTAssertTrue(store.pendingClips().isEmpty)
        XCTAssertTrue(store.inProgressClips().isEmpty)
    }

    // AC-061 / ASM-012: thumbnail from the first frame is generated before deletion and kept.
    func test_AC061_thumbnailGeneratedBeforeDeletion() async throws {
        let sut = ClipSaveService(store: store, saver: photos)
        XCTAssertNil(sut.lastThumbnail)
        _ = await sut.process(try await makeClip())
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.thumbnailURL.path))
        let thumbnail = try XCTUnwrap(sut.lastThumbnail)
        XCTAssertGreaterThan(thumbnail.size.width, 50)
        XCTAssertNotNil(ClipSaveService(store: store, saver: photos).lastThumbnail, "thumbnail survives relaunch")
    }

    // AC-006 / AC-062: denied keeps the clip pending; once access is granted the pending clip is saved.
    func test_AC006_deniedKeepsPendingThenRetries() async throws {
        let sut = ClipSaveService(store: store, saver: photos)
        photos.result = .denied
        let outcome = await sut.process(try await makeClip())
        XCTAssertEqual(outcome, .denied)
        XCTAssertEqual(store.pendingClips().count, 1)

        photos.result = nil
        let saved = await sut.flushPending()
        XCTAssertEqual(saved, .saved)
        XCTAssertEqual(photos.saved.count, 1)
        XCTAssertTrue(store.pendingClips().isEmpty)
    }

    // AC-062: generic failure keeps the clip too.
    func test_AC062_failureKeepsPending() async throws {
        let sut = ClipSaveService(store: store, saver: photos)
        photos.result = .failed
        let outcome = await sut.process(try await makeClip())
        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(store.pendingClips().count, 1)
    }

    // AC-006: nothing pending → nothing to report.
    func test_AC006_flushWithNothingPending() async {
        let outcome = await ClipSaveService(store: store, saver: photos).flushPending()
        XCTAssertNil(outcome)
    }

    // AC-093: export hook copies the clip before the sandbox copy is deleted.
    func test_AC093_exportCopiesClip() async throws {
        let exportDir = root.appendingPathComponent("export", isDirectory: true)
        let sut = ClipSaveService(store: store, saver: photos, exportDirectory: exportDir)
        _ = await sut.process(try await makeClip())
        let exported = try FileManager.default.contentsOfDirectory(at: exportDir, includingPropertiesForKeys: nil)
        XCTAssertEqual(exported.filter { $0.pathExtension == "mov" }.count, 1)
        XCTAssertEqual(sut.lastExportURL?.deletingLastPathComponent().standardizedFileURL, exportDir.standardizedFileURL)
    }

    // AC-105 / R-07: the real saver only ever asks for add-only access.
    func test_AC105_photoSaverUsesAddOnlyAccess() {
        XCTAssertEqual(PhotoLibrarySaver.accessLevel, .addOnly)
    }
}
#endif
