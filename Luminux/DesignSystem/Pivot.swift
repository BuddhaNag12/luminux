import SwiftUI

extension ContainerValues {
    @Entry var pivotTitle: String = ""
}

extension View {
    func pivotTitle(_ title: String) -> some View {
        containerValue(\.pivotTitle, title)
    }
}

/// Paged content under a row of headers that slide with the swipe; the active header sits at the left.
struct Pivot<Content: View>: View {
    var overline: String?
    @Binding var selection: Int
    @ViewBuilder var content: Content

    @State private var progress: CGFloat = 0
    @State private var scrolledPage: Int?
    @State private var headerWidths: [Int: CGFloat] = [:]
    @Environment(\.metro) private var metro

    private static var headerSpacing: CGFloat { 24 }

    var body: some View {
        Group(subviews: content) { pages in
            VStack(alignment: .leading, spacing: 0) {
                if let overline {
                    Text(overline)
                        .font(.metroOverline)
                        .tracking(1.5)
                        .padding(.leading, MetroMetrics.margin + 4)
                        .metroFeather(row: 0)
                }

                headerStrip(titles: pages.map(\.containerValues.pivotTitle))
                    .metroFeather(row: 0)
                    .padding(.bottom, 8)

                GeometryReader { geo in
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 0) {
                            ForEach(pages.indices, id: \.self) { index in
                                pages[index]
                                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                                    .id(index)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $scrolledPage)
                    .scrollIndicators(.hidden)
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        geometry.contentOffset.x / max(geometry.containerSize.width, 1)
                    } action: { _, newValue in
                        progress = newValue
                    }
                }
            }
        }
        .foregroundStyle(metro.foreground)
        .background(metro.background)
        .onAppear { scrolledPage = selection }
        .onChange(of: scrolledPage) { _, page in
            if let page, page != selection { selection = page }
        }
        .onChange(of: selection) { _, page in
            guard page != scrolledPage else { return }
            withAnimation(MetroMotion.standard) { scrolledPage = page }
        }
    }

    private func headerStrip(titles: [String]) -> some View {
        // The titles repeat once so the row reads as a loop, like the original pivot.
        let looped = titles + titles
        // The row is far wider than the screen; drawing it in an overlay keeps it from widening the layout.
        return Text(" ")
            .font(.metroPivot)
            .hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                HStack(alignment: .firstTextBaseline, spacing: Self.headerSpacing) {
                    ForEach(looped.indices, id: \.self) { index in
                        let page = index % max(titles.count, 1)
                        Button {
                            selection = page
                        } label: {
                            Text(looped[index])
                                .font(.metroPivot)
                                .lineLimit(1)
                                .fixedSize()
                                .opacity(headerOpacity(index))
                        }
                        .buttonStyle(.plain)
                        .accessibilityHidden(index >= titles.count)
                        .accessibilityAddTraits(page == selection ? .isSelected : [])
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                            if index < titles.count { headerWidths[index] = width }
                        }
                    }
                }
                .fixedSize()
                .padding(.leading, MetroMetrics.margin + 4)
                .offset(x: -headerOffset(count: titles.count))
            }
            .clipped()
    }

    private func headerOpacity(_ index: Int) -> Double {
        let distance = abs(CGFloat(index) - progress)
        return 1 - 0.6 * min(distance, 1)
    }

    private func headerOffset(count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let clamped = min(max(progress, 0), CGFloat(count - 1))
        let lower = Int(clamped.rounded(.down))
        let upper = min(lower + 1, count - 1)
        let fraction = clamped - CGFloat(lower)
        return leadingEdge(of: lower) + (leadingEdge(of: upper) - leadingEdge(of: lower)) * fraction
    }

    private func leadingEdge(of index: Int) -> CGFloat {
        (0..<index).reduce(0) { $0 + (headerWidths[$1] ?? 0) + Self.headerSpacing }
    }
}
