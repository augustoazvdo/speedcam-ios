import Foundation

struct CameraZoomOption: Identifiable, Equatable, Sendable {
    let factor: CGFloat
    let label: String

    var id: CGFloat { factor }

    static func available(minimum: CGFloat, maximum: CGFloat, switchOvers: [CGFloat],
                          displayMultiplier: CGFloat) -> [CameraZoomOption] {
        guard minimum.isFinite, maximum.isFinite, minimum > 0, maximum >= minimum,
              displayMultiplier.isFinite, displayMultiplier > 0 else { return [] }
        var factors = [minimum]
        if minimum <= 1, maximum >= 1 { factors.append(1) }
        factors += switchOvers.filter { $0.isFinite && $0 >= minimum && $0 <= maximum }
        factors.sort()
        factors = factors.reduce(into: []) { result, factor in
            if let last = result.last, abs(last - factor) < 0.01 { return }
            result.append(factor)
        }
        return factors.map { factor in
            let display = factor * displayMultiplier
            let text = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), Double(display))
                .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
            return CameraZoomOption(factor: factor, label: "\(text)×")
        }
    }
}

protocol CameraZoomControlling: AnyObject, Sendable {
    var zoomOptions: [CameraZoomOption] { get }
    func selectZoom(factor: CGFloat)
}
