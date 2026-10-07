import SwiftUI

/// Horizontally scrolling hub with a wide title and background that move slower than the panels.
struct Panorama<Background: View, Content: View>: View {
    let title: String
    var background: Background?
    var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content, @ViewBuilder background: () -> Background) {
        self.title = title
        self.content = content()
        self.background = background()
    }

    /// How much of the next panel shows at the right edge.
    static var peek: CGFloat { 44 }

    @State private var offset: CGFloat = 0
    @State private var maxOffset: CGFloat = 0
    @State private var titleWidth: CGFloat = 0
    /// What the app bar and home indicator cover, measured before the panels extend under them.
    @State private var bottomInset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.metro) private var metro

    private var parallaxOffset: CGFloat { reduceMotion ? 0 : max(offset, 0) }

    /// The title slides off the left edge a little more on every panel ("photos", "otos", "tos"), so it keeps moving
    /// to the last panel instead of stopping early.
    private var titleShift: CGFloat {
        guard maxOffset > 0 else { return 0 }
        let progress = min(parallaxOffset / maxOffset, 1)
        return progress * (MetroMetrics.margin + 4 + titleWidth * MetroMotion.titleTravel)
    }

    var body: some View {
        GeometryReader { geo in
            let panelWidth = geo.size.width - Self.peek

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.metroPanorama)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.leading, MetroMetrics.margin + 4)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { titleWidth = $0 }
                    .offset(x: -titleShift)
                    .frame(width: geo.size.width, alignment: .leading)
                    .clipped()
                    .metroFeather(row: 0)
                    .accessibilityAddTraits(.isHeader)

                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 0) {
                        ForEach(subviews: content) { panel in
                            panel
                                .contentMargins(.bottom, bottomInset, for: .scrollContent)
                                .frame(width: panelWidth, alignment: .topLeading)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.x + geometry.contentInsets.leading
                } action: { _, newValue in
                    offset = newValue
                }
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentSize.width - geometry.containerSize.width
                } action: { _, newValue in
                    maxOffset = newValue
                }
                // Panels run under the app bar; their content can still scroll clear of it.
                .ignoresSafeArea(.container, edges: .bottom)
            }
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomInset = $0 }
        }
        .foregroundStyle(metro.foreground)
        .background {
            // Separate reader so the background runs under the status bar and app bar too.
            GeometryReader { geo in
                if let background {
                    backgroundLayer(background, size: geo.size, panelWidth: geo.size.width - Self.peek)
                }
            }
            .ignoresSafeArea()
        }
        .background(metro.background)
    }

    private func backgroundLayer(_ background: Background, size: CGSize, panelWidth: CGFloat) -> some View {
        // Wide enough to cover the screen through about four panels of parallax.
        let width = size.width + panelWidth * 4 * MetroMotion.backgroundParallax
        return background
            .frame(width: width, height: size.height)
            .clipped()
            .overlay(metro.background.opacity(metro.theme == .dark ? 0.45 : 0.55))
            .offset(x: -parallaxOffset * MetroMotion.backgroundParallax)
            .frame(width: size.width, height: size.height, alignment: .leading)
            .clipped()
            .accessibilityHidden(true)
    }
}

extension Panorama where Background == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
        self.background = nil
    }
}

/// One panel of a `Panorama`: a section header over vertically scrolling content.
struct PanoramaSection<Content: View>: View {
    let header: String
    @ViewBuilder var content: Content

    init(_ header: String, @ViewBuilder content: () -> Content) {
        self.header = header
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(header)
                .font(.metroSection)
                .padding(.leading, MetroMetrics.margin)
                .metroFeather(row: 1)
                .accessibilityAddTraits(.isHeader)

            ScrollView(.vertical) {
                content
                    .padding(.leading, MetroMetrics.margin)
                    .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
    }
}
