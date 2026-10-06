import QuartzCore
import SwiftUI

/// The staggered "feathered" turnstile: when a page opens or closes, its tiles swing on a hinge at the left of the screen
/// one after another, top to bottom and left to right, instead of the page turning as one sheet.
enum Feather {
    /// Items start here and swing to 0 when their page opens.
    static let enterAngle: Double = -80
    /// Items swing here when another page covers theirs.
    static let coverAngle: Double = 50
    /// Items swing here when their page is closed with `Navigator.pop()`.
    static let leaveAngle: Double = -80

    /// Lets the outgoing tiles start moving before the incoming ones.
    static let enterBaseDelay: Double = 0.16
    static let rowDelay: Double = 0.03
    static let columnDelay: Double = 0.01
    /// Rows past this many below the top of the screen are off screen, so they share its delay.
    static let visibleRows = 9

    static func animation(toward angle: Double, row: Int, column: Int) -> Animation {
        let stagger = Double(min(max(row, 0), visibleRows)) * rowDelay + Double(column) * columnDelay
        return angle == 0
            ? .spring(response: 0.32, dampingFraction: 1).delay(enterBaseDelay + stagger)
            : .easeIn(duration: 0.18).delay(stagger * 0.6)
    }
}

/// The first visible row of a scrolling grid, so rows scrolled above the screen don't hold up the visible ones.
@Observable
final class FeatherRowOrigin {
    var row = 0
}

extension EnvironmentValues {
    /// Where this page's feathered items should rest: 0 while the page is showing.
    @Entry var featherAngle: Double = 0
    @Entry var featherRowOrigin: FeatherRowOrigin?
}

extension View {
    /// Swings this item with its page. `row` and `column` set its place in the stagger; `column` and `spacing`
    /// also put the hinge at the left edge of the grid rather than the item.
    func metroFeather(row: Int, column: Int = 0, spacing: CGFloat = MetroMetrics.gutter) -> some View {
        modifier(FeatherItem(row: row, column: column, spacing: spacing))
    }

    /// Drives the feathered items inside: they swing in once on appear, then rest at `coveredAngle`.
    func featherScope(coveredAngle: Double = 0) -> some View {
        modifier(FeatherScope(coveredAngle: coveredAngle))
    }
}

private struct FeatherScope: ViewModifier {
    var coveredAngle: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasEntered = false

    func body(content: Content) -> some View {
        content
            .environment(\.featherAngle, reduceMotion ? 0 : (hasEntered ? coveredAngle : Feather.enterAngle))
            .opacity(hasEntered ? 1 : 0)
            .animation(.easeOut(duration: 0.15).delay(0.12), value: hasEntered)
            .task {
                // One frame at the start angle first, or there's nothing to animate from.
                try? await Task.sleep(for: .milliseconds(20))
                hasEntered = true
            }
    }
}

private struct FeatherItem: ViewModifier {
    let row: Int
    let column: Int
    let spacing: CGFloat

    @Environment(\.featherAngle) private var angle
    @Environment(\.featherRowOrigin) private var origin

    func body(content: Content) -> some View {
        let visibleRow = row - (origin?.row ?? 0)
        let isOffScreen = visibleRow < -1 || visibleRow > Feather.visibleRows + 2
        content
            .modifier(HingeRotation(angle: angle, column: column, spacing: spacing))
            .opacity(angle == 0 ? 1 : 0)
            .animation(isOffScreen ? nil : Feather.animation(toward: angle, row: visibleRow, column: column), value: angle)
    }
}

/// Rotation about a vertical hinge `column` item-widths to the left, with the same perspective as a whole-page turn.
/// Exact identity at 0°, like `PerspectiveRotation`.
private struct HingeRotation: GeometryEffect {
    var angle: Double
    let column: Int
    let spacing: CGFloat

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        guard angle != 0 else { return ProjectionTransform() }
        let hingeX = -(CGFloat(column) * (size.width + spacing) + MetroMetrics.margin)
        let anchorY = size.height / 2

        var depth = CATransform3DIdentity
        depth.m34 = -0.7 / 900

        var transform = CATransform3DMakeTranslation(-hingeX, -anchorY, 0)
        transform = CATransform3DConcat(transform, CATransform3DMakeRotation(angle * .pi / 180, 0, 1, 0))
        transform = CATransform3DConcat(transform, depth)
        transform = CATransform3DConcat(transform, CATransform3DMakeTranslation(hingeX, anchorY, 0))
        return ProjectionTransform(transform)
    }
}
