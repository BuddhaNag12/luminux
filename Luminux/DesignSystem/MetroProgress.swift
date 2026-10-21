import SwiftUI

/// The Windows Phone "working" dots: a row of small squares that rush in from the left, drift through the middle
/// and rush out to the right, one after another.
struct MetroProgress: View {
    @Environment(\.metro) private var metro
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let dots = 5
    /// One sweep of all the dots, the pause before the next included.
    static let period = 2.6
    /// Each dot's time on screen, as a share of the period, and the gap between one dot and the next.
    static let travel = 0.62
    static let stagger = 0.07

    /// Where along the row (0...1) a dot is at `phase` (0...1 of its own travel): fast in, slow through the middle,
    /// fast out.
    static func position(at phase: Double) -> Double {
        let t = 2 * phase - 1
        return 0.5 + 0.5 * t * t * t
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(paused: reduceMotion)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                ZStack(alignment: .leading) {
                    ForEach(0..<Self.dots, id: \.self) { dot in
                        let phase = (time / Self.period - Double(dot) * Self.stagger).truncatingRemainder(dividingBy: 1)
                        let local = (phase < 0 ? phase + 1 : phase) / Self.travel
                        // Still: the dots sit in a short row in the middle.
                        let x = reduceMotion ? 0.5 + (Double(dot) - 2) * 0.02 : Self.position(at: local)
                        Rectangle()
                            .fill(metro.accentColor)
                            .frame(width: 4, height: 4)
                            .offset(x: (geo.size.width - 4) * x)
                            .opacity(reduceMotion || local < 1 ? 1 : 0)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityLabel("Loading")
    }
}
