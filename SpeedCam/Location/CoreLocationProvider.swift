import CoreLocation
import Foundation

/// CoreLocation speed source (ASM-001). When In Use only; the view model starts it only
/// while the app is in the foreground and stops it on background (R-06, AC-102).
/// Works with `xcrun simctl location` in the Simulator (AC-092).
@MainActor
final class CoreLocationProvider: NSObject, LocationProvider {
    let manager = CLLocationManager()

    var onSample: ((LocationSample) -> Void)?
    var onAuthorizationChange: ((LocationAuthorization) -> Void)?
    private(set) var isRunning = false

    override init() {
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.activityType = .automotiveNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = false
        manager.delegate = self
    }

    var authorization: LocationAuthorization {
        Self.map(manager.authorizationStatus)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        manager.startUpdatingLocation()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        manager.stopUpdatingLocation()
    }

    func setRecordingMode(_ recording: Bool) {
        manager.desiredAccuracy = recording ? kCLLocationAccuracyBestForNavigation : kCLLocationAccuracyNearestTenMeters
    }

    nonisolated static func sample(from location: CLLocation) -> LocationSample {
        LocationSample(speedMps: location.speed, speedAccuracy: location.speedAccuracy,
                       horizontalAccuracy: location.horizontalAccuracy, timestamp: location.timestamp)
    }

    nonisolated static func map(_ status: CLAuthorizationStatus) -> LocationAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .authorizedWhenInUse, .authorizedAlways: .authorized
        default: .denied
        }
    }
}

extension CoreLocationProvider: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let samples = locations.map(Self.sample(from:))
        MainActor.assumeIsolated {
            for sample in samples { onSample?(sample) }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = Self.map(manager.authorizationStatus)
        MainActor.assumeIsolated {
            onAuthorizationChange?(status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {}
}
