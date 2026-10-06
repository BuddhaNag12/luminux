import QuartzCore
import SwiftUI

/// Like `rotation3DEffect`, but returns an exact identity at 0°. The built-in effect keeps its perspective term at rest,
/// which throws off hit testing for scroll views inside the rotated view.
struct PerspectiveRotation: GeometryEffect {
    var angle: Double
    var axis: (x: CGFloat, y: CGFloat, z: CGFloat)
    var anchor: UnitPoint = .center
    var perspective: CGFloat = 1

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        guard angle != 0, axis != (0, 0, 0) else { return ProjectionTransform() }
        let anchorX = anchor.x * size.width
        let anchorY = anchor.y * size.height

        var depth = CATransform3DIdentity
        depth.m34 = -perspective / max(size.width, size.height, 1)

        var transform = CATransform3DMakeTranslation(-anchorX, -anchorY, 0)
        transform = CATransform3DConcat(transform, CATransform3DMakeRotation(angle * .pi / 180, axis.x, axis.y, axis.z))
        transform = CATransform3DConcat(transform, depth)
        transform = CATransform3DConcat(transform, CATransform3DMakeTranslation(anchorX, anchorY, 0))
        return ProjectionTransform(transform)
    }
}

extension View {
    func perspectiveRotation(
        _ degrees: Double,
        axis: (x: CGFloat, y: CGFloat, z: CGFloat),
        anchor: UnitPoint = .center,
        perspective: CGFloat = 1
    ) -> some View {
        modifier(PerspectiveRotation(angle: degrees, axis: axis, anchor: anchor, perspective: perspective))
    }
}
