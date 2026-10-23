import SwiftUI

/// Slow abstract backgrounds for the hub tiles that have no photos. Drawn in one `Canvas` at 30 fps (plenty for motion
/// this slow), and stopped whenever live tiles are paused (the hub covered or another panel showing), when "tile
/// patterns" is off in settings, or with Reduce Motion.
struct AmbientTile: View {
    enum Pattern {
        /// Three translucent squares, stacked like album covers, drifting around one another.
        case albums
        /// This month as a grid of squares: past days a little brighter than the ones ahead, today solid and gently
        /// pulsing, and a slow glow travelling through the days.
        case date
    }

    let pattern: Pattern

    @Environment(\.metro) private var metro
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let isPaused = reduceMotion || !settings.animatesTilePatterns || LiveTileScheduler.shared.isPaused
        // shortcut: wall-clock time, so the drift jumps a little after a long pause; fine at these speeds.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: isPaused)) { context in
            Canvas { canvas, size in
                let time = context.date.timeIntervalSinceReferenceDate
                switch pattern {
                case .albums: drawAlbums(in: &canvas, size: size, time: time)
                case .date: drawMonth(in: &canvas, size: size, time: time, now: context.date)
                }
            }
        }
        .background(metro.accentColor)
        .tileOnAccent()
        .accessibilityHidden(true)
    }

    private func drawAlbums(in canvas: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let side = min(size.width, size.height) * 0.42
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let step = side * 0.2
        let opacities = [0.12, 0.2, 0.32]
        for index in 0..<3 {
            let phase = time * 2 * .pi / 14 + Double(index) * 2.1
            let drift = side * 0.08
            // Back to front, up and to the right, each circling slowly on its own.
            let back = CGFloat(2 - index)
            let x = center.x + back * step - step + drift * cos(phase)
            let y = center.y - back * step + step + drift * sin(phase)
            let tilt = Angle.degrees(4 * sin(time * 2 * .pi / 11 + Double(index)))
            var square = canvas
            square.translateBy(x: x, y: y)
            square.rotate(by: tilt)
            square.fill(Path(CGRect(x: -side / 2, y: -side / 2, width: side, height: side)), with: .color(metro.onAccent.opacity(opacities[index])))
        }
    }

    private func drawMonth(in canvas: inout GraphicsContext, size: CGSize, time: TimeInterval, now: Date) {
        // A small tile only has room for the day number.
        guard min(size.width, size.height) > 120 else { return }
        let calendar = Calendar.current
        guard let days = calendar.range(of: .day, in: .month, for: now)?.count,
              let first = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else { return }
        let today = calendar.component(.day, from: now) - 1
        // Monday-first columns, like a wall calendar.
        let lead = (calendar.component(.weekday, from: first) + 5) % 7
        let rows = (lead + days + 6) / 7

        // Right of the date on a wide tile, under it on a square one, so the numbers stay clear.
        let inset: CGFloat = 12
        let isWide = size.width > size.height * 1.5
        let area = isWide
            ? CGRect(x: size.width * 0.42, y: inset, width: size.width * 0.58 - inset, height: size.height - inset * 2)
            : CGRect(x: size.width * 0.3, y: size.height * 0.46, width: size.width * 0.7 - inset, height: size.height * 0.54 - inset)
        let cell = min(area.width / 7, area.height / CGFloat(rows))
        let gap = cell * 0.2
        let origin = CGPoint(x: area.maxX - cell * 7, y: area.maxY - cell * CGFloat(rows))

        let pulse = 1 + 0.08 * sin(time * 2 * .pi / 4)
        for day in 0..<days {
            let slot = lead + day
            let rect = CGRect(
                x: origin.x + CGFloat(slot % 7) * cell + gap / 2,
                y: origin.y + CGFloat(slot / 7) * cell + gap / 2,
                width: cell - gap, height: cell - gap
            )
            if day == today {
                let grown = rect.insetBy(dx: -rect.width * (pulse - 1) / 2, dy: -rect.height * (pulse - 1) / 2)
                canvas.fill(Path(grown), with: .color(metro.onAccent))
                continue
            }
            // A glow sweeps through the month every 10 s.
            let wave = max(0, cos(2 * .pi * (time / 10 - Double(day) / Double(days))))
            let base = day < today ? 0.24 : 0.12
            canvas.fill(Path(rect), with: .color(metro.onAccent.opacity(base + 0.18 * pow(wave, 6))))
        }
    }
}
