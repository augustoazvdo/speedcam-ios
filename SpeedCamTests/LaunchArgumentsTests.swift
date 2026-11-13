import XCTest
@testable import SpeedCam

#if DEBUG
final class LaunchArgumentsTests: XCTestCase {
    // AC-090
    func test_AC090_syntheticCameraFlagParsed() {
        let args = LaunchArguments(arguments: ["app", "-SpeedCamSyntheticCamera", "YES"], isSimulator: false)
        XCTAssertTrue(args.syntheticCamera)
        XCTAssertFalse(LaunchArguments(arguments: ["app"], isSimulator: false).syntheticCamera)
    }

    // AC-090: Simulator has no camera, so the synthetic source is on by default there.
    func test_AC090_syntheticCameraDefaultsOnInSimulator() {
        XCTAssertTrue(LaunchArguments(arguments: ["app"], isSimulator: true).syntheticCamera)
        XCTAssertFalse(LaunchArguments(arguments: ["app", "-SpeedCamSyntheticCamera", "NO"], isSimulator: true).syntheticCamera)
    }

    // AC-091
    func test_AC091_simulatedLocationScenarioParsed() {
        let args = LaunchArguments(arguments: ["app", "-SpeedCamSimulatedLocation", "accelerate"], isSimulator: true)
        XCTAssertEqual(args.simulatedLocation, .accelerate)
        XCTAssertNil(LaunchArguments(arguments: ["app", "-SpeedCamSimulatedLocation", "bogus"], isSimulator: true).simulatedLocation)
    }

    // AC-093
    func test_AC093_autoRecordAndExportParsed() {
        let args = LaunchArguments(arguments: ["app", "-SpeedCamAutoRecordSeconds", "5",
                                               "-SpeedCamExportPath", "/tmp/out", "-SpeedCamSkipOnboarding", "YES"],
                                   isSimulator: true)
        XCTAssertEqual(args.autoRecordSeconds, 5)
        XCTAssertEqual(args.exportDirectory?.path, "/tmp/out")
        XCTAssertTrue(args.skipOnboarding)
    }
}
#endif
