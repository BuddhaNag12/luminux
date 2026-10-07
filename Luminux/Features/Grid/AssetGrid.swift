import Photos
import SwiftUI

@Observable
final class SelectionModel {
    var isActive = false
    var selectedIDs: Set<String> = []

    func toggle(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    func begin(with id: String? = nil) {
        selectedIDs = id.map { [$0] } ?? []
        withAnimation(MetroMotion.standard) { isActive = true }
    }

    /// Selects every id, or clears them all when every one is already selected.
    func toggleAll(_ ids: [String]) {
        if ids.allSatisfy(selectedIDs.contains) {
            selectedIDs.subtract(ids)
        } else {
            selectedIDs.formUnion(ids)
        }
    }

    func end() {
        withAnimation(MetroMotion.standard) { isActive = false }
        selectedIDs = []
    }

    @ObservationIgnored private var swipeBase: Set<String> = []
    @ObservationIgnored private var swipeAdds = true

    /// Like Photos, a swipe that starts on an unselected photo selects, and one that starts on a selected photo clears.
    func beginSwipe(on id: String) {
        swipeBase = selectedIDs
        swipeAdds = !selectedIDs.contains(id)
    }

    /// `ids` are the photos between where the swipe started and the finger; photos it has moved back off return to
    /// how they were before the swipe.
    func updateSwipe(covering ids: [String]) {
        selectedIDs = swipeAdds ? swipeBase.union(ids) : swipeBase.subtracting(ids)
    }

    var selectedAssets: [PHAsset] {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: Array(selectedIDs), options: nil)
        return result.objects(at: IndexSet(integersIn: 0..<result.count))
    }
}

/// Square photo grid, optionally grouped under month headers that open the jump list.
struct AssetGrid: View {
    let source: AssetSource
    var sections: [MonthSection]?
    var selection: SelectionModel
    var emptyMessage = "Nothing here yet."
    var onHeaderTap: (() -> Void)?
    @Binding var jumpTarget: String?

    @Environment(PhotoLibrary.self) private var library
    @Environment(Navigator.self) private var navigator
    @Environment(AppSettings.self) private var settings
    @Environment(\.metro) private var metro
    @Environment(\.displayScale) private var displayScale
    @State private var gridWidth: CGFloat = 360
    /// The tile a long press just selected, so the tap that ends the press doesn't toggle it straight back off.
    @State private var longPressedID: String?
    @State private var featherOrigin = FeatherRowOrigin()
    @State private var scrollPosition = ScrollPosition(idType: Int.self)
    @State private var tileFrames = TileFrames()
    @State private var metrics = GridScrollMetrics()
    @State private var pinchScale: CGFloat = 1
    @State private var pinchAnchor = UnitPoint.center
    /// Set while a pinch runs and just after, so lifting the fingers doesn't open the photo under them.
    @State private var isPinching = false
    @State private var swipe: SwipeState?

    private var columns: Int { settings.gridColumns }
    private var tileSide: CGFloat { (gridWidth - MetroMetrics.gutter * CGFloat(columns - 1)) / CGFloat(columns) }

