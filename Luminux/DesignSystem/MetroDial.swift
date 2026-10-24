import SwiftUI

/// A ruler for one value: its ticks slide under a fixed accent line as you drag, like the editing dials in Photos and
/// VSCO. Each tick passing clicks like a detent, the resting value lands with a firmer knock, and the ends bump; a
/// double tap returns to rest.
struct MetroDial: View {
    let label: String
    @Binding var value: Double
    var range: ClosedRange<Double> = -1...1
    var resting: Double = 0
    /// Ticks across the whole range; every fifth is longer.
    var ticks = 40
    var format: (Double) -> String = { MetroDial.text(for: $0) }

    @Environment(\.metro) private var metro
    @State private var dragStart: Double?

    /// How far a drag goes to cover the whole range.
    static let pointsPerRange: CGFloat = 480
    /// How close to the resting value counts as on it, as a share of half the range.
    static let snap = 0.03

    /// The value a drag of `distance` points sets, starting from `start`: dragging left raises it, as the ruler moves
    /// with the finger. Clamped to the range, and caught at the resting value.
    static func value(from start: Double, dragged distance: CGFloat, range: ClosedRange<Double>, resting: Double) -> Double {
        let span = range.upperBound - range.lowerBound
        let raw = start - Double(distance / pointsPerRange) * span
        let clamped = min(max(raw, range.lowerBound), range.upperBound)
        return abs(clamped - resting) < snap * span / 2 ? resting : clamped
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(format(value))
                .font(.metro(17, .semilight))
                .monospacedDigit()
                .foregroundStyle(value == resting ? metro.secondary : metro.accentColor)
            ruler
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    let start = dragStart ?? value
                    dragStart = start
                    value = Self.value(from: start, dragged: drag.translation.width, range: range, resting: resting)
                }
                .onEnded { _ in dragStart = nil }
        )
        .onTapGesture(count: 2) {
            withAnimation(MetroMotion.snappy) { value = resting }
        }
        // A light click for every tick that passes the line, a firmer one landing on rest, a bump at either end.
        .sensoryFeedback(.selection, trigger: tick)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.9), trigger: value == resting) { _, isResting in isResting }
        .sensoryFeedback(.impact(weight: .heavy, intensity: 0.6), trigger: value == range.lowerBound || value == range.upperBound) { _, atEnd in atEnd }
        .accessibilityRepresentation {
            Slider(value: $value, in: range) { Text(label) }
        }
    }

    /// The tick nearest the line, so each one passing can click.
    private var tick: Int {
        let span = range.upperBound - range.lowerBound
        return Int(((value - range.lowerBound) / span * Double(ticks)).rounded())
    }

    private var ruler: some View {
        Canvas { [value, range, resting, metro, ticks] context, size in
            let span = range.upperBound - range.lowerBound
            let middle = size.width / 2
            for index in 0...ticks {
                let tick = range.lowerBound + span * Double(index) / Double(ticks)
                let x = middle + CGFloat((tick - value) / span) * Self.pointsPerRange
                guard x > -2, x < size.width + 2 else { continue }
                let isResting = abs(tick - resting) < span / Double(ticks) / 2
                let height: CGFloat = isResting ? size.height : index % 5 == 0 ? size.height * 0.6 : size.height * 0.35
                let line = Path(CGRect(x: x - 0.75, y: (size.height - height) / 2, width: 1.5, height: height))
                context.fill(line, with: .color(metro.foreground.opacity(isResting ? 0.9 : 0.45)))
            }
        }
        .frame(height: 28)
        .overlay {
            Rectangle().fill(metro.accentColor).frame(width: 3, height: 36)
        }
        // Ticks fade toward the ends, so the ruler reads as running on past them.
        .mask {
            LinearGradient(stops: [
                .init(color: .clear, location: 0), .init(color: .black, location: 0.2),
                .init(color: .black, location: 0.8), .init(color: .clear, location: 1),
            ], startPoint: .leading, endPoint: .trailing)
        }
    }

    /// "+12.5°", "-3°" or "0°".
    static func degrees(_ value: Double) -> String {
        let tenths = (value * 10).rounded() / 10
        let text = tenths == tenths.rounded() ? String(Int(tenths)) : String(format: "%.1f", tenths)
        return (tenths > 0 ? "+" : "") + text + "°"
    }

    /// "+24", "-7" or "0".
    static func text(for value: Double) -> String {
        let rounded = Int((value * 100).rounded())
        return rounded > 0 ? "+\(rounded)" : "\(rounded)"
    }
}
