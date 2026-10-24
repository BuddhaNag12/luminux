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

    /// The coordinate space of a page in the stack, which scattering items zoom out from the centre of.
    static let pageSpace = "featherPage"

    /// Perspective as a fraction of the screen, so every item turns about the same vanishing point.
    static let depth: CGFloat = 0.75 / 900

    /// How long a full exit takes, so a popped page can be removed once its items are gone.
    static var exitTime: Double { exitDuration + Double(visibleRows / 2) * exitRowDelay }
    /// How long a page's entrance takes, so heavy views (a map) can wait until its lines have settled.
    static var enterTime: Double { enterBaseDelay + Double(visibleRows) * rowDelay + enterDuration }

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
    /// `waitsForOutgoing` false: nothing is leaving (a zooming page is only built once the one before has gone), so the
    /// lines start turning in at once.
    static func timing(toward state: FeatherState, from previous: FeatherState, row: Int, column: Int, rows: Int = visibleRows, waitsForOutgoing: Bool = true) -> Timing {
        let rows = max(rows, visibleRows)
        let line = Double(min(max(row, 0), rows)) * Double(visibleRows) / Double(rows)
        if state == .shown {
            let base = previous == .below ? (waitsForOutgoing ? enterBaseDelay : 0) : revealBaseDelay
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

/// `zoom`: instead of turning, a covered page's items grow and fly outward from the screen's centre one at a time, in
/// a scattered order, like Windows 10 Mobile's start screen as an app opens; they fly back in when it's uncovered.
nonisolated enum FeatherStyle: Sendable {
    case turnstile, zoom
}

extension EnvironmentValues {
    @Entry var featherStyle = FeatherStyle.turnstile
    /// The screen the items scatter from the centre of.
    @Entry var featherScreen = CGSize.zero
    /// Items opening come forward from behind the screen instead of turning in (the first page, as the app starts).
    @Entry var featherFromBack = false
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

    /// For a live platform view (a map): fades with its page instead of moving. Turning or scattering one re-clipped
    /// it inside its scroll view on every frame, and MapKit laid itself out again each time.
    func metroFeatherFade() -> some View {
        modifier(FeatherFade())
    }

    /// Drives the feathered items inside: they turn in once on appear, then follow `restingState`.
    func featherScope(_ restingState: FeatherState = .shown) -> some View {
        modifier(FeatherScope(restingState: restingState))
    }
}

private struct FeatherScope: ViewModifier {
    var restingState: FeatherState

    @Environment(\.featherStyle) private var featherStyle
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
            .animation(.linear(duration: 0.08).delay(featherStyle == .zoom ? 0 : Feather.enterBaseDelay), value: hasAppeared)
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

private struct FeatherFade: ViewModifier {
    @Environment(\.feather) private var feather

    func body(content: Content) -> some View {
        content
            .opacity(feather.state == .shown ? 1 : 0)
            .animation(.easeOut(duration: 0.2).delay(feather.state == .shown ? Feather.revealBaseDelay : 0), value: feather.state)
    }
}

private struct FeatherItem: ViewModifier {
    let row: Int
    let column: Int
    let hingeX: CGFloat?

    @Environment(\.feather) private var feather
    @Environment(\.featherRowOrigin) private var origin
    @Environment(\.foldX) private var foldX
    @Environment(\.featherStyle) private var style
    @Environment(\.featherScreen) private var screen
    @Environment(\.featherFromBack) private var fromBack

    func body(content: Content) -> some View {
        let visibleRow = row - (origin?.row ?? 0)
        let rows = origin?.rows ?? Feather.visibleRows
        let isOffScreen = visibleRow < -1 || visibleRow > rows + 1
        // With the zoom style a page being covered, or uncovered again, scatters instead of turning; the first page
        // opening (the app starting) comes forward from the back; other pages still turn. One chain for all of them,
        // so switching never rebuilds the item.
        let scatters = style == .zoom && (feather.state == .above || (feather.state == .shown && feather.previous == .above))
        let comesForward = style == .zoom && fromBack && (feather.state == .below || (feather.state == .shown && feather.previous == .below))
        let angle = scatters || comesForward ? 0 : Feather.angle(for: feather.state)
        let out: CGFloat = scatters && feather.state == .above ? 1 : comesForward && feather.state == .below ? -1 : 0
        // One item at a time in reading order: the title, the headers, then each tile left to right, line by line.
        let step = Double(max(visibleRow, 0) * 2 + column)
        let timing = Feather.timing(toward: feather.state, from: feather.previous, row: visibleRow, column: column, rows: rows, waitsForOutgoing: style != .zoom)
        let motion: Animation
        let fade: Animation
        if scatters && out == 1 {
            // Grows away at full strength, then fades only at the very end.
            motion = .easeIn(duration: Self.scatterDuration).delay(step * Self.scatterStagger)
            fade = .linear(duration: 0.08).delay(step * Self.scatterStagger + Self.scatterDuration - 0.08)
        } else if scatters {
            motion = .timingCurve(Feather.decelerate, duration: 0.35).delay(Feather.revealBaseDelay + step * Self.scatterStagger)
            fade = .linear(duration: 0.06).delay(Feather.revealBaseDelay + step * Self.scatterStagger)
        } else if comesForward {
            // The title swings in first, then the headers, then the tiles in reading order, a moment apart.
            let delay = Self.forwardDelay(row: visibleRow, column: column)
            motion = .timingCurve(Feather.decelerate, duration: visibleRow == 0 ? 0.7 : 0.55).delay(delay)
            fade = .linear(duration: visibleRow == 0 ? 0.3 : 0.2).delay(delay)
        } else {
            motion = timing.rotation
            fade = timing.opacity
        }
        return content
            .modifier(FeatherTurn(angle: angle, hingeX: hingeX, foldX: foldX))
            .modifier(FeatherScatter(out: out, screen: screen, slidesIn: comesForward && visibleRow == 0))
            .animation(isOffScreen ? nil : motion, value: feather.state)
            .opacity(feather.state == .shown ? 1 : 0)
            .animation(isOffScreen ? nil : fade, value: feather.state)
    }

    private static let scatterDuration: Double = 0.22
    private static let scatterStagger: Double = 0.03

    private static func forwardDelay(row: Int, column: Int) -> Double {
        switch row {
        case 0: 0
        case 1: 0.25 + Double(column) * 0.05
        default: 0.35 + Double((row - 2) * 2 + column) * 0.05
        }
    }
}

/// A scattering item (`out` 1) grows where it is, nudged a little away from the screen's centre; one coming forward
/// (`out` -1) starts small and tilted, as if swinging in from behind the screen, and the title (`slidesIn`) from
/// further back on the right. Reads its position only while out, so an item at rest doesn't follow every scroll.
private struct FeatherScatter: ViewModifier {
    let out: CGFloat
    let screen: CGSize
    let slidesIn: Bool

    func body(content: Content) -> some View {
        content.visualEffect { [out, screen, slidesIn] content, proxy in
            if out < 0 {
                let back = -out
                return content
                    .rotation3DEffect(.degrees((slidesIn ? -55 : -35) * back), axis: (x: slidesIn ? 0.2 : 0.6, y: 1, z: 0), perspective: 0.6)
                    .rotationEffect(.zero)
                    .scaleEffect(1 - (slidesIn ? 0.35 : 0.4) * back)
                    .offset(x: slidesIn ? screen.width * 0.35 * back : 0, y: 0)
            }
            guard out > 0 else { return content.rotation3DEffect(.zero, axis: (x: 0, y: 1, z: 0)).rotationEffect(.zero).scaleEffect(1).offset(x: 0, y: 0) }
            // Measured against the page itself, which every item can see, rather than a size handed down to it.
            // Only its size: `bounds(of:)` gives the page's rect in this item's own coordinates.
            let page = proxy.bounds(of: .named(Feather.pageSpace))?.size ?? screen
            let frame = proxy.frame(in: .named(Feather.pageSpace))
            // Like marbles thrown at a mirror: each item comes out of the screen toward you, flying outward from the
            // centre on a slightly different line. The variation comes from its position, so it stays the same each
            // time.
            // A view mid-layout (a map, say) can report an infinite frame; it just gets the plain path.
            let mix = abs(frame.minX) * 7 + abs(frame.minY) * 13
            let seed = mix.isFinite ? Int(mix.truncatingRemainder(dividingBy: 1_000_000)) : 0
            let swerve = Angle.degrees(Double(seed % 41) - 20)
            var away = mix.isFinite ? CGVector(dx: frame.midX - page.width / 2, dy: frame.midY - page.height / 2) : CGVector(dx: 0, dy: -1)
            let length = max(hypot(away.dx, away.dy), 1)
            // Items near the centre still fly somewhere, not just grow in place.
            let reach = max(length, 60) * 0.6
            away = CGVector(dx: away.dx / length * reach, dy: away.dy / length * reach)
            let turned = CGVector(
                dx: away.dx * cos(swerve.radians) - away.dy * sin(swerve.radians),
                dy: away.dx * sin(swerve.radians) + away.dy * cos(swerve.radians)
            )
            return content
                .rotation3DEffect(.zero, axis: (x: 0, y: 1, z: 0))
                .rotationEffect(.zero)
                .scaleEffect(1 + 0.8 * out)
                .offset(x: turned.dx * out, y: turned.dy * out)
        }
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
