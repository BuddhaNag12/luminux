import Photos
import SwiftUI

/// Pivot over the whole library: all (by month), albums, favorites, videos.
struct CollectionView: View {
    @State var page: Int
    @State var showsJumpList: Bool

    @Environment(PhotoLibrary.self) private var library
    @Environment(Navigator.self) private var navigator
    @Environment(\.metro) private var metro
    @State private var selection = SelectionModel()
    @State private var jumpTarget: String?
    @State private var isAppBarExpanded = false
    @State private var share: ShareItems?
    @State private var addToAlbum: AddToAlbumRequest?
    @State private var isNamingAlbum = false
    @State private var newAlbumName = ""

    private static let albumsPage = 1

    init(page: Int, showsJumpList: Bool = false) {
        _page = State(initialValue: page)
        _showsJumpList = State(initialValue: showsJumpList)
    }

    var body: some View {
        ZStack {
            Pivot(overline: selection.isActive ? "LUMINUX · \(selection.selectedIDs.count) SELECTED" : "LUMINUX", selection: $page) {
                AssetGrid(
                    source: .all,
                    sections: library.sections,
                    selection: selection,
                    emptyMessage: "No photos yet.",
                    onHeaderTap: { showsJumpList = true },
                    jumpTarget: $jumpTarget
                )
                .pivotTitle("all")

                AlbumsGrid().pivotTitle("albums")

                AssetGrid(
                    source: .favorites,
                    selection: selection,
                    emptyMessage: "No favorites yet. Tap the heart on a photo to add it here.",
                    jumpTarget: .constant(nil)
                )
                .pivotTitle("favorites")

                AssetGrid(source: .videos, selection: selection, emptyMessage: "No videos yet.", jumpTarget: .constant(nil))
                    .pivotTitle("videos")
            }
            .metroAppBar(appBarButtons, menu: menu, isExpanded: $isAppBarExpanded)

            if showsJumpList {
                JumpListView(sections: library.sections, currentSectionID: library.sections.first?.id) { id in
                    page = 0
                    jumpTarget = id
                    showsJumpList = false
                }
                .transition(.scale(scale: 1.1).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .animation(MetroMotion.standard, value: showsJumpList)
        .onChange(of: page) { _, newPage in
            if newPage == Self.albumsPage { selection.end() }
        }
        .assetActionSheets(share: $share, addToAlbum: $addToAlbum)
        .alert("New album", isPresented: $isNamingAlbum) {
            TextField("Album name", text: $newAlbumName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let name = newAlbumName.trimmingCharacters(in: .whitespaces)
                newAlbumName = ""
                guard !name.isEmpty else { return }
                Task { try? await library.createAlbum(named: name) }
            }
        }
    }

    private var appBarButtons: [AppBarButton] {
        if selection.isActive {
            return SelectionActions.buttons(
                selection: selection,
                library: library,
                share: { assets in exportForSharing(assets) },
                addToAlbum: { assets in addToAlbum = AddToAlbumRequest(assets: assets) }
            )
        }
        if page == Self.albumsPage {
            return [AppBarButton(title: "new album", systemImage: "plus") { isNamingAlbum = true }]
        }
        return [AppBarButton(title: "select", systemImage: "checklist") { selection.begin() }]
    }

    private var menu: [AppBarMenuItem] {
        if selection.isActive {
            return [AppBarMenuItem(title: "cancel selection") { selection.end() }]
        }
        return [AppBarMenuItem(title: "settings") { navigator.push(.settings) }]
    }

    private func exportForSharing(_ assets: [PHAsset]) {
        Task {
            let urls = await ImageLoader.shared.exportOriginals(assets)
            if !urls.isEmpty { share = ShareItems(urls: urls) }
        }
    }
}

struct AlbumsGrid: View {
    @Environment(PhotoLibrary.self) private var library
    @Environment(Navigator.self) private var navigator
    @Environment(\.metro) private var metro
    @Environment(\.displayScale) private var displayScale

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            if library.albums.isEmpty && library.isLoaded {
                Text("No albums yet. Use \"new album\" below to make one.")
                    .font(.metroBody)
                    .foregroundStyle(metro.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(Array(library.albums.enumerated()), id: \.element.id) { index, album in
                    Button {
                        navigator.push(.album(album.id))
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Group {
                                if let id = album.keyAssetID, let asset = library.asset(id: id) {
                                    AssetThumbnail(asset: asset, pixelSide: 200 * displayScale)
                                } else {
                                    metro.chrome
                                }
                            }
                            .aspectRatio(1, contentMode: .fit)

                            Text(album.title)
                                .font(.metro(20, .semilight))
                                .lineLimit(1)
                            Text("\(album.count)")
                                .font(.metroCaption)
                                .foregroundStyle(metro.secondary)
                        }
                    }
                    .buttonStyle(TiltButtonStyle(touch: nil, size: .zero))
                    .metroFeather(row: index / 2, column: index % 2, spacing: 12)
                }
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, MetroMetrics.margin)
    }
}
