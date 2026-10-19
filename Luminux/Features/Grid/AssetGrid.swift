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
    @Environment(ProStore.self) private var store
    @Environment(\.metro) private var metro
    @Environment(\.displayScale) private var displayScale
    /// A pinch without Pro springs back and says why.
    @State private var showsProNote = false
    @State private var gridWidth: CGFloat = 360
    /// The tile a long press just selected, so the tap that ends the press doesn't toggle it straight back off.
    @State private var longPressedID: String?
    @State private var featherOrigin = FeatherRowOrigin()
    @State private var scrollPosition = ScrollPosition(idType: Int.self)
    @State private var tileFrames = TileFrames()
    @State private var metrics = GridScrollMetrics()
    @State private var pinch = GridPinch()
    @State private var swipe: SwipeState?

    /// Grid sizes come with Pro; without it every grid stays at the default.
    private var columns: Int { store.unlocksPro ? settings.gridColumns : GridZoom.defaultColumns }
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
                                    .metroFeather(row: headerRows[position], hingeX: MetroMetrics.margin)
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
                metrics.viewportSize = geometry.containerSize
                let rowHeight = tileSide + MetroMetrics.gutter
                featherOrigin.row = Int(max(geometry.contentOffset.y + geometry.contentInsets.top, 0) / rowHeight)
                featherOrigin.rows = Int((geometry.containerSize.height / rowHeight).rounded(.up))
                if pinch.swap != nil {
                    pinch.swap?.hasNewLayout = true
                    alignSwap()
                }
            }
            // The pinch moves the grid itself; the scroll view would otherwise pan it too.
            .scrollDisabled(pinch.isActive)
            .modifier(GridPinchTransform(pinch: pinch))
            .background {
                PinchPreviewLayer(pinch: pinch, assets: assets, sections: sections, gridWidth: gridWidth)
            }
            .overlay {
                PinchTileLayer(pinch: pinch, assets: assets)
            }
            .gesture(GridPinchRecognizer { phase, scale, velocity, centroid in
                pinchChanged(phase, scale: scale, velocity: velocity, centroid: centroid)
            })
            .gesture(SwipeSelectRecognizer(isEnabled: selection.isActive && !pinch.isActive) { phase, start, location in
                swipeChanged(phase, start: start, location: location, assets: assets)
            })
            // One long press for the whole grid rather than one per photo: UIKit sorts every recognizer on every touch.
            .gesture(GridLongPressRecognizer { location in
                guard !selection.isActive, !pinch.isActive,
                      let index = tileFrames.index(at: CGPoint(x: location.x, y: location.y + metrics.offsetY), columns: columns),
                      index < assets.count else { return }
                let id = assets.object(at: index).localIdentifier
                longPressedID = id
                selection.begin(with: id)
            })
            .sensoryFeedback(.selection, trigger: longPressedID) { _, new in new != nil }
            .sensoryFeedback(.selection, trigger: swipe?.current)
            .sensoryFeedback(.impact(weight: .light), trigger: columns)
            .onChange(of: jumpTarget) { _, target in
                guard let target else { return }
                proxy.scrollTo(target, anchor: .top)
                jumpTarget = nil
            }
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

    private static let gridSpace = "assetGrid"

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
            // The recognizer starts after the fingers have already moved; measure from here so nothing jumps.
            pinch.startScale = max(scale, 0.01)
            pinch.gestureScale = 1
            pinch.limits = GridZoom.scaleLimits(for: columns)
            pinch.anchorPoint = centroid
            pinch.onPreviewMeasured = { applyPinch() }
            // The photo between the fingers, and where in it they are, so the preview can line it up.
            let contentPoint = CGPoint(x: centroid.x, y: centroid.y + metrics.offsetY)
            // Nearest, not containing: the fingers often sit on a gutter or a month header.
            pinch.anchorIndex = tileFrames.index(nearest: contentPoint, columns: columns, within: CGRect(origin: CGPoint(x: 0, y: metrics.offsetY), size: viewport))
            if let index = pinch.anchorIndex, let frame = tileFrames.frame(of: index, columns: columns), frame.width > 0 {
                pinch.anchorUnit = CGPoint(x: (contentPoint.x - frame.minX) / frame.width, y: (contentPoint.y - frame.minY) / frame.height)
            } else {
                pinch.anchorIndex = scrollPosition.viewID(type: Int.self)
                pinch.anchorUnit = CGPoint(x: 0.5, y: 0.5)
            }
            // Where that photo is on screen now, to line it up on its cell in the next level.
            pinch.anchorFrame = pinch.anchorIndex.flatMap { tileFrames.frame(of: $0, columns: columns) }
                .map { $0.offsetBy(dx: 0, dy: -metrics.offsetY) }
            // Zooming out shows photos that weren't on screen; start loading them before the preview needs them.
            if let index = pinch.anchorIndex, let wider = GridZoom.levels.first(where: { $0 > columns }) {
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

    /// Lays the next level out (hidden) once the pinch heads there and puts the photos on its cells unsorted.
    private func applyPinch() {
        let looksLike = CGFloat(columns) / pinch.gestureScale
        guard store.unlocksPro, pinch.anchorIndex != nil, let target = GridZoom.level(toward: looksLike, from: columns) else {
            restoreTiles()
            return
        }
        let progress = GridZoom.progress(looksLike, from: columns, to: target)
        if pinch.previewColumns != target {
            // Laying the next level out costs a frame or two of work; wait until the pinch is heading there.
            restoreTiles()
            guard progress > 0.05 else { return }
            pinch.preview = GridPinch.PreviewLayout()
            pinch.previewColumns = target
        }
        guard pinch.preview.isReady else { return }
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
        let zoomsIn = target < columns
        if !pinch.isSorting, progress >= Self.sortsAt(zoomsIn) {
            setSorting(true)
        } else if pinch.isSorting, progress < Self.unsortsAt(zoomsIn) {
            setSorting(false)
        }
        carryOn(looksLike: looksLike, target: target)
    }

    /// With the fingers still going past a level that has fully sorted, the grid switches to it underneath and the
    /// pinch carries on toward the next one, so one pinch can go 3 → 5 → 15 without stopping.
    private func carryOn(looksLike: CGFloat, target: Int) {
        guard pinch.isTracking, pinch.isSorted, pinch.progress >= 1, pinch.swap == nil,
              let beyond = GridZoom.level(toward: looksLike, from: target), (beyond > target) == (target > columns) else { return }
        switchGrid(to: target)
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
                carryOn(looksLike: CGFloat(columns) / pinch.gestureScale, target: target)
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
        guard let anchorIndex = pinch.anchorIndex, let anchorOld = pinch.anchorFrame,
              let anchorNew = pinch.preview.frames[anchorIndex] else { return nil }
        let assetCount = library.assets(in: source).count
        let viewport = metrics.viewportSize
        let gutter = MetroMetrics.gutter
        let side = GridZoom.tileSide(columns: target, width: gridWidth, gutter: gutter)
        let pitch = side + gutter
        let oldPitch = tileSide + gutter
        let anchorTop = anchorNew.minY - pinch.preview.offsetY
        let anchorColumn = Int((anchorNew.minX / pitch).rounded())
        let screen = CGRect(origin: .zero, size: viewport)

        func cell(_ row: Int, _ column: Int) -> CGRect {
            CGRect(x: CGFloat(column) * pitch, y: anchorTop + CGFloat(row) * pitch, width: side, height: side)
        }
        /// Where a photo sits sorted: as the hidden layout measured it, or counted on from the photo under the fingers.
        func sorted(_ index: Int) -> CGRect {
            if let frame = pinch.preview.frames[index] { return frame.offsetBy(dx: 0, dy: -pinch.preview.offsetY) }
            let linear = anchorColumn + index - anchorIndex
            let row = Int((Double(linear) / Double(target)).rounded(.down))
            return cell(row, linear - row * target)
        }

        var tiles: [PinchTile] = []
        var shown = Set<Int>()
        var taken = Set<GridCell>()
        var spots: [Int: GridCell] = [:]
        // The photos on screen keep their rows, in place: the photo under the fingers on the cell nearest where it
        // is, the rest on the cells as far from it as they were.
        // Each level adds (or drops) the same number of columns on either side, so zooming is even both ways.
        let anchorUnsortedColumn = Int((anchorOld.minX / oldPitch).rounded()) + (target - columns) / 2
        let anchorUnsortedRow = Int(((anchorOld.minY - anchorTop) / pitch).rounded())
        // The camera starts close enough that the next level's cells look the size the grid's are, with the photo
        // under the fingers where it is, and pulls back (or pushes in) to the next level as the pinch goes on.
        pinch.camera = PinchCamera(
            // Centres, since photos are drawn around their cells' centres.
            from: CGPoint(x: anchorOld.midX, y: anchorOld.midY),
            to: CGPoint(x: cell(anchorUnsortedRow, anchorUnsortedColumn).midX, y: cell(anchorUnsortedRow, anchorUnsortedColumn).midY),
            startScale: oldPitch / pitch,
            startSide: tileSide
        )
        for (index, frame) in tileFrames.frames(columns: columns) where index < assetCount {
            let now = frame.offsetBy(dx: 0, dy: -metrics.offsetY)
            guard now.intersects(screen) else { continue }
            let column = anchorUnsortedColumn + Int(((now.minX - anchorOld.minX) / oldPitch).rounded())
            let row = anchorUnsortedRow + Int(((now.minY - anchorOld.minY) / oldPitch).rounded())
            guard taken.insert(GridCell(row: row, column: column)).inserted else { continue }
            shown.insert(index)
            spots[index] = GridCell(row: row, column: column)
            tiles.append(PinchTile(index: index, kind: .shown, unsorted: cell(row, column)))
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
        let firstLinear = firstRow * target - anchorColumn
        let lastLinear = (lastRow + 1) * target - anchorColumn
        var sortedAt: [GridCell: Int] = [:]
        for index in (anchorIndex + firstLinear - target..<anchorIndex + lastLinear + target).clamped(to: 0..<assetCount) {
            let frame = sorted(index)
            guard frame.intersects(seen) else { continue }
            sortedAt[GridCell(row: Int(((frame.minY - anchorTop) / pitch).rounded()), column: Int((frame.minX / pitch).rounded()))] = index
        }
        var fillers: [PinchTile] = []
        for row in firstRow...max(firstRow, lastRow) {
            for column in 0..<target where !taken.contains(GridCell(row: row, column: column)) {
                guard let index = sortedAt[GridCell(row: row, column: column)] else { continue }
                let slot = cell(row, column)
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
            sortedAt[spot].map { PinchTile(index: $0, kind: .sortedMiddle, unsorted: cell(spot.row, spot.column)) }
        }
        // An old photo with no sorted one under it (beyond the next level's columns) stays as it is until the camera
        // moves it off screen, rather than fading to nothing.
        let old = tiles.map { tile in
            spots[tile.index].flatMap { sortedAt[$0] } == nil
                ? PinchTile(index: tile.index, kind: .edge, unsorted: tile.unsorted)
                : tile
        }
        // Under the old photos, which cover them until they've shrunk out of the way.
        return fillers + underneath + old
    }

    private func release(scale: CGFloat, velocity: CGFloat) {
        // The fingers are up: the preview re-measuring itself from here on mustn't re-apply the pinch.
        pinch.onPreviewMeasured = nil
        // A quick flick carries on to where the pinch was heading, about a tenth of a second on.
        let projected = pinch.gestureScale * max(1 + velocity * 0.1 / max(scale, 0.01), 0.1)
        let looksLike = CGFloat(columns) / projected
        let target = GridZoom.level(toward: looksLike, from: columns)
        // Letting go once the middle block has changed into order keeps it; a flick toward the next level counts too.
        let commits = pinch.isSorting
            || (target.map { GridZoom.progress(looksLike, from: columns, to: $0) >= Self.sortsAt($0 < columns) } ?? false)
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

    private func switchGrid(to target: Int) {
        let swap = GridPinch.Swap()
        pinch.swap = swap
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            settings.gridColumns = target
            scrollPosition.scrollTo(y: pinch.preview.offsetY)
        }
        ImageLoader.shared.cache(nearby(pinch.anchorIndex ?? 0, columns: target), side: AssetThumbnail.requestSide(for: tileSide * displayScale))
        // Carry on anyway if the measurement never comes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { finishSwap(swap.id, force: true) }
    }

    /// Once the switched grid is laid out, lines its photos up with the preview's. The lazy grid only knows where a
    /// photo really is after laying it out, which can take a pass or two after the jump, so this aims at the photo's
    /// measured position each time it's reported until the two agree.
    private func alignSwap() {
        guard let swap = pinch.swap, swap.hasNewLayout, let index = pinch.anchorIndex,
              let target = swapScrollTarget(index) else { return }
        if abs(target - metrics.offsetY) > 0.5, swap.corrections < 6 {
            pinch.swap?.corrections += 1
            pinch.swap?.isDone = false
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { scrollPosition.scrollTo(y: target) }
            return
        }
        guard !swap.isDone else { return }
        pinch.swap?.isDone = true
        // After the rest of this layout pass, so the grid shows where it finally lands.
        DispatchQueue.main.async { finishSwap(swap.id) }
    }

    /// The grid's scroll offset that puts the photo at `index` where the preview shows it.
    private func swapScrollTarget(_ index: Int) -> CGFloat? {
        guard let frame = tileFrames.frame(of: index, columns: columns), let previewFrame = pinch.preview.anchorFrame else { return nil }
        let target = frame.minY - (previewFrame.minY - pinch.preview.offsetY)
        return min(max(target, metrics.minOffsetY), metrics.maxOffsetY)
    }

    private func finishSwap(_ id: UUID, force: Bool = false) {
        guard let swap = pinch.swap, swap.id == id else { return }
        // A later layout pass moved the photo again; the next measurement finishes the job.
        if !force, swap.corrections < 6, let index = pinch.anchorIndex, let target = swapScrollTarget(index),
           abs(target - metrics.offsetY) > 0.5 { return }
        pinch.swap = nil
        // The grid under the photos is now laid out exactly as they are, so it takes over in one frame: nothing on
        // screen changes once the transition has finished.
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { pinch.hidesTiles = false }
        DispatchQueue.main.async {
            withTransaction(instant) { pinch.progress = 0 }
            clearTiles()
            pinch.previewColumns = nil
            if pinch.isTracking {
                // Switched mid-pinch: start over from the new level, from where the fingers are now.
                pinchChanged(.began, scale: pinch.lastScale, velocity: 0, centroid: pinch.lastCentroid)
            } else {
                pinch.isActive = false
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
            clearTiles()
            pinch.previewColumns = nil
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
            guard let anchor = tileFrames.index(at: CGPoint(x: start.x, y: start.y + metrics.offsetY), columns: columns), anchor < assets.count else { return }
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
        if let index = tileFrames.index(at: point, columns: columns), index < assets.count {
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
                if pinch.isActive {
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
            .metroFeather(
                row: firstRow + (index - range.lowerBound) / columns,
                column: (index - range.lowerBound) % columns,
                hingeX: MetroMetrics.margin + CGFloat((index - range.lowerBound) % columns) * (tileSide + MetroMetrics.gutter)
            )
            // Measured outside the feather so its turn doesn't skew the frame.
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.gridSpace)) } action: { frame in
                tileFrames.set(frame, for: index, columns: columns)
                if pinch.swap != nil, index == pinch.anchorIndex { alignSwap() }
            }
            .modifier(PinchHidesTile(pinch: pinch))
            .zoomSource(id: id)
            .accessibilityAddTraits(selection.selectedIDs.contains(id) ? .isSelected : [])
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
    @State private var loadedSide: CGFloat = 0
    @Environment(\.metro) private var metro

    init(asset: PHAsset, pixelSide: CGFloat) {
        self.asset = asset
        self.pixelSide = pixelSide
        // Any size already loaded beats a blank square while the right one loads.
        let side = Self.requestSide(for: pixelSide)
        _image = State(initialValue: ([side] + Self.requestSides.reversed()).lazy
            .compactMap { ImageLoader.shared.cachedThumbnail(for: asset, side: $0) }.first)
    }

    /// Request sizes come in steps, so neighbouring zoom levels share one image instead of loading it twice.
    static func requestSide(for pixelSide: CGFloat) -> CGFloat {
        requestSides.first { $0 >= pixelSide } ?? pixelSide
    }

    static let requestSides: [CGFloat] = [128, 256, 384, 512, 768, 1024, 1536]

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
    @ObservationIgnored var lastScale: CGFloat = 1
    @ObservationIgnored var lastCentroid: CGPoint = .zero
    /// How the pinch's photos are seen, from the grid as it was to the next level.
    @ObservationIgnored var camera = PinchCamera()
    /// The grid's own photos hide while the pinch's stand in for them.
    var hidesTiles = false
    /// From the first finger until the grid has settled; scrolling, taps and swipe-select wait for it.
    var isActive = false

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
    @ObservationIgnored var preview = PreviewLayout()
    @ObservationIgnored var onPreviewMeasured: (() -> Void)?
    /// Set between switching the grid under a settled preview and the grid lining up with it.
    @ObservationIgnored var swap: Swap?

    /// Where the preview has laid out the photo under the fingers, and its scroll position.
    struct PreviewLayout {
        var anchorFrame: CGRect?
        /// Every photo it has laid out, in its own coordinates.
        var frames: [Int: CGRect] = [:]
        var offsetY: CGFloat = 0
        var minOffsetY: CGFloat = 0
        var maxOffsetY: CGFloat = 0
        var hasScrolled = false
        /// Scrolled to put the photo where it rests under the fingers, and measured there.
        var isReady = false
    }

    struct Swap {
        let id = UUID()
        var hasNewLayout = false
        var corrections = 0
        var isDone = false
    }
}

private struct GridPinchTransform: ViewModifier {
    let pinch: GridPinch

    func body(content: Content) -> some View {
        content
            .scaleEffect(pinch.scale, anchor: .topLeading)
            .offset(pinch.offset)
            // While its photos hide, only its month titles show, giving way to the next level's.
            .opacity(pinch.hidesTiles ? 1 - pinch.progress : 1)
    }
}

/// The level a pinch is heading to, in place under the grid.
private struct PinchPreviewLayer: View {
    let pinch: GridPinch
    let assets: PHFetchResult<PHAsset>
    let sections: [MonthSection]?
    let gridWidth: CGFloat

    var body: some View {
        if let columns = pinch.previewColumns {
            // Only its month titles show, fading in as the grid's fade out; its photos are the tile layer's.
            PinchPreview(pinch: pinch, columns: columns, assets: assets, sections: sections, gridWidth: gridWidth)
                .id(columns)
                .opacity(pinch.progress)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// The grid laid out at another level, without its controls: what a pinch's preview draws.
private struct PinchPreview: View {
    let pinch: GridPinch
    let columns: Int
    let assets: PHFetchResult<PHAsset>
    let sections: [MonthSection]?
    let gridWidth: CGFloat

    @Environment(\.displayScale) private var displayScale
    @State private var scrollPosition = ScrollPosition(idType: Int.self)

    private static let space = "pinchPreview"
    private var side: CGFloat { GridZoom.tileSide(columns: columns, width: gridWidth, gutter: MetroMetrics.gutter) }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: MetroMetrics.gutter), count: columns), alignment: .leading, spacing: MetroMetrics.gutter) {
                if let sections {
                    ForEach(sections, id: \.id) { section in
                        Section {
                            tiles(section.range)
                        } header: {
                            MonthTitle(section: section)
                        }
                    }
                } else {
                    tiles(0..<assets.count)
                }
            }
            .scrollTargetLayout()
            .coordinateSpace(.named(Self.space))
            .padding(.bottom, 24)
        }
        .scrollPosition($scrollPosition)
        .scrollIndicators(.hidden)
        .scrollDisabled(true)
        .onScrollGeometryChange(for: ScrollGeometry.self) { $0 } action: { _, geometry in
            pinch.preview.offsetY = geometry.contentOffset.y
            pinch.preview.minOffsetY = -geometry.contentInsets.top
            pinch.preview.maxOffsetY = max(geometry.contentSize.height + geometry.contentInsets.bottom - geometry.containerSize.height, pinch.preview.minOffsetY)
            if pinch.preview.hasScrolled { pinch.preview.isReady = true }
            measured()
        }
        .onAppear {
            if let index = pinch.anchorIndex { scrollPosition.scrollTo(id: index, anchor: .center) }
        }
    }

    private func tiles(_ range: Range<Int>) -> some View {
        ForEach(range.clamped(to: 0..<assets.count), id: \.self) { index in
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { frame in
                    pinch.preview.frames[index] = frame
                    guard index == pinch.anchorIndex else { return }
                    pinch.preview.anchorFrame = frame
                    measured()
                }
        }
    }

    /// Once the photo under the fingers is laid out, scrolls it to where it'll rest under them, then reports.
    private func measured() {
        guard let frame = pinch.preview.anchorFrame else { return }
        if !pinch.preview.hasScrolled {
            pinch.preview.hasScrolled = true
            let rest = frame.minY + pinch.anchorUnit.y * frame.height - pinch.anchorPoint.y
            let target = min(max(rest, pinch.preview.minOffsetY), pinch.preview.maxOffsetY)
            if abs(target - pinch.preview.offsetY) > 0.5 {
                scrollPosition.scrollTo(y: target)
                return
            }
            pinch.preview.isReady = true
        }
        pinch.onPreviewMeasured?()
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
    }

    let index: Int
    let kind: Kind
    let unsorted: CGRect

    /// A photo can show twice for a moment: unsorted in the old block and sorted in a cell around it.
    var id: String { "\(kind == .edge ? .shown : kind)-\(index)" }

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
                let frame = tile.unsorted
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
