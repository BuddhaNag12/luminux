import SwiftUI

/// Where a page's feathered items sit: swung toward the viewer before the page opens (and while it's popped away),
/// flat while it shows, swung away while another page covers it.
nonisolated enum FeatherState: Equatable, Sendable {
    case below, shown, above
}

/// The turnstile feather: every item turns on a hinge at the left edge of the screen (on iPhone Duo's open screen, the
/// right half turns on the fold, so each half turns like a screen of its own), line after line from the top,
/// using the original timings (in −80° → 0° over 350 ms with a sharp decelerate; out 0° → 50° over 250 ms
/// accelerating). The built-in `rotation3DEffect` is a layer transform, so it stays smooth at 120 Hz.
nonisolated enum Feather {
    static let enterAngle: Double = -80
    static let coverAngle: Double = 50
    static let leaveAngle: Double = -80

    static let enterDuration: Double = 0.35
    static let exitDuration: Double = 0.22
    static let rowDelay: Double = 0.04
    static let columnDelay: Double = 0.012
    static let exitRowDelay: Double = 0.025
    /// Lines further down than this are off screen, so they don't hold up the visible ones.
    static let visibleRows = 10

    /// The outgoing page is gone by now (its items turn away, then its background fades), so the pages never overlap.
    static let enterBaseDelay: Double = 0.22
    /// When a covered page's background fades out, once its items have mostly turned away.
    static let coverFadeDelay: Double = 0.12
    static let revealBaseDelay: Double = 0.12

    /// Perspective as a fraction of the screen, so every item turns about the same vanishing point.
    static let depth: CGFloat = 0.75 / 900

    /// How long a full exit takes, so a popped page can be removed once its items are gone.
    static var exitTime: Double { exitDuration + Double(visibleRows / 2) * exitRowDelay }

    static func angle(for state: FeatherState) -> Double {
        switch state {
        case .below: enterAngle
        case .shown: 0
        case .above: coverAngle
        }
    }

    /// Windows' decelerate curve, and its accelerating mirror for exits.
    static let decelerate = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.1, y: 0.9), endControlPoint: UnitPoint(x: 0.2, y: 1))
    static let accelerate = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.7, y: 0), endControlPoint: UnitPoint(x: 1, y: 0.5))

    struct Timing {
        let rotation: Animation
        /// Items pop visible as they start turning in and vanish as they finish turning out.
        let opacity: Animation
    }

    /// `rows` is how many lines fit on screen; more lines than `visibleRows` share the same overall spread, so a
    /// zoomed-out grid turns every line without taking longer.
    static func timing(toward state: FeatherState, from previous: FeatherState, row: Int, column: Int, rows: Int = visibleRows) -> Timing {
        let rows = max(rows, visibleRows)
        let line = Double(min(max(row, 0), rows)) * Double(visibleRows) / Double(rows)
        if state == .shown {
            let base = previous == .below ? enterBaseDelay : revealBaseDelay
            let delay = base + line * rowDelay + Double(column) * columnDelay
            return Timing(
                rotation: Animation.timingCurve(decelerate, duration: enterDuration).delay(delay),
                opacity: .linear(duration: 0.04).delay(delay)
            )
        }
        let delay = line * exitRowDelay + Double(column) * columnDelay * 0.5
        return Timing(
            rotation: Animation.timingCurve(accelerate, duration: exitDuration).delay(delay),
            opacity: .linear(duration: 0.05).delay(delay + exitDuration - 0.05)
        )
    }
}

struct FeatherContext: Equatable {
    var state: FeatherState = .shown
    var previous: FeatherState = .shown
}

/// The first visible row of a scrolling grid and how many rows fit on screen, so rows scrolled above the screen
/// don't hold up the visible ones. Not observed: items read it when their page's state changes, so scrolling past a
/// row doesn't re-render every tile.
final class FeatherRowOrigin {
    var row = 0
    var rows = Feather.visibleRows
}

extension EnvironmentValues {
    @Entry var feather = FeatherContext()
    @Entry var featherRowOrigin: FeatherRowOrigin?
}

extension View {
    /// Turns this item with its page; `row` sets its line in the feather, `column` a small offset within the line.
    /// Items that know how far they sit from the screen's left edge pass it as `hingeX`, so the turn needn't read
    /// their on-screen position: reading it re-renders the item whenever anything above it moves, which in a photo
    /// grid meant every tile on every frame of a pinch or a scroll.
    func metroFeather(row: Int, column: Int = 0, hingeX: CGFloat? = nil) -> some View {
        modifier(FeatherItem(row: row, column: column, hingeX: hingeX))
    }

