import Foundation

/// Every user-facing string, resolved from Localizable.xcstrings (R-17, AC-132).
enum L10n {
    // Onboarding
    static var welcomeTitle: String { String(localized: "Welcome to SpeedCam") }
    static var welcomeBody: String { String(localized: "Record your drive with your speed burned into the video. SpeedCam needs:") }
    static var permCamera: String { String(localized: "Camera") }
    static var permCameraReason: String { String(localized: "Records the road ahead.") }
    static var permMicrophone: String { String(localized: "Microphone") }
    static var permMicrophoneReason: String { String(localized: "Adds sound to your clips. Optional.") }
    static var permLocation: String { String(localized: "Location (While Using)") }
    static var permLocationReason: String { String(localized: "Measures your speed only while the app is open.") }
    static var permPhotos: String { String(localized: "Photos (add only)") }
    static var permPhotosReason: String { String(localized: "Saves finished clips. SpeedCam can't see your library.") }
    static var continueAction: String { String(localized: "Continue") }

    // Camera screen states
    static var cameraDenied: String { String(localized: "Camera access is off. SpeedCam needs it to record.") }
    static var cameraNotDetermined: String { String(localized: "SpeedCam needs camera access to record.") }
    static var cameraUnavailable: String { String(localized: "The camera isn't available right now.") }
    static var allowCamera: String { String(localized: "Allow Camera") }
    static var openSettings: String { String(localized: "Open Settings") }
    static var tryAgain: String { String(localized: "Try Again") }
    static var ok: String { String(localized: "OK") }
    static var micOffBadge: String { String(localized: "No audio — Mic off") }
    static var micOffDetail: String { String(localized: "Microphone access is off. Clips are recorded without sound.") }
    static var locationOffBanner: String { String(localized: "Location is off — speed won't be recorded") }
    static var noFixBanner: String { String(localized: "Searching for GPS — you can still record") }
    static var noClipsYet: String { String(localized: "No clips yet") }
    static var lastClip: String { String(localized: "Last clip — opens Photos") }
    static var record: String { String(localized: "Record") }
    static var stop: String { String(localized: "Stop") }
    static var recording: String { String(localized: "Recording") }
    static var settings: String { String(localized: "Settings") }
    static var switchUnit: String { String(localized: "Switch speed unit") }
    static var saving: String { String(localized: "Saving…") }
    static var savedToPhotos: String { String(localized: "✓ Saved to Photos") }
    static var preview: String { String(localized: "Camera preview") }

    // Settings sheet
    static var speedUnit: String { String(localized: "Speed unit") }
    static var overlayCorner: String { String(localized: "Overlay corner") }
    static var cornerTopLeft: String { String(localized: "Top left") }
    static var cornerTopRight: String { String(localized: "Top right") }
    static var cornerBottomLeft: String { String(localized: "Bottom left") }
    static var cornerBottomRight: String { String(localized: "Bottom right") }
    static var appliesNextRecording: String { String(localized: "Applies to the next recording") }
    static var done: String { String(localized: "Done") }

    // Notices (one cause, one action: R-15, AC-078)
    static var storageTooLow: String { String(localized: "Not enough storage — free up space to record") }
    static var storageStopped: String { String(localized: "Recording stopped — storage almost full") }
    static var stoppedByCall: String { String(localized: "Recording stopped by a call — clip saved") }
    static var stoppedByBackground: String { String(localized: "Recording stopped when the app closed — clip saved") }
    static var cameraRevoked: String { String(localized: "Camera access was turned off — clip saved") }
    static var cameraFailed: String { String(localized: "Recording stopped — the camera stopped working") }
    static var phoneHot: String { String(localized: "Phone is hot — recording may stop") }
    static var phoneTooHot: String { String(localized: "Recording stopped — phone too hot") }
    static var photosDenied: String { String(localized: "Couldn't save to Photos — access is off") }
    static var photosFailed: String { String(localized: "Couldn't save to Photos — the clip is kept on this iPhone") }
    static var writeFailed: String { String(localized: "Recording failed — the video couldn't be written") }
    static var recovered: String { String(localized: "A clip from the last session was recovered") }
    static var unrecoverable: String { String(localized: "A clip from the last session couldn't be recovered") }

    // Overlay (burned into the video)
    static var gpsGood: String { String(localized: "GPS") }
    static var gpsWeak: String { String(localized: "GPS weak") }
    static var gpsNoFix: String { String(localized: "No GPS fix") }
    static var gpsOff: String { String(localized: "GPS off") }

    static func corner(_ corner: OverlayCorner) -> String {
        switch corner {
        case .topLeft: cornerTopLeft
        case .topRight: cornerTopRight
        case .bottomLeft: cornerBottomLeft
        case .bottomRight: cornerBottomRight
        }
    }
}
