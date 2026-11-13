import AVFoundation
import CoreLocation
import Photos
import UIKit

/// Camera, microphone, location When In Use and Photos add-only (US-01). Never asks for
/// "Always" location or full library access (AC-002, R-06, R-07).
@MainActor
final class PermissionsService: NSObject, PermissionsProviding {
    enum LocationRequest: Equatable {
        case whenInUse
    }

    static let photoAccessLevel: PHAccessLevel = .addOnly
    static let locationRequest = LocationRequest.whenInUse

    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
    }

    func status(_ kind: PermissionKind) -> PermissionStatus {
        switch kind {
        case .camera: Self.map(AVCaptureDevice.authorizationStatus(for: .video))
        case .microphone: Self.map(AVCaptureDevice.authorizationStatus(for: .audio))
        case .location:
            switch CoreLocationProvider.map(manager.authorizationStatus) {
            case .authorized: .granted
            case .denied: .denied
            case .notDetermined: .notDetermined
            }
        case .photos:
            switch PHPhotoLibrary.authorizationStatus(for: Self.photoAccessLevel) {
            case .authorized, .limited: .granted
            case .notDetermined: .notDetermined
            default: .denied
            }
        }
    }

    func request(_ kind: PermissionKind) async -> PermissionStatus {
        guard status(kind) == .notDetermined else { return status(kind) }
        switch kind {
        case .camera:
            _ = await AVCaptureDevice.requestAccess(for: .video)
        case .microphone:
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        case .location:
            await withCheckedContinuation { continuation in
                locationContinuation = continuation
                switch Self.locationRequest {
                case .whenInUse: manager.requestWhenInUseAuthorization()
                }
            }
        case .photos:
            _ = await PHPhotoLibrary.requestAuthorization(for: Self.photoAccessLevel)
        }
        return status(kind)
    }

    private static func map(_ status: AVAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }
}

extension PermissionsService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let determined = manager.authorizationStatus != .notDetermined
        MainActor.assumeIsolated {
            guard determined, let continuation = locationContinuation else { return }
            locationContinuation = nil
            continuation.resume()
        }
    }
}

@MainActor
final class SystemOpener: SystemOpening {
    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Add-only access cannot address a specific asset, so this opens the Photos app (ASM-012).
    func openPhotos() {
        guard let url = URL(string: "photos-redirect://") else { return }
        UIApplication.shared.open(url)
    }
}

#if DEBUG
/// ASM-015 fakes, plus "granted" for hardware that is replaced by a DEBUG simulation.
@MainActor
final class OverridingPermissions: PermissionsProviding {
    private let base: PermissionsProviding
    private var overrides: [PermissionKind: PermissionStatus]

    init(base: PermissionsProviding, overrides: [PermissionKind: PermissionStatus]) {
        self.base = base
        self.overrides = overrides
    }

    func status(_ kind: PermissionKind) -> PermissionStatus {
        overrides[kind] ?? base.status(kind)
    }

    func request(_ kind: PermissionKind) async -> PermissionStatus {
        if let value = overrides[kind] {
            if value == .notDetermined { overrides[kind] = .granted }
            return status(kind)
        }
        return await base.request(kind)
    }
}
#endif
