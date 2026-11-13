#if DEBUG
import Foundation

enum SimulatedLocationScenario: String, Sendable, CaseIterable {
    case constant50kmh
    case accelerate
    case invalid
    case noFix
    case weak
}
#endif
