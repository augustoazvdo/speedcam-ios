import Foundation
import SwiftUI

/// Maps capture-session events and scene-phase changes to stop reasons (AC-072, AC-073).
enum CaptureEvent: Equatable, Sendable {
    /// Phone call, Siri, another app taking the camera or audio.
    case interrupted
    case interruptionEnded
    case runtimeError
}

enum InterruptionMonitor {
    static func stopReason(for event: CaptureEvent) -> StopReason? {
        switch event {
        case .interrupted: .interruption
        case .runtimeError: .cameraFailed
        case .interruptionEnded: nil
        }
    }

    /// Recording is foreground-only (ASM-005): leaving the foreground stops and saves.
    static func stopReason(for phase: ScenePhase) -> StopReason? {
        phase == .background ? .background : nil
    }
}
