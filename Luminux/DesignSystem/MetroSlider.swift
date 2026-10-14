import SwiftUI

/// A flat track with a square thumb. The accent fills from the resting value to the thumb, so a slider that goes
/// both ways fills out from the middle. Drags move the value relative to where they start, so touching the track
/// doesn't make it jump; a double tap puts it back.
struct MetroSlider: View {
    let label: String
    @Binding var value: Double
    var range: ClosedRange<Double> = -1...1
    var resting: Double = 0

    @Environment(\.metro) private var metro
    @State private var dragStart: Double?

    private static let thumbWidth: CGFloat = 12
    private static let snap = 0.03

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width - Self.thumbWidth, 1)
            let x = position(of: value, width: width)
            let restX = position(of: resting, width: width)
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(metro.foreground.opacity(0.3))
                    .frame(height: 4)
                    .padding(.horizontal, Self.thumbWidth / 2)
                Rectangle()
                    .fill(metro.accentColor)
                    .frame(width: abs(x - restX), height: 4)
                    .offset(x: min(x, restX) + Self.thumbWidth / 2)
                // Marks the resting value on two-way sliders.
                if resting > range.lowerBound {
                    Rectangle()
                        .fill(metro.foreground.opacity(0.6))
                        .frame(width: 2, height: 12)
                        .offset(x: restX + Self.thumbWidth / 2 - 1)
                }
                Rectangle()
                    .fill(metro.foreground)
                    .frame(width: Self.thumbWidth, height: 28)
                    .offset(x: x)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let start = dragStart ?? value
                        dragStart = start
                        let span = range.upperBound - range.lowerBound
                        set(start + Double(drag.translation.width / width) * span)
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .onTapGesture(count: 2) {
                withAnimation(MetroMotion.snappy) { value = resting }
            }
        }
        .frame(height: 44)
        .sensoryFeedback(.selection, trigger: value == resting) { _, isResting in isResting }
        .accessibilityRepresentation {
            Slider(value: $value, in: range) { Text(label) }
        }
    }

    private func position(of value: Double, width: CGFloat) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        return CGFloat((value - range.lowerBound) / span) * width
    }

    /// Clamps to the range and catches the resting value, so it's easy to land on exactly.
    private func set(_ newValue: Double) {
        let clamped = min(max(newValue, range.lowerBound), range.upperBound)
        value = abs(clamped - resting) < Self.snap ? resting : clamped
    }
}
