import Photos
import SwiftUI

@Observable
final class SelectionModel {
    var isActive = false
    var selectedIDs: Set<String> = []
    /// Off while the grid is at its smallest photos (see `GridZoom.allowsSelection`); pages hide their select button.
    var isAllowed = true

    func toggle(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    func begin(with id: String? = nil) {
        guard isAllowed else { return }
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
    @Environment(ProStore.self) private var store
    @Environment(\.metro) private var metro
    @Environment(\.displayScale) private var displayScale
    /// A pinch without Pro springs back and says why.
    @State private var showsProNote = false
    @State private var gridWidth: CGFloat = 360
    /// The tile a long press just selected, so the tap that ends the press doesn't toggle it straight back off.
    @State private var touch = GridTouch()
    @State private var featherOrigin = FeatherRowOrigin()
    @State private var scrollPosition = ScrollPosition()
    @State private var metrics = GridScrollMetrics()
    /// Which stretch of the grid is drawn: a band a quarter of the screen tall, so scrolling redraws now and then
    /// rather than every frame.
    @State private var renderBand = 0
    @State private var viewportHeight: CGFloat = 800
    @State private var pinch = GridPinch()
    @State private var swipe: SwipeState?

    /// Grid sizes come with Pro; without it every grid stays at the default.
    private var columns: Int { store.unlocksPro ? settings.gridColumns : GridZoom.defaultColumns }
    private var tileSide: CGFloat { (gridWidth - MetroMetrics.gutter * CGFloat(columns - 1)) / CGFloat(columns) }

    /// The level a pinch works from: the grid's own until the pinch carries on to the next, which it then draws
    /// itself, so the grid underneath isn't laid out again until the pinch ends.
    private var base: Int { pinch.baseColumns }
    private var baseSide: CGFloat { GridZoom.tileSide(columns: base, width: gridWidth, gutter: MetroMetrics.gutter) }

    /// The smallest photos (15 columns) are an overview: plain thumbnails to find your place in, which a tap zooms into.
    private var isOverview: Bool { !GridZoom.allowsSelection(columns: columns) }

    private func layout(columns: Int) -> GridLayout {
        GridLayout(columns: columns, width: gridWidth, gutter: MetroMetrics.gutter, sections: sections?.map(\.range), count: library.assets(in: source).count)
    }

    /// The part of the grid drawn: the screen and a little either side, so a scroll's next rows are ready.
    private var renderedRect: CGRect {
        let band = viewportHeight / Self.bandsPerScreen
        return CGRect(x: 0, y: CGFloat(renderBand - 1) * band, width: gridWidth, height: viewportHeight + band * 3)
    }

    /// A sixth of the screen: small enough that little is drawn off screen (at 15 columns every extra row is 15
    /// photos), big enough that a fast scroll rebuilds now and then rather than every frame.
    private static let bandsPerScreen: CGFloat = 6

    var body: some View {
        let assets = library.assets(in: source)

        let layout = layout(columns: columns)

        ScrollView {
                if assets.count == 0 && library.isLoaded {
                    Text(emptyMessage)
                        .font(.metroBody)
                        .foregroundStyle(metro.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                        .metroFeather(row: 0)
                }

                // Drawn only where it's on screen, at worked-out places; see `GridLayout`.
                PlacedLayout(height: layout.height) {
                    let rendered = renderedRect
                    if let sections {
                        ForEach(layout.headers(in: rendered), id: \.position) { slot in
                            header(sections[slot.position], assets: assets)
                                .metroFeather(row: slot.row, hingeX: MetroMetrics.margin)
                                .placed(slot.frame)
                        }
                    }
                    // By row, each skipped when nothing about it changed: scrolling only builds the rows coming on.
                    ForEach(layout.rows(in: rendered), id: \.row) { slot in
                        GridRowView(
                            slot: slot, side: layout.side, gutter: layout.gutter, isOverview: isOverview, assets: assets, source: source,
                            selection: selection, pinch: pinch, touch: touch, zoomIn: { zoomIn(toIndex: $0) }
                        )
                        .equatable()
                            .placed(CGRect(x: 0, y: slot.y, width: CGFloat(slot.range.count) * layout.pitch, height: layout.side))
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
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
                metrics.viewportSize = geometry.containerSize
                featherOrigin.row = layout.row(atY: max(geometry.contentOffset.y + geometry.contentInsets.top, 0))
                featherOrigin.rows = Int((geometry.containerSize.height / layout.pitch).rounded(.up))
                if viewportHeight != geometry.containerSize.height { viewportHeight = geometry.containerSize.height }
                let band = Int((geometry.contentOffset.y / max(viewportHeight / Self.bandsPerScreen, 1)).rounded(.down))
                if band != renderBand { renderBand = band }
            }
            // The pinch moves the grid itself; the scroll view would otherwise pan it too.
            .scrollDisabled(pinch.isActive)
            .modifier(GridPinchTransform(pinch: pinch))
            .overlay {
                PinchTileLayer(pinch: pinch, assets: assets)
            }
            .gesture(GridPinchRecognizer { phase, scale, velocity, centroid in
                pinchChanged(phase, scale: scale, velocity: velocity, centroid: centroid)
            })
            .gesture(SwipeSelectRecognizer(isEnabled: selection.isActive && !pinch.isActive) { phase, start, location in
                swipeChanged(phase, start: start, location: location, assets: assets)
            })
            // At 15 columns the photos aren't buttons; a tap anywhere zooms in there.
            .simultaneousGesture(SpatialTapGesture().onEnded { value in
                if isOverview { zoomIn(at: value.location) }
            })
            // One long press for the whole grid rather than one per photo: UIKit sorts every recognizer on every touch.
            .gesture(GridLongPressRecognizer { location in
                guard !selection.isActive, !pinch.isActive,
                      let index = layout.index(at: CGPoint(x: location.x, y: location.y + metrics.offsetY)),
                      index < assets.count else { return }
                let id = assets.object(at: index).localIdentifier
                touch.longPressedID = id
                selection.begin(with: id)
            })
            .sensoryFeedback(.selection, trigger: touch.longPressedID) { _, new in new != nil }
            .sensoryFeedback(.selection, trigger: swipe?.current)
            // Once the grid has settled at its new level after the fingers lift, not at each level a pinch passes.
            .sensoryFeedback(.impact(weight: .light), trigger: pinch.settledLevels)
            .onChange(of: columns, initial: true) { _, columns in
                selection.isAllowed = GridZoom.allowsSelection(columns: columns)
                if !selection.isAllowed, selection.isActive { selection.end() }
            }
            .onChange(of: jumpTarget) { _, target in
                guard let target else { return }
                if let position = sections?.firstIndex(where: { $0.id == target }), let top = layout.headerTop(ofSectionAt: position) {
                    scrollPosition.scrollTo(y: min(max(top + metrics.minOffsetY, metrics.minOffsetY), metrics.maxOffsetY))
                }
                jumpTarget = nil
            }
            .clipped()
        .overlay(alignment: .top) {
            if showsProNote { proNote }
        }
        .task(id: showsProNote) {
            guard showsProNote else { return }
            try? await Task.sleep(for: .seconds(3))
            withAnimation(MetroMotion.fade) { showsProNote = false }
        }
        .padding(.horizontal, MetroMetrics.margin)
        .preference(key: GridPinchingKey.self, value: pinch.isActive)
    }

    private var proNote: some View {
        Button {
            showsProNote = false
            navigator.push(.pro)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill").font(.system(size: 14, weight: .light))
                Text("Grid sizes come with Luminux Pro. Tap to see what it adds.")
                    .font(.metro(15, .semilight))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.white)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(metro.accentColor)
            .contentShape(Rectangle())
        }
        .buttonStyle(TiltButtonStyle(touch: nil, size: .zero))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: Pinch to zoom
    //
    // One layer of photos, each drawn once. Once a pinch heads for the next level, the photos on screen take that
    // level's size but keep their old rows (unsorted), on the next level's cells with the photo under the fingers on
    // its own new cell. The cells they leave empty already show the next level's sorted photos, and come in from
    // beyond the edges as a camera pulls back with the pinch. Once it has pulled back about a third of the way, the
    // middle block changes into order on its own (and back, if the pinch turns back). Letting go after that switches
    // the grid to the next level underneath; before it, everything goes back.

    /// Photos' settle is gentle rather than snappy.
    private static let settleMotion = Animation.spring(response: 0.4, dampingFraction: 1)
    /// The camera's quick return when the pinch turns back before the next level.
    private static let resizeMotion = Animation.spring(response: 0.25, dampingFraction: 1)
    /// The middle block's change into order (or back), a dissolve with a fade, on its own clock.
    private static let sortMotion = Animation.easeInOut(duration: 0.5)
    private static let tapZoomMotion = Animation.easeInOut(duration: 0.6)
    /// How far the pinch goes toward the next level before the middle block changes into its order, and back.
    /// Zooming in, it starts almost at once, so it's done before the photos around leave the screen.
    private static func sortsAt(_ zoomsIn: Bool) -> CGFloat { zoomsIn ? 0.1 : 0.3 }
    private static func unsortsAt(_ zoomsIn: Bool) -> CGFloat { zoomsIn ? 0.05 : 0.22 }

    private func pinchChanged(_ phase: GridPinchRecognizer.Phase, scale: CGFloat, velocity: CGFloat, centroid: CGPoint) {
        let viewport = metrics.viewportSize
        pinch.lastScale = scale
        pinch.lastCentroid = centroid
        if phase == .began { pinch.isTracking = true }
        if phase == .ended { pinch.isTracking = false }
        // While the grid switches level mid-pinch, the pinch carries on from the new level once it's done.
        guard viewport.width > 0, viewport.height > 0, pinch.swap == nil else { return }
        switch phase {
        case .began:
            pinch.isActive = true
            pinch.baseColumns = columns
            pinch.baseOffset = metrics.offsetY
            // The recognizer starts after the fingers have already moved; measure from here so nothing jumps.
            pinch.startScale = max(scale, 0.01)
            pinch.gestureScale = 1
            pinch.limits = GridZoom.scaleLimits(for: base)
            pinch.anchorsOnSortedColumn = false
            setAnchor(at: centroid)
            // Zooming out shows photos that weren't on screen; start loading them before the preview needs them.
            if let index = pinch.anchorIndex, let wider = GridZoom.levels.first(where: { $0 > base }) {
                let side = GridZoom.tileSide(columns: wider, width: gridWidth, gutter: MetroMetrics.gutter)
                ImageLoader.shared.cache(nearby(index, columns: wider), side: AssetThumbnail.requestSide(for: side * displayScale))
            }
            applyPinch()
        case .changed:
            pinch.gestureScale = GridZoom.rubberBand(scale / pinch.startScale, limits: pinch.limits)
            applyPinch()
        case .ended:
            release(scale: scale, velocity: velocity)
        }
    }

    /// The photo at `point` on screen, and where in it the point is, so the next level can line it up.
    private func setAnchor(at point: CGPoint) {
        pinch.anchorPoint = point
        let contentPoint = CGPoint(x: point.x, y: point.y + pinch.baseOffset)
        let current = layout(columns: base)
        pinch.anchorIndex = current.index(nearest: contentPoint)
        let frame = pinch.anchorIndex.flatMap(current.frame(of:))
        if let frame {
            pinch.anchorUnit = CGPoint(x: (contentPoint.x - frame.minX) / frame.width, y: (contentPoint.y - frame.minY) / frame.height)
        }
        // Where that photo is on screen now, to line it up on its cell in the next level.
        pinch.anchorFrame = frame?.offsetBy(dx: 0, dy: -pinch.baseOffset)
    }

    /// Works out the next level and where it would be scrolled to, with the anchor photo under the same point.
    private func preparePreview(target: Int) -> Bool {
        guard let anchorIndex = pinch.anchorIndex else { return false }
        let next = layout(columns: target)
        guard let anchorNext = next.frame(of: anchorIndex) else { return false }
        // Scrolled so the photo under the fingers is under them there too, as far as the grid's ends allow.
        let rest = anchorNext.minY + pinch.anchorUnit.y * anchorNext.height - pinch.anchorPoint.y
        let insetBottom = metrics.viewportSize.height - metrics.visibleBottom
        let maxOffset = max(next.height + insetBottom - metrics.viewportSize.height, metrics.minOffsetY)
        pinch.previewLayout = next
        pinch.previewOffset = min(max(rest, metrics.minOffsetY), maxOffset)
        pinch.previewColumns = target
        // Each level the pinch heads to, not just the first: carried on to 15, its photos are new ones.
        ImageLoader.shared.cache(nearby(anchorIndex, columns: target), side: AssetThumbnail.requestSide(for: next.side * displayScale))
        return true
    }

    /// Tapping the overview: the camera pushes in on the photo tapped, the photos around it sort into the level it
    /// opens on, and the grid switches to that level, the photo still under the finger.
    private func zoomIn(at point: CGPoint) {
        guard !pinch.isActive, store.unlocksPro else { return }
        pinch.isActive = true
        pinch.isTracking = false
        pinch.baseColumns = columns
        pinch.baseOffset = metrics.offsetY
        // The tapped photo lands on its own column, not the middle of the screen, so it stays under the finger.
        pinch.anchorsOnSortedColumn = true
        setAnchor(at: point)
        guard preparePreview(target: GridZoom.overviewZoomColumns), let tiles = pinchTiles(target: GridZoom.overviewZoomColumns) else {
            pinch.previewColumns = nil
            pinch.previewLayout = nil
            pinch.isActive = false
            return
        }
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            pinch.progress = 0
            pinch.tiles = tiles
            pinch.stage = .unsorted
            pinch.hidesTiles = true
        }
        setSorting(true)
        // A little longer than the sort, so the photos have settled into order when the grid takes over.
        withAnimation(Self.tapZoomMotion) {
            pinch.progress = 1
        } completion: {
            switchGrid(to: GridZoom.overviewZoomColumns)
        }
    }

    private func zoomIn(toIndex index: Int) {
        guard let frame = layout(columns: columns).frame(of: index) else { return }
        zoomIn(at: CGPoint(x: frame.midX, y: frame.midY - metrics.offsetY))
    }

    /// Lays the next level out (hidden) once the pinch heads there and puts the photos on its cells unsorted.
    private func applyPinch() {
        let looksLike = CGFloat(base) / pinch.gestureScale
        guard store.unlocksPro, pinch.anchorIndex != nil, let target = GridZoom.level(toward: looksLike, from: base) else {
            // Carried on past the grid's own level, the tile layer is all there is to show; it stays.
            if !pinch.isRebased { restoreTiles() }
            return
        }
        let progress = GridZoom.progress(looksLike, from: base, to: target)
        if pinch.previewColumns != target {
            if pinch.isRebased {
                // Turned the other way: start toward that level at once; near the base level both look the same.
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) { resetTiles() }
                guard preparePreview(target: target) else { return }
            } else {
                restoreTiles()
                guard progress > 0.05, preparePreview(target: target) else { return }
            }
        }
        if pinch.tiles.isEmpty, !pinch.isRestoring, let tiles = pinchTiles(target: target) {
            var instant = Transaction()
            instant.disablesAnimations = true
            // Seen through the camera at the pinch's start, they look just as the grid did; nothing jumps.
            withTransaction(instant) {
                pinch.progress = progress
                pinch.tiles = tiles
                pinch.stage = .unsorted
                pinch.hidesTiles = true
            }
        }
        pinch.progress = progress
        // Once the camera has pulled back far enough for the photos around to show, the middle block changes into
        // order on its own; back short of that, it changes back. The gap between the two keeps it from flickering.
        let zoomsIn = target < base
        if !pinch.isSorting, progress >= Self.sortsAt(zoomsIn) {
            setSorting(true)
        } else if pinch.isSorting, progress < Self.unsortsAt(zoomsIn) {
            setSorting(false)
        }
        carryOn(looksLike: looksLike, target: target)
    }

    /// With the fingers still going past a level that has fully sorted, the pinch carries on toward the next one
    /// from there, so one pinch can go 3 → 5 → 15 without stopping. The grid underneath stays as it was until the
    /// fingers lift: laying it out again mid-pinch cost frames and showed it for one.
    private func carryOn(looksLike: CGFloat, target: Int) {
        guard pinch.isTracking, pinch.progress >= 1, pinch.swap == nil,
              let beyond = GridZoom.level(toward: looksLike, from: target), (beyond > target) == (target > base) else { return }
        var instant = Transaction()
        instant.disablesAnimations = true
        // Straight on, without waiting for this level's sort to finish: the camera never stops with the fingers.
        let carried = GridZoom.progress(looksLike, from: target, to: beyond)
        withTransaction(instant) {
            pinch.baseColumns = target
            pinch.baseOffset = pinch.previewOffset
            pinch.isRebased = target != columns
            resetTiles()
            // Measured from here on so the grid looks like as many columns as the fingers say, not where they were
            // when this level was reached.
            pinch.gestureScale = CGFloat(target) / looksLike
            pinch.startScale = pinch.lastScale / pinch.gestureScale
            pinch.limits = GridZoom.scaleLimits(for: target)
            pinch.anchorsOnSortedColumn = false
            setAnchor(at: pinch.lastCentroid)
            // At the new level's start the camera shows it exactly as the last one ended.
            if preparePreview(target: beyond), let tiles = pinchTiles(target: beyond) {
                pinch.progress = carried
                pinch.tiles = tiles
                pinch.stage = .unsorted
            }
        }
        applyPinch()
    }

    /// Empties the tile layer without showing the grid under it.
    private func resetTiles() {
        pinch.tiles = []
        pinch.stage = .unsorted
        pinch.sortedness = 0
        pinch.progress = 0
        pinch.isSorting = false
        pinch.isSorted = false
        pinch.isRestoring = false
    }

    private func setSorting(_ sorting: Bool) {
        pinch.isSorting = sorting
        pinch.isSorted = false
        withAnimation(Self.sortMotion) {
            pinch.sortedness = sorting ? 1 : 0
        } completion: {
            guard sorting, pinch.isSorting else { return }
            pinch.isSorted = true
            // The fingers may already be past the level, holding still.
            if let target = pinch.previewColumns {
                carryOn(looksLike: CGFloat(base) / pinch.gestureScale, target: target)
            }
        }
    }

    /// Sends the photos back to where they were and hands back to the grid.
    private func restoreTiles() {
        guard !pinch.tiles.isEmpty, !pinch.isRestoring else {
            if pinch.tiles.isEmpty { pinch.progress = 0 }
            return
        }
        pinch.isRestoring = true
        pinch.isSorting = false
        pinch.isSorted = false
        withAnimation(Self.resizeMotion) {
            pinch.progress = 0
            pinch.sortedness = 0
        } completion: {
            clearTiles()
        }
    }

    private func clearTiles() {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            pinch.hidesTiles = false
            pinch.tiles = []
            pinch.stage = .unsorted
            pinch.sortedness = 0
        }
        pinch.isSorting = false
        pinch.isSorted = false
        pinch.isRestoring = false
    }

    /// Every photo on screen now or after the pinch, with where it is, where it sits unsorted on the next level's
    /// cells, and where it lands sorted.
    private func pinchTiles(target: Int) -> [PinchTile]? {
        guard let anchorIndex = pinch.anchorIndex, let anchorOld = pinch.anchorFrame, let next = pinch.previewLayout,
              let anchorNew = next.frame(of: anchorIndex) else { return nil }
        let current = layout(columns: base)
        let previewOffset = pinch.previewOffset
        let assetCount = library.assets(in: source).count
        let viewport = metrics.viewportSize
        let gutter = next.gutter
        let side = GridZoom.tileSide(columns: target, width: gridWidth, gutter: gutter)
        let pitch = side + gutter
        let oldPitch = baseSide + gutter
        let anchorTop = anchorNew.minY - previewOffset
        let anchorColumn = Int((anchorNew.minX / pitch).rounded())
        let screen = CGRect(origin: .zero, size: viewport)

        /// Where a photo sits sorted, on screen.
        func sorted(_ index: Int) -> CGRect? {
            next.frame(of: index)?.offsetBy(dx: 0, dy: -previewOffset)
        }

        var tiles: [PinchTile] = []
        var shown = Set<Int>()
        var taken = Set<GridCell>()
        var spots: [Int: GridCell] = [:]
        // The photos on screen keep their rows, in place: the photo under the fingers on the cell nearest where it
        // is, the rest on the cells as far from it as they were.
        // Each level adds (or drops) the same number of columns on either side, so zooming is even both ways.
        let anchorUnsortedColumn = pinch.anchorsOnSortedColumn
            ? anchorColumn
            : Int((anchorOld.minX / oldPitch).rounded()) + (target - base) / 2
        // Each photo keeps its row in its own month, the month lined up with where it'll be: the one under the
        // fingers on that photo's row, those above on their last row, those below on their first. Counting rows
        // across a month title (hidden while pinching) put a month's first row in the next level's title space.
        guard let anchorPlace = current.placeInSection(of: anchorIndex), let anchorSortedPlace = next.placeInSection(of: anchorIndex),
              let anchorUnsorted = next.frame(inSectionOf: anchorIndex, row: anchorSortedPlace.row, column: anchorUnsortedColumn)?
                .offsetBy(dx: 0, dy: -previewOffset) else { return nil }
        let columnShift = anchorUnsortedColumn - anchorPlace.column
        func rowShift(_ index: Int) -> Int {
            if current.isSameSection(index, anchorIndex) { return anchorSortedPlace.row - anchorPlace.row }
            guard index < anchorIndex else { return 0 }
            return (next.rowCount(inSectionOf: index) ?? 0) - (current.rowCount(inSectionOf: index) ?? 0)
        }
        // The camera starts close enough that the next level's cells look the size the grid's are, with the photo
        // under the fingers where it is, and pulls back (or pushes in) to the next level as the pinch goes on.
        pinch.camera = PinchCamera(
            // Centres, since photos are drawn around their cells' centres.
            from: CGPoint(x: anchorOld.midX, y: anchorOld.midY),
            to: CGPoint(x: anchorUnsorted.midX, y: anchorUnsorted.midY),
            startScale: oldPitch / pitch,
            startSide: baseSide
        )
        for index in current.indices(in: screen.offsetBy(dx: 0, dy: pinch.baseOffset)) where index < assetCount {
            guard let now = current.frame(of: index)?.offsetBy(dx: 0, dy: -pinch.baseOffset),
                  let place = current.placeInSection(of: index) else { continue }
            let column = place.column + columnShift
            guard let unsorted = next.frame(inSectionOf: index, row: place.row + rowShift(index), column: column)?
                .offsetBy(dx: 0, dy: -previewOffset) else { continue }
            let spot = GridCell(row: Int(((unsorted.minY - anchorTop) / pitch).rounded()), column: column)
            guard taken.insert(spot).inserted else { continue }
            shown.insert(index)
            spots[index] = spot
            // Starts exactly where the camera's start shows it as it was, so the pinch begins without anything
            // moving, and settles onto its cell as the pinch goes on.
            let center = CGPoint(
                x: pinch.camera.to.x + (now.midX - pinch.camera.from.x) / pinch.camera.startScale,
                y: pinch.camera.to.y + (now.midY - pinch.camera.from.y) / pinch.camera.startScale
            )
            let start = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
            // The month under the fingers sorts as one block; others cross-fade to where they'll be as the camera
            // moves, since the widening about the fingers moves their sorted places.
            let kind: PinchTile.Kind = current.isSameSection(index, anchorIndex) ? .shown : .moving
            tiles.append(PinchTile(index: index, kind: kind, unsorted: unsorted, start: start))
        }

        // The cells around them are already sorted: each shows the photo the next level puts there, so letting go
        // only sorts the block the old photos sit in.
        // Zooming in, the camera starts further out than the next level's screen, so everything it sees then counts.
        let startOffset = pinch.camera.offset(at: 0)
        let seenAtStart = CGRect(
            x: -startOffset.width / pinch.camera.startScale, y: -startOffset.height / pinch.camera.startScale,
            width: viewport.width / pinch.camera.startScale, height: viewport.height / pinch.camera.startScale
        )
        let seen = screen.union(seenAtStart)
        let firstRow = Int(((seen.minY - anchorTop) / pitch).rounded(.down))
        let lastRow = Int(((seen.maxY - anchorTop) / pitch).rounded(.down))
        var sortedAt: [GridCell: Int] = [:]
        for index in next.indices(in: seen.offsetBy(dx: 0, dy: previewOffset)) {
            guard let frame = sorted(index) else { continue }
            sortedAt[GridCell(row: Int(((frame.minY - anchorTop) / pitch).rounded()), column: Int((frame.minX / pitch).rounded()))] = index
        }
        var fillers: [PinchTile] = []
        for row in firstRow...max(firstRow, lastRow) {
            for column in 0..<target where !taken.contains(GridCell(row: row, column: column)) {
                // Drawn where the next level puts it (month titles shift rows off the even pitch), so handing over to
                // the grid at the end moves nothing.
                guard let index = sortedAt[GridCell(row: row, column: column)], let slot = sorted(index) else { continue }
                // Already on screen in the old block: its sorted place shows it only once the block sorts, so it's
                // never drawn twice.
                if shown.contains(index) {
                    fillers.append(PinchTile(index: index, kind: current.isSameSection(index, anchorIndex) ? .sortedMiddle : .arriving, unsorted: slot))
                    continue
                }
                // Most come in from beyond the edges as the camera pulls back; one that starts already on screen,
                // where the grid had no photo (its month title), fades in instead of popping up.
                let center = CGPoint(
                    x: pinch.camera.from.x + (slot.midX - pinch.camera.to.x) * pinch.camera.startScale,
                    y: pinch.camera.from.y + (slot.midY - pinch.camera.to.y) * pinch.camera.startScale
                )
                let half = pinch.camera.startSide / 2
                let startsOnScreen = CGRect(x: center.x - half, y: center.y - half, width: half * 2, height: half * 2)
                    .insetBy(dx: 1, dy: 1).intersects(screen)
                fillers.append(PinchTile(index: index, kind: startsOnScreen ? .appearing : .filler, unsorted: slot))
            }
        }
        // Under the old photos, each middle cell's sorted photo, for the middle block's change into order.
        let underneath = taken.compactMap { spot in
            sortedAt[spot].flatMap { index in
                sorted(index).map { PinchTile(index: index, kind: current.isSameSection(index, anchorIndex) ? .sortedMiddle : .arriving, unsorted: $0) }
            }
        }
        // An old photo beyond the next level's columns has no sorted photo under it: it stays as it is until the
        // camera moves it off screen, rather than fading to nothing. Inside them it fades with the rest of its block.
        let old = tiles.map { tile in
            guard tile.kind == .shown, let spot = spots[tile.index], spot.column < 0 || spot.column >= target else { return tile }
            return PinchTile(index: tile.index, kind: .edge, unsorted: tile.unsorted, start: tile.start)
        }
        // Under the old photos, which cover them until they've shrunk out of the way.
        return fillers + underneath + old
    }

    private func release(scale: CGFloat, velocity: CGFloat) {
        // A quick flick carries on to where the pinch was heading, about a tenth of a second on.
        let projected = pinch.gestureScale * max(1 + velocity * 0.1 / max(scale, 0.01), 0.1)
        let looksLike = CGFloat(base) / projected
        let target = GridZoom.level(toward: looksLike, from: base)
        // Letting go once the middle block has changed into order keeps it; a flick toward the next level counts too.
        let commits = pinch.isSorting
            || (target.map { GridZoom.progress(looksLike, from: base, to: $0) >= Self.sortsAt($0 < base) } ?? false)
        if commits, !store.unlocksPro {
            withAnimation(MetroMotion.standard) { showsProNote = true }
        }
        if commits, let target, target == pinch.previewColumns, !pinch.tiles.isEmpty, !pinch.isRestoring {
            commit(to: target)
        } else {
            springBack()
        }
    }

    /// The camera finishes its move, then the grid switches to that level underneath, still hidden, at the same scroll
    /// position; once it's laid out on the same cells, each cell dissolves from its unsorted photo to its sorted one.
    private func commit(to target: Int) {
        // The camera finishes pulling back first, and the middle block its change into order.
        if !pinch.isSorting { setSorting(true) }
        withAnimation(Self.settleMotion) {
            pinch.progress = 1
        } completion: {
            switchGrid(to: target)
        }
    }

    private func switchGrid(to target: Int, offset: CGFloat? = nil) {
        let swap = GridPinch.Swap()
        pinch.swap = swap
        var instant = Transaction()
        instant.disablesAnimations = true
        // The same worked-out layout the transition used, so the grid comes up exactly under it.
        withTransaction(instant) {
            settings.gridColumns = target
            scrollPosition.scrollTo(y: offset ?? pinch.previewOffset)
        }
        let targetSide = GridZoom.tileSide(columns: target, width: gridWidth, gutter: MetroMetrics.gutter)
        ImageLoader.shared.cache(nearby(pinch.anchorIndex ?? 0, columns: target), side: AssetThumbnail.requestSide(for: targetSide * displayScale))
        // A couple of frames for the grid to draw at its new level before it takes over.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { finishSwap(swap.id) }
    }

    private func finishSwap(_ id: UUID) {
        guard pinch.swap?.id == id else { return }
        pinch.swap = nil
        // The grid under the photos is now laid out as they are, so it takes over in one frame: nothing on screen
        // changes once the transition has finished.
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { pinch.hidesTiles = false }
        DispatchQueue.main.async {
            withTransaction(instant) { pinch.progress = 0 }
            clearTiles()
            pinch.previewColumns = nil
            pinch.previewLayout = nil
            pinch.isRebased = false
            if pinch.isTracking {
                // Switched mid-pinch: start over from the new level, from where the fingers are now.
                pinchChanged(.began, scale: pinch.lastScale, velocity: 0, centroid: pinch.lastCentroid)
            } else {
                pinch.isActive = false
                pinch.settledLevels += 1
            }
        }
    }

    private func springBack() {
        pinch.isRestoring = !pinch.tiles.isEmpty
        pinch.isSorting = false
        pinch.isSorted = false
        withAnimation(Self.settleMotion) {
            pinch.progress = 0
            pinch.sortedness = 0
        } completion: {
            guard pinch.swap == nil else { return }
            // Carried on to another level before letting go: that's where the grid ends up.
            if pinch.isRebased {
                switchGrid(to: base, offset: pinch.baseOffset)
                return
            }
            clearTiles()
            pinch.previewColumns = nil
            pinch.previewLayout = nil
            pinch.isActive = false
        }
    }

    /// The photos a few screens around `index`, to have their thumbnails ready for a new level.
    private func nearby(_ index: Int, columns: Int) -> [PHAsset] {
        let assets = library.assets(in: source)
        let span = columns * 30
        let range = max(index - span, 0)..<min(index + span, assets.count)
        guard !range.isEmpty else { return [] }
        return assets.objects(at: IndexSet(integersIn: range))
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
            guard let anchor = layout(columns: columns).index(at: CGPoint(x: start.x, y: start.y + metrics.offsetY)), anchor < assets.count else { return }
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
        if let index = layout(columns: columns).index(at: point), index < assets.count {
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

    private func header(_ section: MonthSection, assets: PHFetchResult<PHAsset>) -> some View {
        HStack(spacing: 0) {
            Button {
                onHeaderTap?()
            } label: {
                MonthTitle(section: section)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // In the overview a tap anywhere zooms in, a month title's included, rather than opening the month list.
            .disabled(onHeaderTap == nil || isOverview)
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
    }
}

/// The photo a long press just selected, so the tap that ends the press doesn't toggle it straight back off.
@Observable
final class GridTouch {
    var longPressedID: String?
}

/// One row of a grid's photos. Equatable on what places it, so a scroll that rebuilds the grid's rows skips the ones
/// still on screen; what changes inside (selection, a pinch hiding the photos) it observes itself.
private struct GridRowView: View, Equatable {
    let slot: GridLayout.RowSlot
    let side: CGFloat
    let gutter: CGFloat
    let isOverview: Bool
    let assets: PHFetchResult<PHAsset>
    let source: AssetSource
    let selection: SelectionModel
    let pinch: GridPinch
    let touch: GridTouch
    let zoomIn: (Int) -> Void

    @Environment(Navigator.self) private var navigator
    @Environment(\.metro) private var metro
    @Environment(\.displayScale) private var displayScale

    nonisolated static func == (a: Self, b: Self) -> Bool {
        a.slot == b.slot && a.side == b.side && a.isOverview == b.isOverview && a.assets === b.assets
    }

    var body: some View {
        if isOverview {
            // Snapshots only: no buttons, badges or per-photo page turn, so hundreds of them draw cheaply. The row
            // turns as one, and is one element for VoiceOver.
            PlacedLayout(height: side) {
                ForEach(slot.range, id: \.self) { index in
                    AssetThumbnail(asset: assets.object(at: index), pixelSide: side * displayScale, isSnapshot: true)
                        .modifier(PinchHidesTile(pinch: pinch))
                        .placed(CGRect(x: CGFloat(index - slot.range.lowerBound) * (side + gutter), y: 0, width: side, height: side))
                }
            }
            .metroFeather(row: slot.row, hingeX: MetroMetrics.margin)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(slot.range.count) photos")
            .accessibilityHint("Zooms in on them")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { zoomIn(slot.range.lowerBound) }
        } else {
            PlacedLayout(height: side) {
                ForEach(slot.range, id: \.self) { index in
                    let column = index - slot.range.lowerBound
                    tile(index, column: column)
                        .placed(CGRect(x: CGFloat(column) * (side + gutter), y: 0, width: side, height: side))
                }
            }
        }
    }

    private func tile(_ index: Int, column: Int) -> some View {
        let asset = assets.object(at: index)
        let id = asset.localIdentifier
        return Button {
            if pinch.isActive {
                return
            } else if touch.longPressedID == id {
                touch.longPressedID = nil
            } else if selection.isActive {
                selection.toggle(id)
            } else {
                navigator.openViewer(source, at: id, index: index)
            }
        } label: {
            AssetThumbnail(asset: asset, pixelSide: side * displayScale)
                .frame(width: side, height: side)
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
        .metroFeather(row: slot.row, column: column, hingeX: MetroMetrics.margin + CGFloat(column) * (side + gutter))
        .modifier(PinchHidesTile(pinch: pinch))
        .zoomSource(id: id)
        .accessibilityAddTraits(selection.selectedIDs.contains(id) ? .isSelected : [])
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
    /// Just the picture: no badges and no description of its own (the overview's row describes them).
    var isSnapshot = false

    @State private var image: UIImage?
    @State private var loadedSide: CGFloat = 0
    @Environment(\.metro) private var metro
    @Environment(\.displayScale) private var displayScale

    init(asset: PHAsset, pixelSide: CGFloat, isSnapshot: Bool = false) {
        self.asset = asset
        self.pixelSide = pixelSide
        self.isSnapshot = isSnapshot
        // Any size already loaded beats a blank square while the right one loads.
        _image = State(initialValue: ImageLoader.shared.cachedThumbnail(for: asset))
    }

    /// Request sizes come in steps, so neighbouring zoom levels share one image instead of loading it twice.
    static func requestSide(for pixelSide: CGFloat) -> CGFloat {
        requestSides.first { $0 >= pixelSide } ?? pixelSide
    }

    static let requestSides: [CGFloat] = [72, 128, 256, 384, 512, 768, 1024, 1536]

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
            // Too small for a badge (the 15-column grid), it would cover the photo; VoiceOver still says what it is.
            .overlay(alignment: .bottomTrailing) {
                if asset.mediaType == .video, pixelSide / displayScale >= 60 {
                    Text(Duration.seconds(asset.duration).formatted(.time(pattern: .minuteSecond)))
                        .font(.metro(12, .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .background(.black.opacity(0.6))
                        .padding(4)
                }
            }
            .overlay(alignment: .topLeading) {
                if asset.mediaSubtypes.contains(.photoLive), pixelSide / displayScale >= 60 {
                    Image(systemName: "livephoto")
                        .font(.system(size: 12, weight: .light))
                        .foregroundStyle(.white)
                        .padding(5)
                }
            }
            // Reloads only when the grid zooms in past the loaded size; zooming out keeps the sharper image.
            .task(id: "\(asset.renderKey)-\(Int(max(Self.requestSide(for: pixelSide), loadedSide)))") {
                let side = max(Self.requestSide(for: pixelSide), loadedSide)
                loadedSide = side
                for await next in ImageLoader.shared.images(for: asset, targetSize: CGSize(width: side, height: side)) {
                    image = next
                    ImageLoader.shared.storeThumbnail(next, for: asset, side: side)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(isSnapshot ? "" : asset.spokenDescription)
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

/// The pinch's live transform. Observed only by `GridPinchTransform`, so a pinch frame redraws the transform and not
/// the grid's tiles.
@Observable
final class GridPinch {
    /// The grid's live transform, around its top-left corner.
    var scale: CGFloat = 1
    var offset: CGSize = .zero
    /// How far the pinch has gone toward the next level, 0...1: the preview of it shows as much.
    var progress: CGFloat = 0
    /// The level the pinch is heading to, laid out (hidden) under the grid to measure where its photos go.
    var previewColumns: Int?
    /// The photos drawn in the grid's place during a pinch, and which of their places they're at.
    var tiles: [PinchTile] = []
    var stage: PinchStage = .unsorted
    /// How far the middle block has changed into the next level's order, 0...1, on its own clock.
    var sortedness: CGFloat = 0
    /// The middle block is changing into order (or has), rather than back; and has finished doing so.
    @ObservationIgnored var isSorting = false
    @ObservationIgnored var isSorted = false
    /// The fingers are down, and where the recognizer last had them, to carry on after a level change mid-pinch.
    @ObservationIgnored var isTracking = false
    /// The level the pinch is working from and that level's scroll offset; see `AssetGrid.base`.
    @ObservationIgnored var baseColumns = GridZoom.defaultColumns
    @ObservationIgnored var baseOffset: CGFloat = 0
    /// A tap's zoom puts the anchor photo on its own column rather than the middle, so it stays under the finger.
    @ObservationIgnored var anchorsOnSortedColumn = false
    @ObservationIgnored var lastScale: CGFloat = 1
    @ObservationIgnored var lastCentroid: CGPoint = .zero
    /// How the pinch's photos are seen, from the grid as it was to the next level.
    @ObservationIgnored var camera = PinchCamera()
    /// The grid's own photos hide while the pinch's stand in for them.
    var hidesTiles = false
    /// From the first finger until the grid has settled; scrolling, taps and swipe-select wait for it.
    var isActive = false
    /// The pinch carried on past the grid's own level: the grid underneath is out of date until the fingers lift.
    var isRebased = false
    /// Counts the times a pinch has settled the grid at a new level.
    var settledLevels = 0

    @ObservationIgnored var limits: ClosedRange<CGFloat> = 1...1
    /// The recognizer's scale when the pinch began, and the pinch since then, rubber-banded past the next levels.
    @ObservationIgnored var startScale: CGFloat = 1
    @ObservationIgnored var gestureScale: CGFloat = 1
    @ObservationIgnored var anchorIndex: Int?
    /// Where in the anchor photo the fingers are, from its top-left corner (0...1 each way).
    @ObservationIgnored var anchorUnit = CGPoint(x: 0.5, y: 0.5)
    /// The anchor photo's frame on screen when the pinch began.
    @ObservationIgnored var anchorFrame: CGRect?
    /// The photos sent back to where they were, on their way.
    @ObservationIgnored var isRestoring = false
    /// Where the fingers started, in the grid's unscaled viewport: the point that stays under them.
    @ObservationIgnored var anchorPoint: CGPoint = .zero
    /// The level the pinch is heading to, worked out, and where it would be scrolled to.
    @ObservationIgnored var previewLayout: GridLayout?
    @ObservationIgnored var previewOffset: CGFloat = 0
    /// Set between switching the grid under a settled preview and the grid lining up with it.
    @ObservationIgnored var swap: Swap?

    struct Swap {
        let id = UUID()
    }
}

private struct GridPinchTransform: ViewModifier {
    let pinch: GridPinch

    func body(content: Content) -> some View {
        content
            .scaleEffect(pinch.scale, anchor: .topLeading)
            .offset(pinch.offset)
            // Its photos are the pinch's while it runs; its month titles hide until the pinch is done.
            .opacity(pinch.hidesTiles || pinch.isRebased ? 0 : 1)
    }
}

enum PinchStage {
    /// On the next level's cells, in their old rows; the cells around them show their sorted photos.
    case unsorted
    /// Handed over to the grid at the next level.
    case sorted
}

struct GridCell: Hashable {
    let row: Int
    let column: Int
}

/// A photo in the pinch's layer and its three places.
struct PinchTile: Identifiable {
    enum Kind {
        /// On screen before the pinch.
        case shown
        /// A cell the unsorted photos leave empty, showing its sorted photo, coming in from beyond the edges.
        case filler
        /// Like a filler, but in a spot already on screen when the pinch began.
        case appearing
        /// The sorted photo for a cell the old photos sit in, under them.
        case sortedMiddle
        /// On screen before the pinch, in a cell with no sorted photo: it stays until it's off screen.
        case edge
        /// On screen before the pinch in another month than the photo under the fingers: fades out as it's zoomed.
        case moving
        /// A sorted photo in another month than the photo under the fingers: fades in as it's zoomed.
        case arriving
    }

    let index: Int
    let kind: Kind
    let unsorted: CGRect
    /// Where it starts, if not on its cell: a photo that was on screen, exactly where it was.
    var start: CGRect?

    func frame(at progress: CGFloat) -> CGRect {
        guard let start else { return unsorted }
        let t = min(max(progress, 0), 1)
        return CGRect(
            x: start.minX + (unsorted.minX - start.minX) * t, y: start.minY + (unsorted.minY - start.minY) * t,
            width: unsorted.width, height: unsorted.height
        )
    }

    /// A photo can show twice for a moment: unsorted in the old block and sorted in a cell around it.
    var id: String { "\(kind == .edge || kind == .moving ? .shown : kind)-\(index)" }

    /// The photos around stay as they are (those appearing on screen fade in over the first part of the pinch);
    /// the middle block's old photos fade out over its sorted ones as `sortedness` goes to 1. Once the grid has
    /// switched, they all fade off it.
    func opacity(at stage: PinchStage, progress: CGFloat, sortedness: CGFloat) -> CGFloat {
        if stage == .sorted { return 0 }
        switch kind {
        case .shown: return 1 - sortedness
        // Solid under the old photo fading off it, so the two never dim the screen between them.
        case .sortedMiddle: return sortedness > 0 ? 1 : 0
        case .appearing: return min(progress * 3, 1)
        case .filler, .edge: return 1
        case .moving: return 1 - progress
        case .arriving: return progress
        }
    }
}

/// The view of the pinch's photos as a camera moving from the grid as it was (`progress` 0: the next level's cells
/// magnified to the grid's size, the photo under the fingers where it was) to the next level (`progress` 1: as laid
/// out). Pinching in, it pulls back and the photos around come in from beyond the edges; spreading, it pushes in.
struct PinchCamera {
    /// The photo under the fingers: where it was, and its cell on the next level.
    var from: CGPoint = .zero
    var to: CGPoint = .zero
    var startScale: CGFloat = 1
    /// The photos' size on screen when the pinch began.
    var startSide: CGFloat = 0

    /// The size to draw a photo whose cell is `side`, so the gaps between photos stay the grid's gutter on screen
    /// rather than growing with the camera.
    func drawnSide(_ side: CGFloat, at progress: CGFloat) -> CGFloat {
        (startSide + (side - startSide) * progress) / scale(at: progress)
    }

    func scale(at progress: CGFloat) -> CGFloat {
        startScale + (1 - startScale) * progress
    }

    /// Draws `to` at the point between `from` and `to`, for a layer scaled around its top-left corner.
    func offset(at progress: CGFloat) -> CGSize {
        let scale = scale(at: progress)
        let x = from.x + (to.x - from.x) * progress
        let y = from.y + (to.y - from.y) * progress
        return CGSize(width: x - to.x * scale, height: y - to.y * scale)
    }
}

/// The photos during a pinch, each drawn once, at the place the stage puts them.
private struct PinchTileLayer: View {
    let pinch: GridPinch
    let assets: PHFetchResult<PHAsset>
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let camera = pinch.camera
        let scale = camera.scale(at: pinch.progress)
        ZStack(alignment: .topLeading) {
            let side = camera.drawnSide(pinch.tiles.first?.unsorted.width ?? 0, at: pinch.progress)
            ForEach(pinch.tiles) { tile in
                let frame = tile.frame(at: pinch.progress)
                AssetThumbnail(asset: assets.object(at: tile.index), pixelSide: frame.width * max(camera.startScale, 1) * displayScale)
                    .frame(width: side, height: side)
                    .offset(x: frame.midX - side / 2, y: frame.midY - side / 2)
                    .opacity(tile.opacity(at: pinch.stage, progress: pinch.progress, sortedness: pinch.sortedness))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .scaleEffect(scale, anchor: .topLeading)
        .offset(camera.offset(at: pinch.progress))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Hides a grid photo while the pinch's layer stands in for it.
private struct PinchHidesTile: ViewModifier {
    let pinch: GridPinch

    func body(content: Content) -> some View {
        content.opacity(pinch.hidesTiles ? 0 : 1)
    }
}

/// A month's name over its photos.
private struct MonthTitle: View {
    let section: MonthSection
    @Environment(\.metro) private var metro

    var body: some View {
        Text(section.title())
            .font(.metro(20, .semilight))
            .foregroundStyle(metro.accentColor)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}
