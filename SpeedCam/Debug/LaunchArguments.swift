#if DEBUG
import Foundation

/// DEBUG-only test hooks (ASM-010, R-04). Release builds compile this file out, so the
/// arguments have no effect there (AC-103).
struct LaunchArguments: Sendable {
    var syntheticCamera: Bool
    var simulatedLocation: SimulatedLocationScenario?
    var autoRecordSeconds: Int?
    var exportDirectory: URL?
    var skipOnboarding: Bool
    var resetDefaults: Bool
    /// ASM-015: deterministic permission/Photos fakes for UI tests.
    var fakePermissions: [PermissionKind: PermissionStatus]?
    var fakePhotos: PhotoSaveError??
    var fakeFreeMegabytes: Int64?

    init(arguments: [String] = ProcessInfo.processInfo.arguments, isSimulator: Bool = LaunchArguments.runningInSimulator) {
        func value(_ key: String) -> String? {
            guard let index = arguments.lastIndex(of: "-\(key)"), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        func flag(_ key: String) -> Bool? {
            value(key).map { ["yes", "true", "1"].contains($0.lowercased()) }
        }

        syntheticCamera = flag("SpeedCamSyntheticCamera") ?? isSimulator
        simulatedLocation = value("SpeedCamSimulatedLocation").flatMap(SimulatedLocationScenario.init(rawValue:))
        autoRecordSeconds = value("SpeedCamAutoRecordSeconds").flatMap(Int.init).flatMap { $0 > 0 ? $0 : nil }
        exportDirectory = value("SpeedCamExportPath").map { URL(fileURLWithPath: $0, isDirectory: true) }
        skipOnboarding = flag("SpeedCamSkipOnboarding") ?? false
        resetDefaults = flag("SpeedCamResetDefaults") ?? false
        fakeFreeMegabytes = value("SpeedCamFakeFreeMB").flatMap(Int64.init)

        if let spec = value("SpeedCamFakePermissions") {
            var map = Dictionary(uniqueKeysWithValues: PermissionKind.allCases.map { ($0, PermissionStatus.granted) })
            for pair in spec.split(separator: ",") {
                let parts = pair.split(separator: "=").map(String.init)
                guard parts.count == 2, let kind = PermissionKind(rawValue: parts[0]) else { continue }
                switch parts[1] {
                case "denied": map[kind] = .denied
                case "notDetermined": map[kind] = .notDetermined
                default: map[kind] = .granted
                }
            }
            fakePermissions = map
        } else {
            fakePermissions = nil
        }

        switch value("SpeedCamFakePhotos") {
        case "success": fakePhotos = .some(nil)
        case "denied": fakePhotos = .some(.denied)
        case "fail": fakePhotos = .some(.failed)
        default: fakePhotos = nil
        }
    }

    static var runningInSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    static var isHostingUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
#endif
