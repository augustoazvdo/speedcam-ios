import Foundation
import Photos

/// Saves finished clips with add-only access; it never reads the library (R-07).
struct PhotoLibrarySaver: PhotoLibrarySaving {
    static let accessLevel: PHAccessLevel = .addOnly

    func save(videoAt url: URL) async throws(PhotoSaveError) {
        var status = PHPhotoLibrary.authorizationStatus(for: Self.accessLevel)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: Self.accessLevel)
        }
        guard status == .authorized || status == .limited else { throw .denied }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false
                request.addResource(with: .video, fileURL: url, options: options)
            }
        } catch {
            throw .failed
        }
    }
}

#if DEBUG
/// ASM-015: deterministic Photos outcome for UI tests on the Simulator.
struct FakePhotoLibrarySaver: PhotoLibrarySaving {
    let error: PhotoSaveError?
    func save(videoAt url: URL) async throws(PhotoSaveError) {
        try? await Task.sleep(for: .seconds(1.5))
        if let error { throw error }
    }
}
#endif
