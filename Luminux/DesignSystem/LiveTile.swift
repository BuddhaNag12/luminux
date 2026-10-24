import SwiftUI

/// How a live tile changes its picture. `zoom`: the picture grows toward you as if coming out of the tile, then fades
/// as the next one fades in.
enum LiveTileStyle: CaseIterable { case flip, slide, zoom }

/// Tile content that changes with a flip, a slide or a zoom when the scheduler gives it a turn. Only one tile on
/// screen changes at a time, like the original start screen.
struct LiveTile<Item: Identifiable, Face: View>: View {
    typealias Style = LiveTileStyle

    let items: [Item]
    /// One way of changing every time; nil picks one at random for each change.
    var style: Style?
    @ViewBuilder var face: (Item) -> Face

    @State private var index = 0
    /// The picture on its way out during a slide or zoom, drawn alongside the incoming one until the change ends.
    @State private var leaving: Int?
    /// How far the current slide or zoom has gone, 0 to 1; both pictures follow it, so they always move together.
    @State private var progress: CGFloat = 1
    /// Where a slide's next picture comes in from: a different side each time, like the widget.
    @State private var slideEdge = Edge.bottom
    @State private var turnStyle = Style.flip
    @State private var flipAngle: Double = 0
    @State private var id = UUID()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var scheduler: LiveTileScheduler { .shared }

    var body: some View {
        ZStack {
            if items.indices.contains(index) {
                face(items[index])
                    .id(items[index].id)
                    .modifier(TileChange(style: turnStyle, edge: slideEdge, progress: progress, isLeaving: false))
            }
            // Drawn explicitly rather than as a removal transition: SwiftUI kept a leaving view's old transition, so
            // after a flip the picture vanished at once and the tile showed empty behind the incoming one.
            if let leaving, items.indices.contains(leaving) {
                face(items[leaving])
                    .id("leaving")
                    .modifier(TileChange(style: turnStyle, edge: slideEdge, progress: progress, isLeaving: true))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The next picture, drawn unseen so it has loaded before its turn; otherwise a slide or flip could bring in an
        // empty tile, which looked like the tile itself moving away.
        .background {
            if items.count > 1 {
                face(items[(index + 1) % items.count])
                    .opacity(0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .clipped()
        .perspectiveRotation(flipAngle, axis: (x: 1, y: 0, z: 0), perspective: 0.5)
        .onAppear { scheduler.register(id, canChange: items.count > 1 && !reduceMotion) }
        .onChange(of: items.count > 1 && !reduceMotion) { _, canChange in scheduler.register(id, canChange: canChange) }
        .onDisappear { scheduler.unregister(id) }
        .onChange(of: scheduler.turn) { _, turn in
            if turn?.tile == id { advance() }
        }
        // With live tiles off, each tile shows one picture and moves to the next whenever the hub comes back.
        .onChange(of: scheduler.returns) {
            if !scheduler.isAnimated, items.count > 1 { index = (index + 1) % items.count }
        }
    }

    private func advance() {
        guard items.count > 1, leaving == nil else { return }
        let next = (index + 1) % items.count
        turnStyle = style ?? Style.allCases.randomElement()!
        switch turnStyle {
        case .flip:
            withAnimation(.easeIn(duration: 0.18)) {
                flipAngle = 90
            } completion: {
                index = next
                flipAngle = -90
                withAnimation(.easeOut(duration: 0.24)) { flipAngle = 0 }
            }
        case .slide, .zoom:
            slideEdge = [Edge.top, .bottom, .leading, .trailing].filter { $0 != slideEdge }.randomElement()!
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) {
                leaving = index
                index = next
                progress = 0
            }
            // A slide comes in fast and settles slowly; a zoom grows steadily, fading at the end.
            let animation: Animation = turnStyle == .slide
                ? .timingCurve(0.2, 0.8, 0.1, 1, duration: 0.85)
                : .easeIn(duration: 0.9)
            Task { @MainActor in
                withAnimation(animation) { progress = 1 } completion: { leaving = nil }
            }
        }
    }
}

/// One picture of a slide or zoom at `progress`. Slide: the incoming picture pushes in from `edge` and the leaving one
/// goes out the opposite side, both solid. Zoom: the leaving picture grows toward you as if coming out of the tile and
/// fades at the end, while the incoming one fades in underneath it.
private struct TileChange: ViewModifier, Animatable {
    let style: LiveTileStyle
    let edge: Edge
    var progress: CGFloat
    let isLeaving: Bool

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        switch style {
        case .flip:
            content
        case .slide:
            let shift = isLeaving ? -progress : 1 - progress
            content.visualEffect { [edge] content, proxy in
                let size = proxy.size
                let direction: CGSize = switch edge {
                case .top: CGSize(width: 0, height: -size.height)
                case .bottom: CGSize(width: 0, height: size.height)
                case .leading: CGSize(width: -size.width, height: 0)
                case .trailing: CGSize(width: size.width, height: 0)
                }
                return content.offset(x: direction.width * shift, y: direction.height * shift)
            }
        case .zoom:
            if isLeaving {
                content
                    .scaleEffect(1 + 0.3 * progress)
                    .opacity(progress < 0.65 ? 1 : 1 - (progress - 0.65) / 0.35)
            } else {
                content.opacity(progress < 0.6 ? 0 : (progress - 0.6) / 0.4)
            }
        }
    }
}

/// Hands out turns to the live tiles on screen, one tile every few seconds and never the same tile twice in a row.
/// Pauses while the hub is covered, so hidden tiles don't animate.
@Observable
final class LiveTileScheduler {
    static let shared = LiveTileScheduler()

    struct Turn: Equatable {
        let tile: UUID
        /// Changes every turn, so the same tile can be told twice (with others in between).
        let count: Int
    }

    private(set) var turn: Turn?
    /// Set while something covers the tiles (another page, the viewer, the app in the background).
    var isPaused = false {
        didSet {
            guard isPaused != oldValue else { return }
            if !isPaused { returns += 1 }
            restart()
        }
    }
    /// Off in settings: no turns at all.
    var isAnimated = true {
        didSet { if isAnimated != oldValue { restart() } }
    }
    /// Counts each time the tiles come back into view.
    private(set) var returns = 0

    @ObservationIgnored private var tiles: Set<UUID> = []
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var count = 0

    /// Seconds between turns; with several tiles on screen each still changes every 10 to 20 seconds.
    static let interval: ClosedRange<Double> = 2.5...4

    func register(_ tile: UUID, canChange: Bool) {
        if canChange { tiles.insert(tile) } else { tiles.remove(tile) }
        if loop == nil { restart() }
    }

    func unregister(_ tile: UUID) {
        tiles.remove(tile)
    }

    private func restart() {
        loop?.cancel()
        loop = nil
        guard !isPaused, isAnimated else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: Self.interval)))
                guard let self, !Task.isCancelled else { return }
                self.giveTurn()
            }
        }
    }

    private func giveTurn() {
        let candidates = tiles.filter { $0 != turn?.tile }
        guard let next = candidates.randomElement() ?? tiles.first else { return }
        count += 1
        turn = Turn(tile: next, count: count)
    }
}