    /// Drives the feathered items inside: they turn in once on appear, then follow `restingState`.
    func featherScope(_ restingState: FeatherState = .shown) -> some View {
        modifier(FeatherScope(restingState: restingState))
    }
}

private struct FeatherScope: ViewModifier {
    var restingState: FeatherState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var context = FeatherContext(state: .below, previous: .below)
    @State private var hasAppeared = false
    @State private var lastSizeClass: UserInterfaceSizeClass?

    func body(content: Content) -> some View {
        content
            .environment(\.feather, reduceMotion ? FeatherContext() : context)
            // Backgrounds and chrome that don't feather appear as the first line starts turning.
            .opacity(hasAppeared ? 1 : 0)
            .animation(.linear(duration: 0.08).delay(Feather.enterBaseDelay), value: hasAppeared)
            .task {
                // One frame at the start angle first, or there's nothing to animate from.
                try? await Task.sleep(for: .milliseconds(16))
                hasAppeared = true
                move(to: restingState)
            }
            .onChange(of: restingState) { _, state in
                if hasAppeared { move(to: state) }
            }
            .task(id: sizeClass) {
                // Opening or closing iPhone Duo turns the page in again on the screen it lands on.
                guard hasAppeared, restingState == .shown, !reduceMotion, sizeClass != lastSizeClass else { return }
                lastSizeClass = sizeClass
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) { context = FeatherContext(state: .below, previous: .below) }
                try? await Task.sleep(for: .milliseconds(16))
                move(to: .shown)
            }
            .onAppear { lastSizeClass = sizeClass }
    }

    private func move(to state: FeatherState) {
        guard state != context.state else { return }
        context = FeatherContext(state: state, previous: context.state)
    }
}

private struct FeatherItem: ViewModifier {
    let row: Int
    let column: Int
    let hingeX: CGFloat?

    @Environment(\.feather) private var feather
    @Environment(\.featherRowOrigin) private var origin
    @Environment(\.foldX) private var foldX

    func body(content: Content) -> some View {
        let visibleRow = row - (origin?.row ?? 0)
        let rows = origin?.rows ?? Feather.visibleRows
        let isOffScreen = visibleRow < -1 || visibleRow > rows + 1
        let angle = Feather.angle(for: feather.state)
        let timing = Feather.timing(toward: feather.state, from: feather.previous, row: visibleRow, column: column, rows: rows)
        content
            .modifier(FeatherTurn(angle: angle, hingeX: hingeX, foldX: foldX))
            .animation(isOffScreen ? nil : timing.rotation, value: feather.state)
            .opacity(feather.state == .shown ? 1 : 0)
            .animation(isOffScreen ? nil : timing.opacity, value: feather.state)
    }
}

/// The turn itself: on a hinge at the screen's left edge, or the fold for items right of it, with one shared
/// perspective for every item.
private struct FeatherTurn: ViewModifier {
    let angle: Double
    let hingeX: CGFloat?
    let foldX: CGFloat?

    func body(content: Content) -> some View {
        if let hingeX {
            let fromFold = foldX.map { hingeX >= $0 ? hingeX - $0 : hingeX } ?? hingeX
            content.modifier(FeatherHingeRotation(angle: angle, hingeX: fromFold))
        } else {
            content.visualEffect { [foldX] content, proxy in
                let frame = proxy.frame(in: .global)
                let width = max(frame.width, 1)
                let hinge = foldX.map { frame.minX >= $0 ? $0 : 0 } ?? 0
                return content.rotation3DEffect(
                    .degrees(angle),
                    axis: (x: 0, y: 1, z: 0),
                    anchor: UnitPoint(x: (hinge - frame.minX) / width, y: 0.5),
                    perspective: Feather.depth * max(frame.width, frame.height)
                )
            }
        }
    }
}

/// The turn for an item `hingeX` points from the screen's left edge, from its size alone.
private struct FeatherHingeRotation: GeometryEffect, CustomStringConvertible {
    var angle: Double
    let hingeX: CGFloat

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    /// Spares SwiftUI's renderer reflecting over the struct every frame; see `PerspectiveRotation`.
    var description: String { "FeatherHingeRotation(\(angle), \(hingeX))" }

    func effectValue(size: CGSize) -> ProjectionTransform {
        PerspectiveRotation(
            angle: angle,
            axis: (x: 0, y: 1, z: 0),
            anchor: UnitPoint(x: -hingeX / max(size.width, 1), y: 0.5),
            perspective: Feather.depth * max(size.width, size.height)
        )
        .effectValue(size: size)
    }
}
