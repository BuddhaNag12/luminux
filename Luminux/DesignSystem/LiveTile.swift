import SwiftUI

/// Tile content that changes with a flip or an upward slide when the scheduler gives it a turn. Only one tile on
/// screen changes at a time, like the original start screen.
struct LiveTile<Item: Identifiable, Face: View>: View {
    enum Style { case flip, slide }

    let items: [Item]
    var style: Style = .flip
    @ViewBuilder var face: (Item) -> Face

    @State private var index = 0
    @State private var flipAngle: Double = 0
    @State private var id = UUID()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var scheduler: LiveTileScheduler { .shared }

    var body: some View {
        ZStack {
            if items.indices.contains(index) {
                face(items[index])
                    .id(items[index].id)
                    .transition(transition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .perspectiveRotation(flipAngle, axis: (x: 1, y: 0, z: 0), perspective: 0.5)
        .onAppear { scheduler.register(id, canChange: items.count > 1 && !reduceMotion) }
        .onChange(of: items.count > 1 && !reduceMotion) { _, canChange in scheduler.register(id, canChange: canChange) }
        .onDisappear { scheduler.unregister(id) }
        .onChange(of: scheduler.turn) { _, turn in
            if turn?.tile == id { advance() }
        }
    }

    private var transition: AnyTransition {
        reduceMotion || style == .flip ? .identity : .push(from: .bottom)
    }

    private func advance() {
        guard items.count > 1 else { return }
        let next = (index + 1) % items.count
        switch style {
        case .slide:
            withAnimation(.spring(response: 0.6, dampingFraction: 1)) { index = next }
        case .flip:
            withAnimation(.easeIn(duration: 0.18)) {
                flipAngle = 90
            } completion: {
                index = next
                flipAngle = -90
                withAnimation(.easeOut(duration: 0.24)) { flipAngle = 0 }
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
        didSet { if isPaused != oldValue { restart() } }
    }

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
        guard !isPaused else { return }
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
