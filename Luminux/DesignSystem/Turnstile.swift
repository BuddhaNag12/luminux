import SwiftUI

/// Page transition that swings the page on a hinge at its left edge.
struct TurnstileTransition: Transition {
    enum Direction { case forward, backward }

    var direction: Direction = .forward

    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .modifier(PerspectiveRotation(angle: angle(for: phase), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.7))
            .opacity(phase.isIdentity ? 1 : 0)
    }

    private func angle(for phase: TransitionPhase) -> Double {
        switch (phase, direction) {
        case (.identity, _): 0
        case (.willAppear, .forward): -80
        case (.didDisappear, .forward): 50
        case (.willAppear, .backward): 50
        case (.didDisappear, .backward): -80
        }
    }
}

extension AnyTransition {
    /// Turnstile, or a cross-fade when Reduce Motion is on.
    static func metroPage(_ direction: TurnstileTransition.Direction, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : AnyTransition(TurnstileTransition(direction: direction))
    }
}
