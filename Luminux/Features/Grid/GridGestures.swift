import SwiftUI
import UIKit

/// The photo grid's zoom levels, like Photos: pinch out for bigger photos, in for more of them.
nonisolated enum GridZoom {
    /// Odd counts, so each level is the one before with the same number of columns added on either side.
    static let levels = [3, 5, 15]
    static let defaultColumns = 5

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

    /// How far a pinch can scale the grid before it starts to resist: one pinch can carry on through every level,
    /// so only past the end ones.
    static func scaleLimits(for columns: Int) -> ClosedRange<CGFloat> {
        let current = CGFloat(nearestLevel(to: columns))
        return current / CGFloat(levels.last!)...current / CGFloat(levels.first!)
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

/// Where every photo and month title of a grid sits, worked out rather than measured: every row is the same height,
/// so nothing has to be laid out to know where it goes. The grid draws only what's on screen from it, and a pinch
/// lines one level up with the next from it exactly.
nonisolated struct GridLayout: Equatable {
    static let headerHeight: CGFloat = 44
    static let bottomPadding: CGFloat = 24

    let columns: Int
    let side: CGFloat
    let gutter: CGFloat
    /// Each section's photos, whether it has a month title over it, where it starts and its first stagger row.
    let sections: [Section]
    let height: CGFloat

    struct Section: Equatable {
        let range: Range<Int>
        let hasHeader: Bool
        let top: CGFloat
        let firstRow: Int
        var rows: Int
    }

    var pitch: CGFloat { side + gutter }

    /// `sections` nil: one run of photos with no month titles.
    init(columns: Int, width: CGFloat, gutter: CGFloat, sections ranges: [Range<Int>]?, count: Int) {
        self.columns = columns
        self.gutter = gutter
        side = GridZoom.tileSide(columns: columns, width: width, gutter: gutter)
        let pitch = side + gutter
        var sections: [Section] = []
        var y: CGFloat = 0
        var row = 0
        for range in ranges ?? [0..<count] where !range.isEmpty {
            let hasHeader = ranges != nil
            let rows = (range.count + columns - 1) / columns
            sections.append(Section(range: range, hasHeader: hasHeader, top: y, firstRow: row, rows: rows))
            y += (hasHeader ? Self.headerHeight + gutter : 0) + CGFloat(rows) * pitch
            row += (hasHeader ? 1 : 0) + rows
        }
        self.sections = sections
        height = max(y - gutter, 0) + Self.bottomPadding
    }

    private func rowsTop(_ section: Section) -> CGFloat {
        section.top + (section.hasHeader ? Self.headerHeight + gutter : 0)
    }

    /// The section holding `index`, by binary search.
    private func section(of index: Int) -> Section? {
        var low = 0, high = sections.count - 1
        while low <= high {
            let mid = (low + high) / 2
            if index < sections[mid].range.lowerBound { high = mid - 1 }
            else if index >= sections[mid].range.upperBound { low = mid + 1 }
            else { return sections[mid] }
        }
        return nil
    }

    /// The last section starting at or above `y`.
    private func sectionIndex(atY y: CGFloat) -> Int? {
        guard !sections.isEmpty else { return nil }
        var low = 0, high = sections.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if sections[mid].top <= y { low = mid } else { high = mid - 1 }
        }
        return low
    }

    func frame(of index: Int) -> CGRect? {
        guard let section = section(of: index) else { return nil }
        let offset = index - section.range.lowerBound
        return CGRect(x: CGFloat(offset % columns) * pitch, y: rowsTop(section) + CGFloat(offset / columns) * pitch, width: side, height: side)
    }

    /// The column and stagger row of a photo, for the page turn.
    func cell(of index: Int) -> (row: Int, column: Int)? {
        guard let section = section(of: index) else { return nil }
        let offset = index - section.range.lowerBound
        return (section.firstRow + (section.hasHeader ? 1 : 0) + offset / columns, offset % columns)
    }

    /// The photo whose square contains `point`.
    func index(at point: CGPoint) -> Int? {
        guard let i = sectionIndex(atY: point.y) else { return nil }
        let section = sections[i]
        let y = point.y - rowsTop(section)
        guard y >= 0, point.x >= 0 else { return nil }
        let row = Int(y / pitch), column = Int(point.x / pitch)
        guard column < columns, y - CGFloat(row) * pitch < side, point.x - CGFloat(column) * pitch < side else { return nil }
        let index = section.range.lowerBound + row * columns + column
        return index < section.range.upperBound ? index : nil
    }

    /// The photo nearest `point`: the fingers often sit on a gutter or a month title.
    func index(nearest point: CGPoint) -> Int? {
        guard let i = sectionIndex(atY: point.y) else { return nil }
        let section = sections[i]
        let row = min(max(Int((point.y - rowsTop(section)) / pitch), 0), section.rows - 1)
        let column = min(max(Int(point.x / pitch), 0), columns - 1)
        return min(section.range.lowerBound + row * columns + column, section.range.upperBound - 1)
    }

    /// Every photo whose square meets `rect`, in order.
    func indices(in rect: CGRect) -> [Int] {
        guard let first = sectionIndex(atY: rect.minY) else { return [] }
        var result: [Int] = []
        for section in sections[first...] {
            guard section.top <= rect.maxY else { break }
            let top = rowsTop(section)
            let firstRow = max(Int(((rect.minY - top) / pitch).rounded(.down)), 0)
            let lastRow = min(Int(((rect.maxY - top) / pitch).rounded(.down)), section.rows - 1)
            guard firstRow <= lastRow else { continue }
            let lower = section.range.lowerBound + firstRow * columns
            let upper = min(section.range.lowerBound + (lastRow + 1) * columns, section.range.upperBound)
            result.append(contentsOf: lower..<upper)
        }
        return result
    }

    /// Every row of photos that meets `rect`: its stagger row (unique across the grid), photos and top.
    func rows(in rect: CGRect) -> [RowSlot] {
        guard let first = sectionIndex(atY: rect.minY) else { return [] }
        var result: [RowSlot] = []
        for section in sections[first...] {
            guard section.top <= rect.maxY else { break }
            let top = rowsTop(section)
            let firstRow = max(Int(((rect.minY - top) / pitch).rounded(.down)), 0)
            let lastRow = min(Int(((rect.maxY - top) / pitch).rounded(.down)), section.rows - 1)
            guard firstRow <= lastRow else { continue }
            for row in firstRow...lastRow {
                let lower = section.range.lowerBound + row * columns
                result.append(RowSlot(
                    row: section.firstRow + (section.hasHeader ? 1 : 0) + row,
                    range: lower..<min(lower + columns, section.range.upperBound),
                    y: top + CGFloat(row) * pitch
                ))
            }
        }
        return result
    }

    struct RowSlot: Equatable {
        let row: Int
        let range: Range<Int>
        let y: CGFloat
    }

    /// The month titles that meet `rect`, by section position.
    func headers(in rect: CGRect) -> [(position: Int, frame: CGRect, row: Int)] {
        sections.indices.compactMap { position in
            let section = sections[position]
            guard section.hasHeader else { return nil }
            let frame = CGRect(x: 0, y: section.top, width: CGFloat(columns) * pitch - gutter, height: Self.headerHeight)
            return frame.intersects(rect) ? (position, frame, section.firstRow) : nil
        }
    }

    func headerTop(ofSectionAt position: Int) -> CGFloat? {
        sections.indices.contains(position) ? sections[position].top : nil
    }

    /// The first stagger row at or below `y`.
    func row(atY y: CGFloat) -> Int {
        guard let i = sectionIndex(atY: y) else { return 0 }
        let section = sections[i]
        let inRows = Int(max(y - rowsTop(section), 0) / pitch)
        return section.firstRow + (section.hasHeader ? 1 : 0) + min(inRows, section.rows)
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

/// Set while a photo grid is being pinched, so what it sits in (a pivot's pages) holds still.
struct GridPinchingKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/// Puts each subview in the rect it carries (see `placed(_:)`) without measuring it first: a grid's places are
/// worked out already, and asking hundreds of photos their size on every scroll step was most of its layout time.
struct PlacedLayout: Layout {
    var height: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            let rect = subview[PlacedRect.self]
            subview.place(at: CGPoint(x: bounds.minX + rect.minX, y: bounds.minY + rect.minY), proposal: ProposedViewSize(rect.size))
        }
    }
}

nonisolated struct PlacedRect: LayoutValueKey {
    static let defaultValue = CGRect.zero
}

extension View {
    /// Where `PlacedLayout` puts this view.
    func placed(_ rect: CGRect) -> some View {
        layoutValue(key: PlacedRect.self, value: rect)
    }
}
