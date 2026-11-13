import AVFoundation
import Foundation
import os
import UIKit

/// Finished clip → pending queue → thumbnail → Photos → delete sandbox copy only on success (R-18, AC-062).
@MainActor
final class ClipSaveService: ClipSaving {
    private let store: ClipStore
    private let saver: PhotoLibrarySaving
    private let logger = Logger(subsystem: "com.augusto.speedcam", category: "save")
    private(set) var lastThumbnail: UIImage?
    #if DEBUG
    private let exportDirectory: URL?
    private(set) var lastExportURL: URL?
    #endif

    #if DEBUG
    init(store: ClipStore, saver: PhotoLibrarySaving, exportDirectory: URL? = nil) {
        self.store = store
        self.saver = saver
        self.exportDirectory = exportDirectory
        lastThumbnail = UIImage(contentsOfFile: store.thumbnailURL.path)
    }
    #else
    init(store: ClipStore, saver: PhotoLibrarySaving) {
        self.store = store
        self.saver = saver
        lastThumbnail = UIImage(contentsOfFile: store.thumbnailURL.path)
    }
    #endif

    func process(_ url: URL) async -> SaveOutcome {
        let pending: URL
        do {
            pending = try store.markPending(url)
        } catch {
            logger.error("could not move clip to pending")
            return .failed
        }
        await makeThumbnail(from: pending)
        #if DEBUG
        export(pending)
        #endif
        return await save(pending)
    }

    /// Retries every pending clip (after Photos access is granted, or after recovery). Nil when nothing was pending.
    func flushPending() async -> SaveOutcome? {
        let pending = store.pendingClips()
        guard !pending.isEmpty else { return nil }
        var result = SaveOutcome.saved
        for url in pending {
            let outcome = await save(url)
            if outcome != .saved { result = outcome }
        }
        return result
    }

    var hasPending: Bool { !store.pendingClips().isEmpty }

    private func save(_ url: URL) async -> SaveOutcome {
        do throws(PhotoSaveError) {
            try await saver.save(videoAt: url)
            store.remove(url)
            return .saved
        } catch .denied {
            return .denied
        } catch {
            return .failed
        }
    }

    private func makeThumbnail(from url: URL) async {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 360, height: 360)
        guard let cgImage = try? await generator.image(at: .zero).image else { return }
        let image = UIImage(cgImage: cgImage)
        if let data = image.jpegData(compressionQuality: 0.8) {
            try? data.write(to: store.thumbnailURL, options: .atomic)
        }
        lastThumbnail = image
    }

    #if DEBUG
    private func export(_ url: URL) {
        guard let exportDirectory else { return }
        let destination = exportDirectory.appendingPathComponent(url.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: url, to: destination)
            lastExportURL = destination
            print("SPEEDCAM_EXPORT=\(destination.path)")
            logger.notice("SPEEDCAM_EXPORT=\(destination.path, privacy: .public)")
        } catch {
            print("SPEEDCAM_EXPORT_FAILED=\(error.localizedDescription)")
        }
    }
    #endif
}
