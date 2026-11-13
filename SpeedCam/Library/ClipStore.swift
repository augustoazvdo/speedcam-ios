import Foundation

/// Clip files in the app sandbox only (AC-105): `recording/` while being written,
/// `pending/` once finalized and waiting for Photos (AC-006, R-18).
final class ClipStore: ClipURLProviding, @unchecked Sendable {
    let root: URL
    let recordingDirectory: URL
    let pendingDirectory: URL
    let thumbnailURL: URL

    static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Clips", isDirectory: true)
    }

    init(root: URL = ClipStore.defaultRoot) {
        self.root = root
        recordingDirectory = root.appendingPathComponent("recording", isDirectory: true)
        pendingDirectory = root.appendingPathComponent("pending", isDirectory: true)
        thumbnailURL = root.appendingPathComponent("last-clip.jpg")
        let fm = FileManager.default
        for dir in [recordingDirectory, pendingDirectory] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        var rootURL = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? rootURL.setResourceValues(values)
    }

    func newRecordingURL() -> URL {
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        return recordingDirectory.appendingPathComponent("SpeedCam-\(stamp)-\(UUID().uuidString.prefix(4)).mov")
    }

    func markPending(_ url: URL) throws -> URL {
        let destination = pendingDirectory.appendingPathComponent(url.lastPathComponent)
        if url.standardizedFileURL == destination.standardizedFileURL { return destination }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }

    func pendingClips() -> [URL] { movies(in: pendingDirectory) }
    func inProgressClips() -> [URL] { movies(in: recordingDirectory) }

    func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func movies(in directory: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "mov" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
