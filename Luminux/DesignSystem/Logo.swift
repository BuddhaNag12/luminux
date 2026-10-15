import SwiftUI

/// The "Tile L" mark: a tall tile turning on its left edge, like a live tile mid-turn, and a wide tile with hills cut
/// into it form an L; a quarter sun rises out of the L's inner corner. Laid out on the same 120-unit grid as the app
/// icon (`scripts/make-app-icon.swift`) and the brand files (`scripts/make-brand.swift`). The phase drives its entrance.
struct LogoMark: View {
    /// Points per grid unit; the mark is 66 by 68 units.
    var unit: CGFloat
    var phase: Phase = .finished
    /// The colour the hills are cut out in, usually the background behind the mark.
    var cutout: Color

    @Environment(\.metro) private var metro

    struct Phase: Equatable {
        var baseIn = false
        /// Degrees the tall tile is turned: 90 is edge-on (hidden), 28 is the resting pose.
        var flapAngle: Double = 90
        var sunLit = false
        /// How much of the hill line is drawn, 0 to 1.
        var hills: CGFloat = 0

        static let hidden = Phase()
        static let finished = Phase(baseIn: true, flapAngle: LogoMark.restAngle, sunLit: true, hills: 1)
    }

    static let restAngle: Double = 28
    static let size = CGSize(width: 66, height: 68)

    private static let origin = CGPoint(x: 28, y: 26)
    private static let tall = CGRect(x: 28, y: 26, width: 28, height: 68)
    private static let wide = CGRect(x: 60, y: 62, width: 34, height: 32)
    private static let sunCorner = CGPoint(x: 60, y: 58)
    private static let sunRadius: CGFloat = 22
    private static let hills: [CGPoint] = [CGPoint(x: 64, y: 89), CGPoint(x: 71, y: 80), CGPoint(x: 77, y: 85), CGPoint(x: 84, y: 75), CGPoint(x: 90, y: 83)]
    private static let hillWidth: CGFloat = 3.4

    var body: some View {
        let u = unit
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(metro.accentColor.opacity(0.85))
                .frame(width: Self.tall.width * u, height: Self.tall.height * u)
                // Turns on its left edge with the same perspective as page turns.
                .perspectiveRotation(phase.flapAngle, axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.7)
                .opacity(phase.flapAngle >= 89 ? 0 : 1)

            Rectangle()
                .fill(metro.accentColor)
                .frame(width: Self.wide.width * u, height: Self.wide.height * u)
                .overlay(alignment: .topLeading) {
                    Path { path in
                        path.addLines(Self.hills.map { CGPoint(x: ($0.x - Self.wide.minX) * u, y: ($0.y - Self.wide.minY) * u) })
                    }
                    .trim(from: 0, to: phase.hills)
                    .stroke(cutout, style: StrokeStyle(lineWidth: Self.hillWidth * u, lineCap: .round, lineJoin: .round))
                }
                .offset(x: (Self.wide.minX - Self.origin.x) * u, y: (Self.wide.minY - Self.origin.y) * u)
                .offset(y: phase.baseIn ? 0 : 10 * u)
                .opacity(phase.baseIn ? 1 : 0)

            QuarterSun()
                .fill(metro.accentColor)
                .frame(width: Self.sunRadius * u, height: Self.sunRadius * u)
                // Grows out of the corner it rises from.
                .scaleEffect(phase.sunLit ? 1 : 0.01, anchor: .bottomLeading)
                .offset(x: (Self.sunCorner.x - Self.origin.x) * u, y: (Self.sunCorner.y - Self.sunRadius - Self.origin.y) * u)
        }
        .frame(width: Self.size.width * u, height: Self.size.height * u, alignment: .topLeading)
    }

    /// The wide tile rises in, the tall tile turns in from edge-on and settles, the sun grows out of the corner, and
    /// the hills draw left to right.
    static func playEntrance(_ phase: Binding<Phase>) async {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { phase.wrappedValue.baseIn = true }
        try? await Task.sleep(for: .milliseconds(120))
        // A loose spring, so the tile overshoots a little and settles like a real turn.
        withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { phase.wrappedValue.flapAngle = restAngle }
        try? await Task.sleep(for: .milliseconds(300))
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { phase.wrappedValue.sunLit = true }
        try? await Task.sleep(for: .milliseconds(120))
        withAnimation(.easeOut(duration: 0.35)) { phase.wrappedValue.hills = 1 }
    }
}

/// A quarter disc whose centre is the bottom-left corner of its frame.
private nonisolated struct QuarterSun: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for step in 0...24 {
            let t = Double(step) / 24 * .pi / 2
            path.addLine(to: CGPoint(x: rect.minX + rect.width * sin(t), y: rect.maxY - rect.height * cos(t)))
        }
        path.closeSubpath()
        return path
    }
}

extension EnvironmentValues {
    /// True while the launch animation covers the screen.
    @Entry var isLaunchSplashShowing = false
}

/// The mark with the name beside it. The mark plays its entrance, and "luminux" types in letter by letter as the tall
/// tile lands, each letter sliding a little as it fades in. Plays each time it appears; Reduce Motion shows it finished.
struct LogoLockup: View {
    var unit: CGFloat = 1
    var cutout: Color

    @Environment(\.metro) private var metro
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLaunchSplashShowing) private var isSplashShowing
    @State private var phase = LogoMark.Phase.hidden
    @State private var lettersIn = 0

    private static let name = Array("luminux")

    var body: some View {
        let isFinished = reduceMotion
        HStack(alignment: .center, spacing: 14 * unit) {
            LogoMark(unit: unit * 0.95, phase: isFinished ? .finished : phase, cutout: cutout)
            HStack(spacing: 0) {
                ForEach(Self.name.indices, id: \.self) { index in
                    let isIn = isFinished || index < lettersIn
                    Text(String(Self.name[index]))
                        .offset(x: isIn ? 0 : -10 * unit)
                        .opacity(isIn ? 1 : 0)
                }
            }
            .font(.metro(52 * unit, .light, relativeTo: .largeTitle))
            .foregroundStyle(metro.foreground)
            .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Luminux")
        .accessibilityAddTraits(.isHeader)
        .onAppear {
            guard !reduceMotion else { return }
            phase = .hidden
            lettersIn = 0
        }
        // Waits for the launch splash, or the whole entrance would play hidden under it.
        .task(id: isSplashShowing) {
            guard !reduceMotion, !isSplashShowing else { return }
            let letters = Task {
                try? await Task.sleep(for: .milliseconds(420))
                for count in 1...Self.name.count {
                    guard !Task.isCancelled else { return }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { lettersIn = count }
                    try? await Task.sleep(for: .milliseconds(45))
                }
            }
            await LogoMark.playEntrance($phase)
            await letters.value
        }
    }
}
