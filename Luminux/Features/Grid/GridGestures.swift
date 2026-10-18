import SwiftUI
import UIKit

/// The photo grid's zoom levels, like Photos: pinch out for bigger photos, in for more of them.
nonisolated enum GridZoom {
    static let levels = [2, 3, 4, 6, 8]
    static let defaultColumns = 4

    static func nearestLevel(to columns: Int) -> Int {
        levels.min { abs($0 - columns) < abs($1 - columns) } ?? defaultColumns
    }

    /// The level a pinch is heading to, given how many columns the grid looks like at the pinch's scale: the next
    /// one out when more than it has, the next one in when fewer; nil past the ends.
    static func level(toward columns: CGFloat, from current: Int) -> Int? {
        if columns > CGFloat(current) { return levels.first { $0 > current } }
        if columns < CGFloat(current) { return levels.last { $0 < current } }
        return nil
    }

    /// How far (0...1) a grid that looks like `columns` columns has gone from `current` to `target`, on a log scale,
    /// so halfway between 4 and 6 is 4.9.
    static func progress(_ columns: CGFloat, from current: Int, to target: Int) -> CGFloat {
        min(max(log(columns / CGFloat(current)) / log(CGFloat(target) / CGFloat(current)), 0), 1)
    }

    /// How far a pinch can scale the grid before it starts to resist: as far as the levels either side.
    static func scaleLimits(for columns: Int) -> ClosedRange<CGFloat> {
        let current = nearestLevel(to: columns)
        let more = levels.first { $0 > current } ?? current
        let fewer = levels.last { $0 < current } ?? current
        return CGFloat(current) / CGFloat(more)...CGFloat(current) / CGFloat(fewer)
    }

    /// Follows the fingers inside the limits and slows down past them, so the grid resists instead of stopping dead.
    static func rubberBand(_ scale: CGFloat, limits: ClosedRange<CGFloat>) -> CGFloat {
        let damping: CGFloat = 0.2
        if scale > limits.upperBound {
            return limits.upperBound * (1 + log(scale / limits.upperBound) * damping)
        } else if scale < limits.lowerBound {
            return limits.lowerBound / (1 + log(limits.lowerBound / scale) * damping)
        }
        return scale
    }

    /// The side of a tile at `columns` across `width`, with the grid's gutters.
    static func tileSide(columns: Int, width: CGFloat, gutter: CGFloat) -> CGFloat {
        (width - gutter * CGFloat(columns - 1)) / CGFloat(columns)
    }
}

/// Where each laid-out tile sits in the grid, for finding the photo under a finger. A plain class, so writing to it
/// doesn't re-render the grid. Frames are kept when tiles scroll or page away, since tiles coming back don't report
/// an unchanged frame again; each is tagged with the level it was measured at, so frames from another level are
/// ignored.
final class TileFrames {
    private var frames: [Int: (rect: CGRect, columns: Int)] = [:]

    func set(_ frame: CGRect, for index: Int, columns: Int) { frames[index] = (frame, columns) }

    func frame(of index: Int, columns: Int) -> CGRect? {
        frames[index].flatMap { $0.columns == columns ? $0.rect : nil }
    }

    /// Every frame measured at `columns`.
    func frames(columns: Int) -> [(Int, CGRect)] {
        frames.compactMap { $0.value.columns == columns ? ($0.key, $0.value.rect) : nil }
    }

    func index(at point: CGPoint, columns: Int) -> Int? {
        frames.first { $0.value.columns == columns && $0.value.rect.contains(point) }?.key
    }

    /// The tile nearest `point` among those in `visible`; the grid parks reused tiles off screen at stale positions.
    func index(nearest point: CGPoint, columns: Int, within visible: CGRect) -> Int? {
        func distance(_ rect: CGRect) -> CGFloat {
            let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
            let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
            return dx * dx + dy * dy
        }
        return frames
            .filter { $0.value.columns == columns && $0.value.rect.intersects(visible) }
            .min { distance($0.value.rect) < distance($1.value.rect) }?.key
    }
}

/// The grid's scroll position, kept outside SwiftUI state so reading it every frame doesn't re-render anything.
final class GridScrollMetrics {
    var offsetY: CGFloat = 0
    var minOffsetY: CGFloat = 0
    var maxOffsetY: CGFloat = 0
    /// The part of the scroll view not covered by bars, in its own coordinates.
    var visibleTop: CGFloat = 0
    var visibleBottom: CGFloat = 0
    var viewportSize: CGSize = .zero
}

/// A two-finger pinch that reports its scale, how fast it's changing, and the point between the fingers, so the grid
/// can zoom around that point and follow it when both fingers move.
struct GridPinchRecognizer: UIGestureRecognizerRepresentable {
    enum Phase { case began, changed, ended }

    var onChange: (_ phase: Phase, _ scale: CGFloat, _ velocity: CGFloat, _ centroid: CGPoint) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPinchGestureRecognizer {
        let recognizer = UIPinchGestureRecognizer()
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPinchGestureRecognizer, context: Context) {
        // With one finger lifted the location jumps to the other finger; keep the last point between both.
        if recognizer.numberOfTouches >= 2 {
            context.coordinator.centroid = context.converter.localLocation
        }
        let centroid = context.coordinator.centroid
        switch recognizer.state {
        case .began: onChange(.began, recognizer.scale, recognizer.velocity, centroid)
        case .changed: onChange(.changed, recognizer.scale, recognizer.velocity, centroid)
        case .ended, .cancelled, .failed: onChange(.ended, recognizer.scale, recognizer.velocity, centroid)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var centroid: CGPoint = .zero

        // Starts alongside the scroll view's pan; the grid turns scrolling off once the pinch begins.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

/// A press held on the grid, reported where it started. Leaves the touch to the photo's button, which still gets
/// the lift that follows.
struct GridLongPressRecognizer: UIGestureRecognizerRepresentable {
    var onPress: (CGPoint) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = 0.4
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        if recognizer.state == .began { onPress(context.converter.localLocation) }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

/// A one-finger drag that only starts when it moves sideways, so vertical drags still scroll the grid. The pivot
/// waits for it, so a sideways swipe selects instead of paging (the original locked its pivot in select mode too).
struct SwipeSelectRecognizer: UIGestureRecognizerRepresentable {
    enum Phase { case began, changed, ended }

    var isEnabled: Bool
    /// Where the swipe started and where the finger is now, in the view's own coordinates.
    var onChange: (_ phase: Phase, _ start: CGPoint, _ location: CGPoint) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let location = context.converter.localLocation
        let translation = recognizer.translation(in: recognizer.view)
        let start = CGPoint(x: location.x - translation.x, y: location.y - translation.y)
        switch recognizer.state {
        case .began: onChange(.began, start, location)
        case .changed: onChange(.changed, start, location)
        case .ended, .cancelled, .failed: onChange(.ended, start, location)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            gestureRecognizer.isEnabled && other.view is UIScrollView && other is UIPanGestureRecognizer
        }
    }
}
