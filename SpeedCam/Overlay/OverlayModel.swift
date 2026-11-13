import CoreGraphics
import Foundation

/// Interface orientation of the recording (UIInterfaceOrientation semantics).
/// Sensor buffers stay landscape; the track transform makes them upright (design §6).
enum CaptureOrientation: String, Sendable, CaseIterable {
    case portrait
    case portraitUpsideDown
    case landscapeLeft
    case landscapeRight

    /// Clockwise rotation that turns a back-camera sensor buffer upright.
    var rotationDegrees: Int {
        switch self {
        case .landscapeRight: 0
        case .portrait: 90
        case .landscapeLeft: 180
        case .portraitUpsideDown: 270
        }
    }

    var isPortrait: Bool { self == .portrait || self == .portraitUpsideDown }

    func uprightSize(for bufferSize: CGSize) -> CGSize {
        rotationDegrees % 180 == 0 ? bufferSize : CGSize(width: bufferSize.height, height: bufferSize.width)
    }

    /// Track transform in top-left-origin pixel space (`AVAssetWriterInput.transform`).
    func trackTransform(bufferSize size: CGSize) -> CGAffineTransform {
        let w = size.width, h = size.height
        switch rotationDegrees {
        case 90: return CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0)
        case 180: return CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: w, ty: h)
        case 270: return CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w)
        default: return .identity
        }
    }

    /// Same rotation expressed in Core Image's bottom-left-origin space.
    func ciTransform(bufferSize size: CGSize) -> CGAffineTransform {
        let upright = uprightSize(for: size)
        let flipBuffer = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size.height)
        let flipUpright = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: upright.height)
        return flipBuffer.concatenating(trackTransform(bufferSize: size)).concatenating(flipUpright)
    }
}

/// Snapshot read by the renderer on the video queue.
struct OverlayModel: Sendable, Equatable {
    var reading: SpeedReading
    var date: Date
    var orientation: CaptureOrientation
    var corner: OverlayCorner
    var locale: Locale = .current
    var timeZone: TimeZone = .current
}

enum OverlayFormat {
    /// ASM-016: fixed `dd/MM/yyyy HH:mm:ss` in device local time for every locale.
    static func timestamp(_ date: Date, timeZone: TimeZone, locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.day, .month, .year, .hour, .minute, .second], from: date)
        func n(_ value: Int?, _ digits: Int) -> String {
            (value ?? 0).formatted(.number.grouping(.never).precision(.integerLength(digits...)).locale(locale))
        }
        return "\(n(c.day, 2))/\(n(c.month, 2))/\(n(c.year, 4)) \(n(c.hour, 2)):\(n(c.minute, 2)):\(n(c.second, 2))"
    }

    static func gpsLabel(_ status: GPSStatus) -> String {
        switch status {
        case .good: L10n.gpsGood
        case .weak: L10n.gpsWeak
        case .noFix: L10n.gpsNoFix
        case .off: L10n.gpsOff
        }
    }
}

/// Lock-protected overlay state shared between the main actor and the video queue.
final class OverlayStateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var reading = SpeedReading.unavailable(.kmh, gps: .noFix)
    private var liveOrientation = CaptureOrientation.portrait
    private var liveCorner = OverlayCorner.default
    private var locked: (orientation: CaptureOrientation, corner: OverlayCorner)?

    func update(reading: SpeedReading) {
        lock.withLock { self.reading = reading }
    }

    func update(orientation: CaptureOrientation) {
        lock.withLock { liveOrientation = orientation }
    }

    func update(corner: OverlayCorner) {
        lock.withLock { liveCorner = corner }
    }

    /// Orientation and corner are locked at record start (ASM-009, ASM-013); unit/speed are not (AC-082).
    func lock(orientation: CaptureOrientation, corner: OverlayCorner) {
        lock.withLock { locked = (orientation, corner) }
    }

    func unlock() {
        lock.withLock { locked = nil }
    }

    var displayOrientation: CaptureOrientation {
        lock.withLock { liveOrientation }
    }

    func snapshot(date: Date) -> OverlayModel {
        lock.withLock {
            OverlayModel(reading: reading, date: date,
                         orientation: locked?.orientation ?? liveOrientation,
                         corner: locked?.corner ?? liveCorner)
        }
    }
}