    var body: some View {
        let assets = library.assets(in: source)
        let gridItems = Array(repeating: GridItem(.flexible(), spacing: MetroMetrics.gutter), count: columns)

        ScrollViewReader { proxy in
            ScrollView {
                if assets.count == 0 && library.isLoaded {
                    Text(emptyMessage)
                        .font(.metroBody)
                        .foregroundStyle(metro.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                        .metroFeather(row: 0)
                }

                LazyVGrid(columns: gridItems, alignment: .leading, spacing: MetroMetrics.gutter) {
                    if let sections {
                        let headerRows = Self.headerRows(for: sections, columns: columns)
                        ForEach(Array(sections.enumerated()), id: \.element.id) { position, section in
                            Section {
                                tiles(assets, range: section.range, firstRow: headerRows[position] + 1)
                            } header: {
                                header(section, assets: assets)
                                    .metroFeather(row: headerRows[position])
                            }
                        }
                    } else {
                        tiles(assets, range: 0..<assets.count, firstRow: 0)
                    }
                }
                .scrollTargetLayout()
                .coordinateSpace(.named(Self.gridSpace))
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
                .padding(.bottom, 24)
            }
            .scrollPosition($scrollPosition)
            .scrollIndicators(.hidden)
            .environment(\.featherRowOrigin, featherOrigin)
            .onScrollGeometryChange(for: ScrollGeometry.self) { $0 } action: { _, geometry in
                metrics.offsetY = geometry.contentOffset.y
                metrics.minOffsetY = -geometry.contentInsets.top
                metrics.maxOffsetY = max(geometry.contentSize.height + geometry.contentInsets.bottom - geometry.containerSize.height, metrics.minOffsetY)
                metrics.visibleTop = geometry.contentInsets.top
                metrics.visibleBottom = geometry.containerSize.height - geometry.contentInsets.bottom
                let row = Int(max(geometry.contentOffset.y + geometry.contentInsets.top, 0) / (tileSide + MetroMetrics.gutter))
                if featherOrigin.row != row { featherOrigin.row = row }
            }
            .scaleEffect(pinchScale, anchor: pinchAnchor)
            .simultaneousGesture(pinch(assets))
            .gesture(SwipeSelectRecognizer(isEnabled: selection.isActive && pinchScale == 1) { phase, start, location in
                swipeChanged(phase, start: start, location: location, assets: assets)
            })
            .sensoryFeedback(.selection, trigger: longPressedID) { _, new in new != nil }
            .sensoryFeedback(.selection, trigger: swipe?.current)
            .sensoryFeedback(.impact(weight: .light), trigger: columns)
            .onChange(of: jumpTarget) { _, target in
                guard let target else { return }
                proxy.scrollTo(target, anchor: .top)
                jumpTarget = nil
            }
            .onChange(of: columns) { tileFrames.removeAll() }
            .onChange(of: library.changeToken) { tileFrames.removeAll() }
        }
        .clipped()
        .padding(.horizontal, MetroMetrics.margin)
    }

    private static let gridSpace = "assetGrid"

    // MARK: Pinch to zoom

    private func pinch(_ assets: PHFetchResult<PHAsset>) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                isPinching = true
                pinchAnchor = value.startAnchor
                // Rubber-bands past the next level so the grid can't be stretched out of shape.
                pinchScale = min(max(value.magnification, 0.6), 1.6)
            }
            .onEnded { value in
                let next = GridZoom.columns(after: columns, magnification: value.magnification)
                // Keep the photo under the fingers in place across the change.
                let contentPoint = CGPoint(x: value.startLocation.x, y: value.startLocation.y + metrics.offsetY)
                let anchorIndex = tileFrames.index(at: contentPoint) ?? scrollPosition.viewID(type: Int.self)
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    isPinching = false
                }
                withAnimation(MetroMotion.standard) {
                    pinchScale = 1
                    guard next != columns else { return }
                    settings.gridColumns = next
                    if let anchorIndex {
                        scrollPosition.scrollTo(id: anchorIndex, anchor: UnitPoint(x: 0.5, y: value.startAnchor.y))
                    }
                }
            }
    }

    // MARK: Swipe to select

    private struct SwipeState: Equatable {
        let anchor: Int
        var current: Int
        /// The finger in the scroll view's coordinates; adding the scroll offset gives the spot in the grid.
        var location: CGPoint
    }

    private func swipeChanged(_ phase: SwipeSelectRecognizer.Phase, start: CGPoint, location: CGPoint, assets: PHFetchResult<PHAsset>) {
        switch phase {
        case .began:
            guard let anchor = tileFrames.index(at: CGPoint(x: start.x, y: start.y + metrics.offsetY)), anchor < assets.count else { return }
            selection.beginSwipe(on: assets.object(at: anchor).localIdentifier)
            swipe = SwipeState(anchor: anchor, current: anchor, location: location)
            extendSwipe(assets)
            Task { await autoScroll(assets) }
        case .changed:
            guard swipe != nil else { return }
            swipe?.location = location
            extendSwipe(assets)
        case .ended:
            swipe = nil
        }
    }

    /// Selects (or clears) everything from the photo the swipe started on to the one under the finger.
    private func extendSwipe(_ assets: PHFetchResult<PHAsset>) {
        guard var state = swipe else { return }
        let point = CGPoint(x: state.location.x, y: state.location.y + metrics.offsetY)
        if let index = tileFrames.index(at: point), index < assets.count {
            state.current = index
        }
        swipe = state
        let range = min(state.anchor, state.current)...max(state.anchor, state.current)
        let ids = assets.objects(at: IndexSet(integersIn: range)).map(\.localIdentifier)
        selection.updateSwipe(covering: ids)
    }

    /// Scrolls while the finger rests near the top or bottom edge, so a swipe can reach photos off screen.
    private func autoScroll(_ assets: PHFetchResult<PHAsset>) async {
        let zone: CGFloat = 72
        let maxStep: CGFloat = 18
        while let state = swipe {
            let y = state.location.y
            var step: CGFloat = 0
            if y < metrics.visibleTop + zone {
                step = -maxStep * min((metrics.visibleTop + zone - y) / zone, 1)
            } else if y > metrics.visibleBottom - zone {
                step = maxStep * min((y - (metrics.visibleBottom - zone)) / zone, 1)
            }
            if step != 0 {
                let target = min(max(metrics.offsetY + step, metrics.minOffsetY), metrics.maxOffsetY)
                if target != metrics.offsetY {
                    scrollPosition.scrollTo(y: target)
                    // The finger hasn't moved, but the photos under it have.
                    metrics.offsetY = target
                    extendSwipe(assets)
                }
            }
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    /// The stagger row of each month header; its photos take the rows after it.
    private static func headerRows(for sections: [MonthSection], columns: Int) -> [Int] {
        var rows: [Int] = []
        var next = 0
        for section in sections {
            rows.append(next)
            next += 1 + (section.count + columns - 1) / columns
        }
        return rows
    }

    private func tiles(_ assets: PHFetchResult<PHAsset>, range: Range<Int>, firstRow: Int) -> some View {
        ForEach(range.clamped(to: 0..<assets.count), id: \.self) { index in
            let asset = assets.object(at: index)
            let id = asset.localIdentifier
            Button {
                if isPinching {
                    return
                } else if longPressedID == id {
                    longPressedID = nil
                } else if selection.isActive {
                    selection.toggle(id)
                } else {
                    navigator.openViewer(source, at: id, index: index)
                }
            } label: {
                AssetThumbnail(asset: asset, pixelSide: tileSide * displayScale)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(alignment: .topTrailing) {
                        if selection.isActive {
                            SelectionBox(isSelected: selection.selectedIDs.contains(id))
                                .padding(6)
                                .transition(.opacity)
                        }
                    }
                    .overlay {
                        if selection.selectedIDs.contains(id) {
                            Rectangle().strokeBorder(metro.accentColor, lineWidth: 3)
                        }
                    }
            }
            .buttonStyle(TiltButtonStyle(touch: nil, size: .zero))
            .metroFeather(row: firstRow + (index - range.lowerBound) / columns, column: (index - range.lowerBound) % columns)
            // Measured outside the feather so its turn doesn't skew the frame; dropped off screen, where the grid
            // parks reused tiles at stale positions.
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.gridSpace)) } action: { tileFrames.set($0, for: index) }
            .onDisappear { tileFrames.remove(index) }
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                guard !selection.isActive else { return }
                longPressedID = id
                selection.begin(with: id)
            })
            .zoomSource(id: id)
            .accessibilityAddTraits(selection.selectedIDs.contains(id) ? .isSelected : [])
        }
    }

    private func header(_ section: MonthSection, assets: PHFetchResult<PHAsset>) -> some View {
        HStack(spacing: 0) {
            Button {
                onHeaderTap?()
            } label: {
                Text(section.title())
                    .font(.metro(20, .semilight))
                    .foregroundStyle(metro.accentColor)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(onHeaderTap == nil)
            .accessibilityAddTraits(.isHeader)
            .accessibilityHint(onHeaderTap == nil ? "" : "Shows all months")

            if selection.isActive {
                let ids = section.range.clamped(to: 0..<assets.count).map { assets.object(at: $0).localIdentifier }
                let selectedCount = ids.count { selection.selectedIDs.contains($0) }
                Button {
                    selection.toggleAll(ids)
                } label: {
                    SelectionBox(isSelected: selectedCount == ids.count, isMixed: selectedCount > 0 && selectedCount < ids.count)
                        .frame(width: 44, height: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
                .transition(.opacity)
                .accessibilityLabel(selectedCount == ids.count ? "Clear \(section.title())" : "Select all of \(section.title())")
            }
        }
        .id(section.id)
    }
}

struct SelectionBox: View {
    let isSelected: Bool
    /// Some but not all of a group is selected.
    var isMixed = false
    @Environment(\.metro) private var metro

    var body: some View {
        let isFilled = isSelected || isMixed
        Rectangle()
            .fill(isFilled ? metro.accentColor : .black.opacity(0.25))
            .strokeBorder(isFilled ? metro.accentColor : .white, lineWidth: 2)
            .frame(width: 24, height: 24)
            .overlay {
                if isFilled {
                    Image(systemName: isSelected ? "checkmark" : "minus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
    }
}

struct AssetThumbnail: View {
    let asset: PHAsset
    var pixelSide: CGFloat

    @State private var image: UIImage?
    @Environment(\.metro) private var metro

    var body: some View {
        metro.chrome
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            // Clipping doesn't limit hit testing; without this, an overflowing photo steals taps from its neighbours.
            .contentShape(Rectangle())
            .overlay(alignment: .bottomTrailing) {
                if asset.mediaType == .video {
                    Text(Duration.seconds(asset.duration).formatted(.time(pattern: .minuteSecond)))
                        .font(.metro(12, .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .background(.black.opacity(0.6))
                        .padding(4)
                }
            }
            .overlay(alignment: .topLeading) {
                if asset.mediaSubtypes.contains(.photoLive) {
                    Image(systemName: "livephoto")
                        .font(.system(size: 12, weight: .light))
                        .foregroundStyle(.white)
                        .padding(5)
                }
            }
            // Reloads at the new size when the grid zooms; the old image stays up until the sharper one arrives.
            .task(id: "\(asset.renderKey)-\(Int(pixelSide))") {
                let side = max(pixelSide, 60)
                for await next in ImageLoader.shared.images(for: asset, targetSize: CGSize(width: side, height: side)) {
                    image = next
                }
            }
            .accessibilityElement()
            .accessibilityLabel(asset.spokenDescription)
    }
}

extension PHAsset {
    /// Changes when the photo is edited, so image loads keyed on it refresh.
    var renderKey: String {
        "\(localIdentifier)-\(modificationDate?.timeIntervalSinceReferenceDate ?? 0)"
    }

    var spokenDescription: String {
        let kind = mediaType == .video ? "Video" : (mediaSubtypes.contains(.photoLive) ? "Live Photo" : "Photo")
        guard let creationDate else { return kind }
        return "\(kind), \(creationDate.formatted(date: .long, time: .shortened))"
    }
}
