import SwiftUI
import UIKit

/// The photo grid's zoom levels, like Photos: pinch out for bigger photos, in for more of them.
nonisolated enum GridZoom {
    static let levels = [2, 3, 4, 6, 8]
    static let defaultColumns = 4

    /// How far a pinch has to go before the grid changes level.
    static let threshold: CGFloat = 0.15

    static func nearestLevel(to columns: Int) -> Int {
        levels.min { abs($0 - columns) < abs($1 - columns) } ?? defaultColumns
    }

    /// The level a pinch lands on: one step per pinch, two for a big one.
    static func columns(after current: Int, magnification: CGFloat) -> Int {
        guard let index = levels.firstIndex(of: nearestLevel(to: current)) else { return defaultColumns }
        let steps: Int
        if magnification > 1 + threshold {
            steps = magnification > 2 ? -2 : -1
        } else if magnification < 1 - threshold {
            steps = magnification < 0.5 ? 2 : 1
        } else {
            steps = 0
        }
        return levels[min(max(index + steps, 0), levels.count - 1)]
    }
}

/// Where each laid-out tile sits in the grid, for finding the photo under a finger. A plain class, so writing to it
/// doesn't re-render the grid.
final class TileFrames {
    private var frames: [Int: CGRect] = [:]

    func set(_ frame: CGRect, for index: Int) { frames[index] = frame }
    func remove(_ index: Int) { frames[index] = nil }
    func removeAll() { frames.removeAll() }

    func index(at point: CGPoint) -> Int? {
        frames.first { $0.value.contains(point) }?.key
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
