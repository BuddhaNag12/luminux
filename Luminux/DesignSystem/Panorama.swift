import SwiftUI

/// Horizontally scrolling hub with a wide title and background that move slower than the panels.
///
/// It opens on `startPanel`; panels before it sit to the left under their own `leadingTitle`. Swiping into them pushes
/// the main title off the right edge, brings the leading title in from the left, and moves the background the other
/// way.
struct Panorama<Background: View, Content: View>: View {
    let title: String
    var leadingTitle: String?
    var startPanel = 0
    var onPanelChange: ((Int) -> Void)?
    var background: Background?
    var content: Content

    init(
        _ title: String,
        leadingTitle: String? = nil,
        startPanel: Int = 0,
        onPanelChange: ((Int) -> Void)? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder background: () -> Background
    ) {
        self.title = title
        self.leadingTitle = leadingTitle
        self.startPanel = startPanel
        self.onPanelChange = onPanelChange
        self.content = content()
        self.background = background()
    }

    /// How much of the next panel shows at the right edge.
    static var peek: CGFloat { 44 }

    @State private var scrollOffset: CGFloat = 0
    @State private var scrollRange: CGFloat = 0
    @State private var position = ScrollPosition(idType: Int.self)
    @State private var panelWidth: CGFloat = 0
    @State private var titleWidth: CGFloat = 0
    /// What the app bar and home indicator cover, measured before the panels extend under them.
    @State private var bottomInset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.metro) private var metro

    private var leadingWidth: CGFloat { CGFloat(startPanel) * panelWidth }
    /// Measured from the start panel, so it's negative in the panels to its left.
    private var offset: CGFloat { scrollOffset - leadingWidth }
    private var maxOffset: CGFloat { scrollRange - leadingWidth }
    private var parallaxOffset: CGFloat { reduceMotion ? 0 : offset }
    private var scrolledPanel: Int? { position.viewID(type: Int.self) }
    private var isOnLeadingPanel: Bool { (scrolledPanel ?? startPanel) < startPanel }

    /// How far into the panels left of the start: 0 on the start panel, 1 on the first leading panel.
    private var leadingProgress: CGFloat {
        guard leadingWidth > 0 else { return 0 }
        return min(max(-offset / leadingWidth, 0), 1)
    }

    /// The title slides off the left edge a little more on every panel ("photos", "otos", "tos"), so it keeps moving
    /// to the last panel instead of stopping early.
    private var titleShift: CGFloat {
        guard maxOffset > 0 else { return 0 }
        let progress = min(max(parallaxOffset / maxOffset, 0), 1)
        return progress * (MetroMetrics.margin + 4 + titleWidth * MetroMotion.titleTravel)
    }

    var body: some View {
        GeometryReader { geo in
            let panelWidth = geo.size.width - Self.peek

            VStack(alignment: .leading, spacing: 0) {
                panoramaTitle(title)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { titleWidth = $0 }
                    .accessibilityHidden(isOnLeadingPanel)
                    // A screen to the left of the main title, so each sits fully off screen while the other shows.
                    .overlay(alignment: .leading) {
                        if let leadingTitle {
                            panoramaTitle(leadingTitle)
                                .offset(x: -geo.size.width)
                                .accessibilityHidden(!isOnLeadingPanel)
                        }
                    }
                    // Follows the panels into the leading ones, so it isn't parallax and moves with Reduce Motion too.
                    .offset(x: leadingProgress * geo.size.width - titleShift)
                    .frame(width: geo.size.width, alignment: .leading)
                    .clipped()
                    .metroFeather(row: 0)

                Group(subviews: content) { panels in
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 0) {
                            ForEach(panels.indices, id: \.self) { index in
                                panels[index]
                                    // Panels to the left of the one on screen don't feather: they hinge on the screen
                                    // edge, so their tiles would swing into view.
                                    .transformEnvironment(\.feather) { context in
                                        if index < (scrolledPanel ?? startPanel) { context = FeatherContext() }
                                    }
                                    .contentMargins(.bottom, bottomInset, for: .scrollContent)
                                    .frame(width: panelWidth, alignment: .topLeading)
                                    .id(index)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.viewAligned)
                    // An initial id in the scroll position is ignored at first layout here, so the start panel is set
                    // as a fraction of the scroll range, which is known from the panel count.
                    .defaultScrollAnchor(
                        startAnchor(panels: panels.count, panelWidth: panelWidth, screenWidth: geo.size.width),
                        for: .initialOffset
                    )
                    .scrollPosition($position, anchor: .leading)
                    .scrollIndicators(.hidden)
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        geometry.contentOffset.x + geometry.contentInsets.leading
                    } action: { _, newValue in
                        scrollOffset = newValue
                    }
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        geometry.contentSize.width - geometry.containerSize.width
                    } action: { _, newValue in
                        scrollRange = newValue
                    }
                }
                // Panels run under the app bar; their content can still scroll clear of it.
                .ignoresSafeArea(.container, edges: .bottom)
            }
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomInset = $0 }
            .onChange(of: panelWidth, initial: true) { _, width in self.panelWidth = width }
        }
        .onChange(of: scrolledPanel) { _, panel in
            if let panel { onPanelChange?(panel) }
        }
        .onChange(of: startPanel) { old, new in
            // A panel added or removed on the left shifts every index; stay on the same panel.
            position.scrollTo(id: max((scrolledPanel ?? old) + new - old, 0), anchor: .leading)
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

    private func panoramaTitle(_ text: String) -> some View {
        Text(text)
            .font(.metroPanorama)
            .lineLimit(1)
            .fixedSize()
            .padding(.leading, MetroMetrics.margin + 4)
            .accessibilityAddTraits(.isHeader)
    }

    private func startAnchor(panels: Int, panelWidth: CGFloat, screenWidth: CGFloat) -> UnitPoint {
        let range = CGFloat(panels) * panelWidth - screenWidth
        guard startPanel > 0, range > 0 else { return .topLeading }
        return UnitPoint(x: min(CGFloat(startPanel) * panelWidth / range, 1), y: 0)
    }

    private func backgroundLayer(_ background: Background, size: CGSize, panelWidth: CGFloat) -> some View {
        // Wide enough to cover the screen through about four panels of parallax, plus the panels left of the start.
        let leading = CGFloat(startPanel) * panelWidth * MetroMotion.backgroundParallax
        let width = size.width + panelWidth * 4 * MetroMotion.backgroundParallax + leading
        return background
            .frame(width: width, height: size.height)
            .clipped()
            .overlay(metro.background.opacity(metro.theme == .dark ? 0.45 : 0.55))
            .offset(x: -leading - parallaxOffset * MetroMotion.backgroundParallax)
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
