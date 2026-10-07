#if DEBUG
import SwiftUI

/// Debug-only showcase of the Metro components. Launch with `-gallery panorama` or `-gallery pivot`.
struct ComponentGallery: View {
    enum Kind: String { case panorama, pivot }

    let kind: Kind

    static var requested: Kind? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-gallery"), arguments.indices.contains(index + 1) else { return nil }
        return Kind(rawValue: arguments[index + 1])
    }

    var body: some View {
        switch kind {
        case .panorama: PanoramaDemo()
        case .pivot: PivotDemo()
        }
    }
}

private struct Swatch: Identifiable {
    let id: Int
    let color: Color
}

private let swatches = Accent.presets.enumerated().map { Swatch(id: $0.offset, color: $0.element.color) }

private struct PanoramaDemo: View {
    @State private var isAppBarExpanded = false
    @State private var showsJumpList = false
    @State private var showsPage = false
    @Environment(\.metro) private var metro
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = [GridItem(.fixed(150), spacing: MetroMetrics.gutter), GridItem(.fixed(150), spacing: MetroMetrics.gutter)]

    var body: some View {
        ZStack {
            Panorama("photos") {
                PanoramaSection("collection") {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: MetroMetrics.gutter) {
                        MetroTile(title: "camera roll", action: {}) { swatches[4].color }
                            .aspectRatio(1, contentMode: .fit)
                        MetroTile(title: "albums", action: {}) {
                            metro.accentColor.overlay {
                                Image(systemName: "rectangle.stack").font(.system(size: 34, weight: .ultraLight)).foregroundStyle(.white)
                            }
                        }
                        .aspectRatio(1, contentMode: .fit)
                        MetroTile(title: "date", action: { showsJumpList = true }) {
                            LiveTile(items: swatches, style: .slide, interval: 2...3) { $0.color }
                        }
                        .aspectRatio(1, contentMode: .fit)
                        MetroTile(title: "favorites", action: {}) {
                            LiveTile(items: swatches.reversed(), style: .flip, interval: 2...4) { $0.color }
                        }
                        .aspectRatio(1, contentMode: .fit)
                    }
                }
                PanoramaSection("what's new") {
                    VStack(alignment: .leading, spacing: 16) {
                        Button("open a page") { withAnimation(MetroMotion.standard) { showsPage = true } }
                            .buttonStyle(.metro)
                        staticTiltSamples
                    }
                }
                PanoramaSection("favorites") {
                    Text("third panel").font(.metroBody)
                }
            } background: {
                HStack(spacing: 0) {
                    ForEach(swatches) { swatch in swatch.color.opacity(0.6) }
                }
            }
            .metroAppBar(
                [
                    AppBarButton(title: "select", systemImage: "checklist") {},
                    AppBarButton(title: "camera", systemImage: "camera") {},
                ],
                menu: [
                    AppBarMenuItem(title: "settings") {},
                    AppBarMenuItem(title: "jump list") { showsJumpList = true },
                ],
                isExpanded: $isAppBarExpanded
            )

            if showsPage {
                DemoPage { withAnimation(MetroMotion.standard) { showsPage = false } }
                    .zIndex(1)
                    .transition(.asymmetric(
                        insertion: .metroPage(.forward, reduceMotion: reduceMotion),
                        removal: .metroPage(.backward, reduceMotion: reduceMotion)
                    ))
            }

            if showsJumpList {
                JumpListView(sections: DemoData.sections, currentSectionID: DemoData.sections.first?.id) { _ in
                    withAnimation(MetroMotion.standard) { showsJumpList = false }
                }
                .zIndex(2)
                .transition(.scale(scale: 1.1).combined(with: .opacity))
            }
        }
        .animation(MetroMotion.standard, value: showsJumpList)
    }

    /// Fixed poses for checking the 3D directions in screenshots.
    private var staticTiltSamples: some View {
        HStack(spacing: 16) {
            let size = CGSize(width: 100, height: 100)
            let tilt = Tilt.pressed(at: CGPoint(x: 100, y: 50), in: size)
            Text("right edge")
                .font(.metroCaption)
                .frame(width: 100, height: 100)
                .background(metro.accentColor)
                .perspectiveRotation(tilt.angle, axis: (x: tilt.axisX, y: tilt.axisY, z: 0), perspective: 0.6)
            Text("turnstile in")
                .font(.metroCaption)
                .frame(width: 100, height: 100)
                .background(metro.accentColor)
                .perspectiveRotation(-40, axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.7)
        }
    }
}

private struct DemoPage: View {
    let onBack: () -> Void
    @Environment(\.metro) private var metro

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LUMINUX").font(.metroOverline).tracking(1.5)
            Text("page").font(.metroTitle)
            Text("Turnstile in, back to turnstile out.").font(.metroBody).foregroundStyle(metro.secondary)
            Button("back", action: onBack).buttonStyle(.metro)
            Spacer()
        }
        .padding(.horizontal, MetroMetrics.margin + 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(metro.foreground)
        .background(metro.background)
    }
}

private struct PivotDemo: View {
    @State private var selection = 0
    @State private var showsJumpList = false
    @Environment(\.metro) private var metro

    private let columns = Array(repeating: GridItem(.flexible(), spacing: MetroMetrics.gutter), count: 4)

    var body: some View {
        Pivot(overline: "LUMINUX", selection: $selection) {
            ForEach(["all", "albums", "favorites", "videos"], id: \.self) { title in
                ScrollView {
                    Button("october 2026") { showsJumpList = true }
                        .font(.metro(20, .semilight))
                        .foregroundStyle(metro.accentColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    LazyVGrid(columns: columns, spacing: MetroMetrics.gutter) {
                        ForEach(swatches) { swatch in
                            MetroTile(action: {}) { swatch.color }
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
                .padding(.horizontal, MetroMetrics.margin)
                .pivotTitle(title)
            }
        }
        .overlay {
            if showsJumpList {
                JumpListView(sections: DemoData.sections, currentSectionID: DemoData.sections.first?.id) { _ in
                    showsJumpList = false
                }
                .transition(.scale(scale: 1.1).combined(with: .opacity))
            }
        }
        .animation(MetroMotion.standard, value: showsJumpList)
    }
}

private enum DemoData {
    static let sections: [MonthSection] = [
        MonthSection(year: 2026, month: 10, range: 0..<12),
        MonthSection(year: 2026, month: 9, range: 12..<13),
        MonthSection(year: 2026, month: 7, range: 13..<20),
        MonthSection(year: 2025, month: 12, range: 20..<22),
        MonthSection(year: 2025, month: 3, range: 22..<30),
        MonthSection(year: 0, month: 0, range: 30..<31),
    ]
}
#endif
