import AppKit
import CoreGraphics
import Foundation

public enum WheelHitTarget: Equatable, Sendable {
    case cancel
    case slice(Int)
}

public struct WheelGeometry {
    /// Hit-tests a point in AppKit coordinates (+y up, +x right) against a radial wheel
    /// whose slice 0 is centered at 12 o'clock and subsequent slices proceed clockwise.
    public static func hitTest(
        point: CGPoint,
        center: CGPoint,
        innerRadius: CGFloat,
        outerRadius: CGFloat,
        sliceCount: Int
    ) -> WheelHitTarget {
        guard sliceCount > 0 else { return .cancel }
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = hypot(dx, dy)
        guard distance >= innerRadius, distance <= outerRadius else {
            return .cancel
        }

        let twoPi = CGFloat.pi * 2.0
        let sliceAngle = twoPi / CGFloat(sliceCount)
        // atan2(dx, dy) gives 0 at 12 o'clock (+y), +pi/2 at 3 o'clock (+x), +/-pi at 6 o'clock (-y), -pi/2 at 9 o'clock (-x).
        var cwFromTop = atan2(dx, dy)
        if cwFromTop < 0 {
            cwFromTop += twoPi
        }
        var shifted = cwFromTop + (sliceAngle / 2.0)
        if shifted >= twoPi {
            shifted -= twoPi
        }
        let index = Int(floor(shifted / sliceAngle)) % sliceCount
        return .slice(index)
    }

    /// Returns center angle in standard AppKit radians (0 = 3 o'clock, +pi/2 = 12 o'clock)
    /// and clockwise start/end degrees for `NSBezierPath.appendArc(..., clockwise: true)`.
    public static func sliceDegrees(index: Int, sliceCount: Int) -> (startDeg: CGFloat, endDeg: CGFloat, midRad: CGFloat) {
        guard sliceCount > 0 else { return (90, 90, .pi / 2) }
        let spanDeg = 360.0 / CGFloat(sliceCount)
        let centerDeg = 90.0 - CGFloat(index) * spanDeg
        let startDeg = centerDeg + spanDeg / 2.0
        let endDeg = centerDeg - spanDeg / 2.0
        return (startDeg, endDeg, centerDeg * .pi / 180.0)
    }
}

public extension ModifierTrigger {
    func matches(flags: NSEvent.ModifierFlags) -> Bool {
        switch self {
        case .shift:
            return flags.contains(.shift)
        case .option:
            return flags.contains(.option)
        case .control:
            return flags.contains(.control)
        }
    }
}
