import MapKit
import Photos
import SwiftUI

/// The collection's "places" page: a map of where photos were taken, with nearby places merged into one bubble when
/// zoomed out, and every place listed below it, the most recently visited first. With iPhone Duo open, the map takes the
/// top of the screen and the photos of the places on it fill the bottom.
struct PlacesPage: View {
    var selection: SelectionModel

    @Environment(Journal.self) private var journal
    @Environment(PhotoLibrary.self) private var library
    @Environment(Navigator.self) private var navigator
    @Environment(\.metro) private var metro
    @Environment(\.displayScale) private var displayScale
    @Environment(\.splitY) private var splitY
    @State private var position: MapCameraPosition = .automatic
    /// What the map shows, for the photos below it.
    @State private var region: MKCoordinateRegion?
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
                    // The map ends on the split line, so it fills the top half and the photos the bottom one.
                    mapArea
                        .frame(height: max(splitY - pageTop, 120))
                        .padding(.horizontal, MetroMetrics.margin)
                    AssetGrid(
                        source: .identifiers(region.map { PlaceGrouping.photoIDs(in: $0, places: journal.places) } ?? journal.places.flatMap(\.photoIDs)),
                        selection: selection,
                        emptyMessage: "No photos here. Move the map to see more.",
                        jumpTarget: .constant(nil)
                    )
                }
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
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(MetroMotion.fade) { showsMap = true }
        }
        .onChange(of: journal.places.count, initial: true) {
            if let region = PlaceGrouping.region(showing: journal.places) {
                position = .region(region)
                span = region.span.latitudeDelta
                self.region = region
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
        .clipShape(Rectangle())
        .metroFeather(row: 0)
    }

    private var map: some View {
        Map(position: $position, interactionModes: [.pan, .zoom]) {
            ForEach(PlaceGrouping.clusters(journal.places, span: span)) { cluster in
                Annotation(journal.title(for: cluster.lead), coordinate: cluster.center.location, anchor: .center) {
                    Button { open(cluster) } label: { bubble(cluster) }
                        .buttonStyle(.plain)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls {}
        .onMapCameraChange(frequency: .onEnd) { context in
            span = context.region.span.latitudeDelta
            region = context.region
        }
        .accessibilityLabel("Map of where your photos were taken")
    }

    private func bubble(_ cluster: PlaceCluster) -> some View {
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
        .accessibilityLabel("\(journal.title(for: cluster.lead)), \(cluster.count) photos")
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

/// The photos taken at one place, oldest first, like a journal entry.
struct PlaceView: View {
    let placeID: String

    @Environment(Journal.self) private var journal
    @Environment(\.metro) private var metro
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

            AssetGrid(
                source: .identifiers(place?.photoIDs ?? []),
                selection: selection,
                emptyMessage: "These photos are no longer in your library.",
                jumpTarget: .constant(nil)
            )
            .contentMargins(.bottom, bottomInset, for: .scrollContent)
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomInset = $0 }
        .foregroundStyle(metro.foreground)
        .background(metro.background)
        .metroAppBar(buttons, menu: selection.isActive ? [AppBarMenuItem(title: "cancel selection") { selection.end() }] : [], isExpanded: $isAppBarExpanded)
        .assetActionSheets(share: $share, addToAlbum: $addToAlbum)
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
