import SwiftUI

/// Tile content that changes every few seconds with a flip or an upward slide, at a random interval per tile.
struct LiveTile<Item: Identifiable, Face: View>: View {
    enum Style { case flip, slide }

    let items: [Item]
    var style: Style = .flip
    var interval: ClosedRange<Double> = 4...8
    @ViewBuilder var face: (Item) -> Face

    @State private var index = 0
    @State private var flipAngle: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .task(id: items.count) { await cycle() }
    }

    private var transition: AnyTransition {
        reduceMotion || style == .flip ? .identity : .push(from: .bottom)
    }

    private func cycle() async {
        guard items.count > 1, !reduceMotion else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: interval)))
            guard !Task.isCancelled else { return }
            advance()
        }
    }

    private func advance() {
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
