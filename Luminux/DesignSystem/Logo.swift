import SwiftUI

/// The app icon's glyph: three offset tiles in the accent colour with a photo (sun and hills) cut into the front one.
/// The state flags drive its entrance; with all of them set it's the finished mark.
struct LogoMark: View {
    /// Points per unit of the 120-unit tile the icon is drawn on; the mark is 66 by 70 units.
    var unit: CGFloat
    /// Back to front.
    var tilesIn = [true, true, true]
    var showsPhoto = true
    /// The colour the photo is cut out in, usually the background behind the mark.
    var cutout: Color

    @Environment(\.metro) private var metro

    private static let tiles = [CGPoint(x: 46, y: 24), CGPoint(x: 36, y: 36), CGPoint(x: 26, y: 48)]
    private static let tileSide: CGFloat = 46
    private static let origin = CGPoint(x: 26, y: 24)
    static let size = CGSize(width: 66, height: 70)
    private static let opacities = [0.45, 0.7, 1.0]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<3, id: \.self) { index in
                let point = Self.tiles[index]
                RoundedRectangle(cornerRadius: 3 * unit)
                    .fill(metro.accentColor.opacity(Self.opacities[index]))
                    .frame(width: Self.tileSide * unit, height: Self.tileSide * unit)
                    .offset(x: (point.x - Self.origin.x) * unit, y: (point.y - Self.origin.y) * unit)
                    .offset(y: tilesIn[index] ? 0 : 33 * unit)
                    .opacity(tilesIn[index] ? 1 : 0)
            }
            photo
        }
        .frame(width: Self.size.width * unit, height: Self.size.height * unit, alignment: .topLeading)
    }

    private var photo: some View {
        let shift = { (point: CGPoint) in CGPoint(x: (point.x - Self.origin.x) * unit, y: (point.y - Self.origin.y) * unit) }
        let hills = [CGPoint(x: 30, y: 88), CGPoint(x: 44, y: 74), CGPoint(x: 52, y: 82), CGPoint(x: 60, y: 76), CGPoint(x: 68, y: 88)].map(shift)
        let sun = shift(CGPoint(x: 58, y: 62))
        return ZStack(alignment: .topLeading) {
            Path { $0.addLines(hills) }
                .trim(from: 0, to: showsPhoto ? 1 : 0)
                .stroke(cutout, style: StrokeStyle(lineWidth: 4 * unit, lineCap: .round, lineJoin: .round))
            Circle()
                .fill(cutout)
                .frame(width: 10 * unit, height: 10 * unit)
                .scaleEffect(showsPhoto ? 1 : 0.01)
                .offset(x: sun.x - 5 * unit, y: sun.y - 5 * unit)
        }
    }

    /// Back to front, 90 ms apart, then the photo draws on: the same entrance as the launch.
    static func playEntrance(tilesIn: Binding<[Bool]>, showsPhoto: Binding<Bool>) async {
        for index in 0..<3 {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { tilesIn.wrappedValue[index] = true }
            try? await Task.sleep(for: .milliseconds(90))
        }
        try? await Task.sleep(for: .milliseconds(180))
        withAnimation(.easeOut(duration: 0.3)) { showsPhoto.wrappedValue = true }
    }
}

extension EnvironmentValues {
    /// True while the launch animation covers the screen.
    @Entry var isLaunchSplashShowing = false
}

/// The mark with the name beside it. The mark stacks in, then "luminux" types in letter by letter from the left,
/// each letter sliding a little as it fades in. Plays each time it appears; Reduce Motion shows it finished.
struct LogoLockup: View {
    var unit: CGFloat = 1
    var cutout: Color

    @Environment(\.metro) private var metro
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLaunchSplashShowing) private var isSplashShowing
    @State private var tilesIn = [false, false, false]
    @State private var showsPhoto = false
    @State private var lettersIn = 0

    private static let name = Array("luminux")

    var body: some View {
        let isFinished = reduceMotion
        HStack(alignment: .center, spacing: 14 * unit) {
            LogoMark(unit: unit, tilesIn: isFinished ? [true, true, true] : tilesIn, showsPhoto: isFinished || showsPhoto, cutout: cutout)
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
            tilesIn = [false, false, false]
            showsPhoto = false
            lettersIn = 0
        }
        // Waits for the launch splash, or the whole entrance would play hidden under it.
        .task(id: isSplashShowing) {
            guard !reduceMotion, !isSplashShowing else { return }
            await LogoMark.playEntrance(tilesIn: $tilesIn, showsPhoto: $showsPhoto)
            for count in 1...Self.name.count {
                try? await Task.sleep(for: .milliseconds(45))
                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { lettersIn = count }
            }
        }
    }
}
