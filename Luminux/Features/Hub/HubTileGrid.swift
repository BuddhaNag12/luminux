import SwiftUI
import UIKit

/// The collection panel's tiles. Press and hold one to customise the panel, like the Windows Phone start screen:
/// drag tiles to move them, and use the buttons on the chosen tile to unpin or resize it.
struct HubTileGrid: View {
    @Binding var isEditing: Bool
    /// The tile showing its unpin and resize buttons.
    @Binding var selected: HubTileKind?

    @Environment(HubTiles.self) private var hubTiles
    @Environment(Navigator.self) private var navigator
    @Environment(\.metro) private var metro
    @State private var width: CGFloat = 0
    @State private var drag: TileDrag?
    @State private var pickups = 0
    @State private var confirmsUnpin: HubTileKind?
    /// The tile buttons still see the touch that picked a tile up; its tap shouldn't open or select anything.
    @State private var ignoresTap = false

    private struct TileDrag {
        let kind: HubTileKind
        /// Where the finger holds the tile, from its top-left corner.
        let grab: CGSize
        var location: CGPoint
    }

    private let spacing = MetroMetrics.gutter

    var body: some View {
        let tiles = hubTiles.tiles
        let placements = TilePacking.place(tiles.map(\.size))
        HubTileLayout(placements: placements, spacing: spacing) {
            ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
                tileView(tile, index: index, count: tiles.count)
                    // The held tile follows the finger in the overlay; its slot stays empty.
                    .opacity(drag?.kind == tile.kind ? 0 : 1)
                    .metroFeather(row: 2 + placements[index].row / 2, column: placements[index].column / 2)
            }
        }
        .overlay(alignment: .topLeading) { floatingTile }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .gesture(TileDragRecognizer(minimumDuration: isEditing ? 0.2 : 0.4) { phase, location in
            dragChanged(phase, at: location)
        })
        .sensoryFeedback(.impact(weight: .medium), trigger: pickups)
        .confirmationDialog(
            "Unpin \"\(confirmsUnpin.map(title) ?? "")\"? The photos stay in your library.",
            isPresented: Binding(get: { confirmsUnpin != nil }, set: { if !$0 { confirmsUnpin = nil } }),
            titleVisibility: .visible
        ) {
            Button("Unpin", role: .destructive) {
                if let kind = confirmsUnpin { unpin(kind) }
            }
        }
    }

    private func tileView(_ tile: HubTile, index: Int, count: Int) -> some View {
        let isSelected = isEditing && selected == tile.kind
        let isDimmed = isEditing && !isSelected
        return HubTileFace(tile: tile) {
            if ignoresTap {
                ignoresTap = false
            } else if isEditing {
                withAnimation(MetroMotion.standard) { selected = tile.kind }
            } else {
                open(tile.kind)
            }
        }
        .scaleEffect(isDimmed ? 0.9 : 1)
        .opacity(isDimmed ? 0.6 : 1)
        .modifier(EditDrift(isActive: isDimmed, seed: index))
        // Back into its slot smoothly when editing ends or it's picked.
        .animation(MetroMotion.standard, value: isDimmed)
        .overlay(alignment: .topTrailing) {
            if isSelected && !tile.kind.isBuiltIn {
                editButton("pin.slash", label: "Unpin") { askToUnpin(tile.kind) }
                    .offset(x: 18, y: -18)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if isSelected {
                editButton(tile.size.next.width > tile.size.width ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left", label: "Resize") {
                    withAnimation(MetroMotion.standard) { hubTiles.resize(tile.kind) }
                }
                .offset(x: 18, y: 18)
                .transition(.opacity)
            }
        }
        .zIndex(isSelected ? 1 : 0)
        .accessibilityActions {
            if index > 0 {
                Button("Move earlier") { withAnimation(MetroMotion.standard) { hubTiles.move(tile.kind, to: index - 1) } }
            }
            if index < count - 1 {
                Button("Move later") { withAnimation(MetroMotion.standard) { hubTiles.move(tile.kind, to: index + 1) } }
            }
            Button("Make \(tile.size.next.rawValue)") { withAnimation(MetroMotion.standard) { hubTiles.resize(tile.kind) } }
            if !tile.kind.isBuiltIn {
                Button("Unpin") { askToUnpin(tile.kind) }
            }
        }
    }

    /// While tiles are being rearranged, the ones not held float slowly about their slots, now and then edging over a
    /// neighbour, like the start screen's edit mode.
    private struct EditDrift: ViewModifier {
        let isActive: Bool
        let seed: Int
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        /// How far a tile wanders from its slot; more than the gap, so neighbours can overlap a little.
        private static let reach: CGFloat = 8

        func body(content: Content) -> some View {
            // Each tile gets its own path and pace, so they don't move in step.
            let turn = Double(seed % 5) * 0.23
            let sign: CGFloat = seed.isMultiple(of: 2) ? 1 : -1
            let reach = Self.reach
            let drifts = isActive && !reduceMotion
            content.keyframeAnimator(initialValue: CGSize.zero, repeating: drifts) { content, offset in
                // A stopped animator holds its last value, which left tiles out of their slots after editing.
                content.offset(drifts ? offset : .zero)
            } keyframes: { _ in
                KeyframeTrack(\.width) {
                    CubicKeyframe(sign * reach, duration: 1.7 + turn)
                    CubicKeyframe(-sign * reach * 0.6, duration: 2.1 + turn)
                    CubicKeyframe(0, duration: 1.6)
                }
                KeyframeTrack(\.height) {
                    CubicKeyframe(-reach * 0.7, duration: 1.4 + turn)
                    CubicKeyframe(reach, duration: 2.2)
                    CubicKeyframe(0, duration: 1.8 + turn)
                }
            }
        }
    }

    private func editButton(_ glyph: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: glyph)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(metro.background)
                .frame(width: 30, height: 30)
                .background(Circle().fill(metro.foreground))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var floatingTile: some View {
        if let drag, let index = hubTiles.tiles.firstIndex(where: { $0.kind == drag.kind }) {
            let frame = frames()[index]
            HubTileFace(tile: hubTiles.tiles[index]) {}
                .frame(width: frame.width, height: frame.height)
                .scaleEffect(1.05)
                .offset(x: drag.location.x - drag.grab.width, y: drag.location.y - drag.grab.height)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func frames() -> [CGRect] {
        TilePacking.place(hubTiles.tiles.map(\.size)).map { TilePacking.frame(for: $0, width: width, spacing: spacing) }
    }

    private func dragChanged(_ phase: TileDragRecognizer.Phase, at location: CGPoint) {
        let tiles = hubTiles.tiles
        let frames = frames()
        switch phase {
        case .began:
            guard let index = frames.firstIndex(where: { $0.contains(location) }) else { return }
            let kind = tiles[index].kind
            withAnimation(MetroMotion.standard) {
                isEditing = true
                selected = kind
            }
            let grab = CGSize(width: location.x - frames[index].minX, height: location.y - frames[index].minY)
            drag = TileDrag(kind: kind, grab: grab, location: location)
            ignoresTap = true
            pickups += 1
        case .changed:
            guard var current = drag, let from = tiles.firstIndex(where: { $0.kind == current.kind }) else { return }
            current.location = location
            // Where the held tile is now, not just the finger: a big tile is often held near one edge.
            let held = CGRect(origin: CGPoint(x: location.x - current.grab.width, y: location.y - current.grab.height), size: frames[from].size)
            let index = TilePacking.dropIndex(for: held, sizes: tiles.map(\.size), moving: from, width: width, spacing: spacing)
            if index != from {
                withAnimation(MetroMotion.standard) { hubTiles.move(current.kind, to: index) }
            }
            drag = current
        case .ended:
            // The buttons' tap lands about now, if at all.
            Task {
                try? await Task.sleep(for: .milliseconds(150))
                ignoresTap = false
            }
            guard let current = drag, let index = hubTiles.tiles.firstIndex(where: { $0.kind == current.kind }) else {
                drag = nil
                return
            }
            // Settle into the slot it was dropped on, then hand back to the tile in the grid.
            let slot = self.frames()[index]
            withAnimation(MetroMotion.release) {
                drag?.location = CGPoint(x: slot.minX + current.grab.width, y: slot.minY + current.grab.height)
            } completion: {
                drag = nil
            }
        }
    }

    private func askToUnpin(_ kind: HubTileKind) {
        // A photo set only lives on its tile, so check first; an album can be pinned again from its page.
        if case .photoSet = kind {
            confirmsUnpin = kind
        } else {
            unpin(kind)
        }
    }

    private func unpin(_ kind: HubTileKind) {
        withAnimation(MetroMotion.standard) {
            hubTiles.unpin(kind)
            if selected == kind { selected = nil }
        }
    }

    private func title(_ kind: HubTileKind) -> String {
        if case .photoSet(let id) = kind { return hubTiles.photoSet(id: id)?.title ?? "photos" }
        return ""
    }

    private func open(_ kind: HubTileKind) {
        switch kind {
        case .cameraRoll: navigator.push(.collection(page: 0))
        case .albums: navigator.push(.collection(page: 1))
        case .date: navigator.push(.collection(page: 0, showsJumpList: true))
        case .favorites: navigator.push(.collection(page: CollectionView.favoritesPage))
        case .places: navigator.push(.collection(page: CollectionView.placesPage))
        case .album(let id): navigator.push(.album(id))
        case .photoSet(let id): navigator.push(.photoSet(id))
        }
    }
}

/// Places tiles on the four-cell grid from `TilePacking`.
private struct HubTileLayout: Layout {
    var placements: [TilePlacement]
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let rows = TilePacking.rows(placements)
        guard rows > 0 else { return CGSize(width: width, height: 0) }
        let side = TilePacking.cellSide(width: width, spacing: spacing)
        return CGSize(width: width, height: CGFloat(rows) * (side + spacing) - spacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, subview) in subviews.enumerated() where placements.indices.contains(index) {
            let frame = TilePacking.frame(for: placements[index], width: bounds.width, spacing: spacing)
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }
}

/// One tile: a live tile of photos, the date, or the albums glyph.
struct HubTileFace: View {
    let tile: HubTile
    let action: () -> Void

    @Environment(PhotoLibrary.self) private var library
    @Environment(HubTiles.self) private var hubTiles
    @Environment(Journal.self) private var journal
    @Environment(\.metro) private var metro
    @Environment(\.displayScale) private var displayScale

    private var isSmall: Bool { tile.size == .small }

    var body: some View {
        MetroTile(title: title, showsTitle: !isSmall, action: action) { content }
    }

    private var title: String {
        switch tile.kind {
        case .cameraRoll: "camera roll"
        case .albums: "albums"
        case .date: "date"
        case .favorites: "favorites"
        case .places: "places"
        case .album(let id): library.albumTitle(id: id)
        case .photoSet(let id): hubTiles.photoSet(id: id)?.title ?? "photos"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tile.kind {
        case .cameraRoll:
            photos(library.allAssets.items(limit: 8), fallback: "photo.on.rectangle")
        case .albums:
            AmbientTile(pattern: .albums)
        case .date:
            AmbientTile(pattern: .date).overlay(alignment: .topLeading) { dateFace }
        case .favorites:
            photos(library.favorites.items(limit: 8), fallback: "heart")
        case .places:
            // The newest photo from each of the most recent places.
            let covers = journal.places.prefix(8).compactMap { $0.photoIDs.first.flatMap(library.asset(id:)) }
            photos(covers.map(AssetItem.init), fallback: "map")
        case .album(let id):
            photos(library.assets(in: .album(id)).items(limit: 8), fallback: "rectangle.stack")
        case .photoSet(let id):
            let ids = hubTiles.photoSet(id: id)?.photoIDs ?? []
            photos(library.assets(in: .identifiers(ids)).items(limit: 8), fallback: "photo.stack")
        }
    }

    private func glyph(_ name: String) -> some View {
        metro.accentColor.overlay {
            Image(systemName: name)
                .font(.system(size: isSmall ? 22 : 34, weight: .ultraLight))
                .foregroundStyle(metro.onAccent)
        }
        .tileOnAccent()
    }

    private var dateFace: some View {
        let now = Date()
        return VStack(alignment: .leading, spacing: 0) {
            if !isSmall {
                Text(now.formatted(.dateTime.month(.abbreviated)).lowercased())
                    .font(.metro(22, .semilight))
            }
            Text(now.formatted(.dateTime.day()))
                .font(.metro(isSmall ? 34 : 56, .light))
        }
        .foregroundStyle(metro.onAccent)
        .padding(isSmall ? 6 : 10)
    }

    @ViewBuilder
    private func photos(_ items: [AssetItem], fallback: String) -> some View {
        if items.isEmpty {
            glyph(fallback)
        } else {
            let side: CGFloat = switch tile.size {
            case .small: 100
            case .medium: 200
            case .wide: 400
            }
            LiveTile(items: items) { item in
                AssetThumbnail(asset: item.asset, pixelSide: side * displayScale)
            }
        }
    }
}

/// Press and hold to pick a tile up, then drag it. Once the hold is recognised the scroll views can't start, so the
/// drag moves the tile instead of the panel; moving before the hold lets the panel scroll as usual.
struct TileDragRecognizer: UIGestureRecognizerRepresentable {
    enum Phase { case began, changed, ended }

    var minimumDuration: Double
    /// The finger's location in the grid's own coordinates.
    var onChange: (_ phase: Phase, _ location: CGPoint) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = minimumDuration
        recognizer.allowableMovement = 10
        // Cancelling the buttons' touch left the held tile stuck pressed until the next tap; the grid ignores the
        // tap that ends a hold instead.
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        recognizer.minimumPressDuration = minimumDuration
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let location = context.converter.localLocation
        switch recognizer.state {
        case .began: onChange(.began, location)
        case .changed: onChange(.changed, location)
        case .ended, .cancelled, .failed: onChange(.ended, location)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// Runs alongside the tile buttons (or they'd win and a hold would open the tile), but not the scroll views,
        /// so they can't start once a tile is held.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            !(other.view is UIScrollView)
        }
    }
}
