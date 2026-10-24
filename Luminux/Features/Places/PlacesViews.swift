import MapKit
import Photos
import SwiftUI

/// The collection's "places" page: a map of where photos were taken, with nearby places merged into one bubble when
/// zoomed out, and every place listed below it, the most recently visited first. With iPhone Duo open, the map takes the
/// top of the screen and the places fill the bottom as folders.
struct PlacesPage: View {

    @Environment(Journal.self) private var journal
    @Environment(PhotoLibrary.self) private var library
    @Environment(Navigator.self) private var navigator
    @Environment(\.metro) private var metro
    @Environment(\.displayScale) private var displayScale
    @Environment(\.splitY) private var splitY
    @State private var position: MapCameraPosition = .automatic
    @State private var pageTop: CGFloat = 0
    /// Degrees of latitude the map shows, for merging bubbles.
    @State private var span: Double = 40
    /// The map is created once the page has turned in: setting MapKit up the first time takes long enough to drop
    /// frames in the middle of the page's entrance.
    @State private var showsMap = false

    var body: some View {
        Group {
            if let splitY, !journal.places.isEmpty {
                VStack(spacing: MetroMetrics.gutter) {
                    // The map ends on the split line, so it fills the top half and the folders the bottom one.
                    mapArea
                        .frame(height: max(splitY - pageTop, 120))
                    folders
                }
                .padding(.horizontal, MetroMetrics.margin)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if journal.places.isEmpty {
                            Text(journal.isBuilt
                                 ? "No photos with a location yet. Photos taken with Location Services on for the Camera show up here."
                                 : "Finding where your photos were taken…")
                                .font(.metroBody)
                                .foregroundStyle(metro.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .metroFeather(row: 0)
                        } else {
                            mapArea.frame(height: 300)
                            list
                        }
                    }
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .padding(.horizontal, MetroMetrics.margin)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { pageTop = $0 }
        .task {
            try? await Task.sleep(for: .seconds(Feather.enterTime))
            withAnimation(MetroMotion.fade) { showsMap = true }
        }
        .onChange(of: journal.places.count, initial: true) {
            if let region = PlaceGrouping.region(showing: journal.places) {
                position = .region(region)
                span = region.span.latitudeDelta
            }
        }
    }

    private var mapArea: some View {
        ZStack {
            metro.chrome
            if showsMap {
                map.transition(.opacity)
            }
        }
        .metroFeatherFade()
    }

    private var map: some View {
        Map(position: $position, interactionModes: [.pan, .zoom]) {
            ForEach(PlaceGrouping.clusters(journal.places, span: span)) { cluster in
                Annotation(journal.title(for: cluster.lead), coordinate: cluster.center.location, anchor: .center) {
                    Button { open(cluster) } label: { PlaceBubble(cluster: cluster, label: "\(journal.title(for: cluster.lead)), \(cluster.count) photos", library: library, metro: metro, displayScale: displayScale) }
                        .buttonStyle(.plain)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls {}
        .onMapCameraChange(frequency: .onEnd) { context in
            span = context.region.span.latitudeDelta
        }
        .accessibilityLabel("Map of where your photos were taken")
    }

    private var list: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(Array(journal.places.enumerated()), id: \.element.id) { index, place in
                Button {
                    navigator.push(.place(place.id))
                } label: {
                    HStack(spacing: 14) {
                        Group {
                            if let id = place.photoIDs.first, let asset = library.asset(id: id) {
                                AssetThumbnail(asset: asset, pixelSide: 72 * displayScale)
                            } else {
                                metro.chrome
                            }
                        }
                        .frame(width: 72, height: 72)
                        .clipped()
                        VStack(alignment: .leading, spacing: 2) {
                            Text(journal.title(for: place))
                                .font(.metro(20, .semilight))
                                .lineLimit(1)
                            Text("\(place.count) \(place.count == 1 ? "photo" : "photos") · \(place.latest.formatted(.dateTime.month(.abbreviated).year()).lowercased())")
                                .font(.metroCaption)
                                .foregroundStyle(metro.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(TiltButtonStyle(touch: nil, size: .zero))
                .metroFeather(row: 1 + min(index, 12))
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// Every place as a folder tile: its newest photo, name and count.
    private var folders: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: MetroMetrics.gutter)], spacing: MetroMetrics.gutter) {
                ForEach(Array(journal.places.enumerated()), id: \.element.id) { index, place in
                    Button { navigator.push(.place(place.id)) } label: { folder(place) }
                        .buttonStyle(TiltButtonStyle(touch: nil, size: .zero))
                        .metroFeather(row: 1 + min(index / 2, 12), column: index % 2)
                        .accessibilityLabel("\(journal.title(for: place)), \(place.count) photos")
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    private func folder(_ place: Place) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let id = place.photoIDs.first, let asset = library.asset(id: id) {
                    AssetThumbnail(asset: asset, pixelSide: 200 * displayScale)
                } else {
                    metro.chrome
                }
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(journal.title(for: place))
                        .font(.metro(15, .semibold))
                        .lineLimit(1)
                    Text("\(place.count) \(place.count == 1 ? "photo" : "photos")")
                        .font(.metroCaption)
                        .opacity(0.85)
                }
                .foregroundStyle(.white)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom))
            }
            .clipped()
    }

    /// One place opens; several zoom the map in on them.
    private func open(_ cluster: PlaceCluster) {
        if cluster.places.count == 1 {
            navigator.push(.place(cluster.lead.id))
        } else if let region = PlaceGrouping.region(showing: cluster.places) {
            withAnimation(MetroMotion.standard) { position = .region(region) }
            span = region.span.latitudeDelta
        }
    }
}

/// The photos taken at one place, oldest first, like a journal entry, under a map of where each was taken. With iPhone
/// Duo open the map fills the top half.
struct PlaceView: View {
    let placeID: String

    @Environment(Journal.self) private var journal
    @Environment(\.metro) private var metro
    @Environment(\.displayScale) private var displayScale
    @Environment(\.splitY) private var splitY
    @Environment(\.zoomPageDepth) private var pageDepth
    @Environment(Navigator.self) private var navigator
    @State private var mapTop: CGFloat = 0
    /// Each located photo as a one-photo place, so the map can merge nearby ones into a bubble like the places page.
    @State private var photoSpots: [Place] = []
    @State private var span: Double = 1
    /// Made once the page has turned in, as on the places page: MapKit's first setup drops frames otherwise.
    @State private var showsMap = false
    @State private var selection = SelectionModel()
    @State private var isAppBarExpanded = false
    @State private var share: ShareItems?
    @State private var addToAlbum: AddToAlbumRequest?
    @State private var bottomInset: CGFloat = 0
    @Environment(PhotoLibrary.self) private var library

    private var place: Place? { journal.place(id: placeID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(selection.isActive ? "LUMINUX · \(selection.selectedIDs.count) SELECTED" : "LUMINUX · PLACES")
                .font(.metroOverline).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .tracking(1.5)
                .padding(.leading, MetroMetrics.margin + 4)
                .metroFeather(row: 0)
            Text(place.map(journal.title(for:)) ?? "place")
                .font(.metroTitle)
                .lineLimit(1)
                .padding(.leading, MetroMetrics.margin + 1)
                .metroOverflowingTitle()
                .metroFeather(row: 0)
                .padding(.bottom, 8)

            if let place {
                ZStack {
                    metro.chrome
                    if showsMap { map(place).transition(.opacity) }
                }
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { mapTop = $0 }
                .frame(height: mapHeight)
                // Edge to edge like the grid below it.
                .padding(.bottom, 12)
                .metroFeatherFade()
            }

            AssetGrid(
                source: .identifiers(place?.photoIDs ?? []),
                selection: selection,
                emptyMessage: "These photos are no longer in your library.",
                jumpTarget: .constant(nil)
            )
            .contentMargins(.bottom, bottomInset, for: .scrollContent)
            .ignoresSafeArea(.container, edges: .bottom)
        }
        // Anchored to the top, so a taller map can't shift its own top and grow without end.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomInset = $0 }
        .foregroundStyle(metro.foreground)
        .background(metro.background)
        .task {
            // Looked up in one query off the main thread while the page turns in; one query per photo in the view's
            // body held the main thread for over a second on a large place.
            let ids = place?.photoIDs ?? []
            async let spots = Task.detached(priority: .userInitiated) { Self.spots(for: ids) }.value
            try? await Task.sleep(for: .seconds(Feather.enterTime))
            photoSpots = await spots
            span = PlaceGrouping.region(showing: photoSpots)?.span.latitudeDelta ?? 1
            withAnimation(MetroMotion.fade) { showsMap = true }
        }
        // Tearing MapKit down is slow too: drop the map as the page starts to leave, before the page below turns in.
        .onChange(of: navigator.isLeaving && navigator.path.count == pageDepth) { _, leaving in
            if leaving { withAnimation(.easeOut(duration: 0.1)) { showsMap = false } }
        }
        .metroAppBar(buttons, menu: selection.isActive ? [AppBarMenuItem(title: "cancel selection") { selection.end() }] : [], isExpanded: $isAppBarExpanded)
        .assetActionSheets(share: $share, addToAlbum: $addToAlbum)
    }

    /// Down to the split line on iPhone Duo, a strip elsewhere.
    private var mapHeight: CGFloat {
        guard let splitY, mapTop.isFinite else { return 220 }
        return min(max(splitY - mapTop, 120), 900)
    }

    /// Photos pinned where they were taken, nearby ones merged into one bubble, on a map framing them all.
    private func map(_ place: Place) -> some View {
        let region = PlaceGrouping.region(showing: photoSpots.isEmpty ? [place] : photoSpots)
        return Map(initialPosition: region.map(MapCameraPosition.region) ?? .automatic, interactionModes: [.pan, .zoom]) {
            ForEach(PlaceGrouping.clusters(photoSpots, span: span)) { cluster in
                Annotation("", coordinate: cluster.center.location, anchor: .center) {
                    PlaceBubble(cluster: cluster, label: "\(cluster.count) \(cluster.count == 1 ? "photo" : "photos")", library: library, metro: metro, displayScale: displayScale)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls {}
        .onMapCameraChange(frequency: .onEnd) { context in
            span = context.region.span.latitudeDelta
        }
        .accessibilityLabel("Map of where these photos were taken")
    }

    nonisolated private static func spots(for ids: [String]) -> [Place] {
        var spots: [Place] = []
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { asset, _, _ in
            guard let coordinate = asset.location?.coordinate else { return }
            spots.append(Place(
                id: asset.localIdentifier,
                center: Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude),
                photoIDs: [asset.localIdentifier],
                latest: asset.creationDate ?? .distantPast
            ))
        }
        return spots
    }

    private var buttons: [AppBarButton] {
        if selection.isActive {
            return SelectionActions.buttons(
                selection: selection,
                library: library,
                share: { assets in
                    Task {
                        let urls = await ImageLoader.shared.exportOriginals(assets)
                        if !urls.isEmpty { share = ShareItems(urls: urls) }
                    }
                },
                addToAlbum: { assets in addToAlbum = AddToAlbumRequest(assets: assets) }
            )
        }
        return selection.isAllowed ? [AppBarButton(title: "select", systemImage: "checklist") { selection.begin() }] : []
    }
}

extension Coordinate {
    var location: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

/// A cluster on a map: its newest photo, with how many photos it holds. Map annotations don't get the page's
/// environment, so the library and theme are handed in.
private struct PlaceBubble: View {
    let cluster: PlaceCluster
    let label: String
    let library: PhotoLibrary
    let metro: MetroPalette
    let displayScale: CGFloat

    var body: some View {
        Group {
            if let id = cluster.lead.photoIDs.first, let asset = library.asset(id: id) {
                AssetThumbnail(asset: asset, pixelSide: 56 * displayScale)
            } else {
                metro.chrome
            }
        }
        .frame(width: 52, height: 52)
        .clipped()
        .overlay(Rectangle().strokeBorder(.white, lineWidth: 2))
        .overlay(alignment: .topTrailing) {
            Text("\(cluster.count)")
                .font(.metro(12, .semibold))
                .foregroundStyle(metro.onAccent)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(metro.accentColor)
                .offset(x: 6, y: -6)
        }
        .accessibilityLabel(label)
    }
}
