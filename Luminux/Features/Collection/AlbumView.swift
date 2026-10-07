import Photos
import SwiftUI

struct AlbumView: View {
    let albumID: String

    @Environment(PhotoLibrary.self) private var library
    @Environment(Navigator.self) private var navigator
    @Environment(\.metro) private var metro
    @State private var selection = SelectionModel()
    @State private var isAppBarExpanded = false
    @State private var share: ShareItems?
    @State private var addToAlbum: AddToAlbumRequest?
    @State private var isRenaming = false
    @State private var newName = ""
    @State private var confirmsDelete = false
    /// Keeps the title on screen while a deleted album's page swings away.
    @State private var lastTitle = "album"
    @State private var bottomInset: CGFloat = 0

    private var album: Album? { library.album(id: albumID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(selection.isActive ? "LUMINUX · \(selection.selectedIDs.count) SELECTED" : "LUMINUX")
                .font(.metroOverline)
                .tracking(1.5)
                .padding(.leading, MetroMetrics.margin + 4)
                .metroFeather(row: 0)
            Text(album?.title ?? lastTitle)
                .font(.metroTitle)
                .lineLimit(1)
                .fixedSize()
                .padding(.leading, MetroMetrics.margin + 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
                .metroFeather(row: 0)
                .padding(.bottom, 8)

            AssetGrid(source: .album(albumID), selection: selection, emptyMessage: "This album is empty.", jumpTarget: .constant(nil))
                // Runs under the app bar; the last row can still scroll clear of it.
                .contentMargins(.bottom, bottomInset, for: .scrollContent)
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomInset = $0 }
        .foregroundStyle(metro.foreground)
        .background(metro.background)
        .onChange(of: album?.title, initial: true) { _, title in
            if let title { lastTitle = title }
        }
        .metroAppBar(buttons, menu: menu, isExpanded: $isAppBarExpanded)
        .assetActionSheets(share: $share, addToAlbum: $addToAlbum)
        .alert("Rename album", isPresented: $isRenaming) {
            TextField("Album name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                Task { try? await library.renameAlbum(id: albumID, to: name) }
            }
        }
        .confirmationDialog("Delete this album? The photos stay in your library.", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete album", role: .destructive) {
                Task {
                    try? await library.deleteAlbum(id: albumID)
                    // Let the library reload land first; it re-renders every page and would stall the feather-out.
                    for _ in 0..<20 where library.album(id: albumID) != nil {
                        try? await Task.sleep(for: .milliseconds(50))
                    }
                    navigator.pop()
                }
            }
        }
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
        return [AppBarButton(title: "select", systemImage: "checklist") { selection.begin() }]
    }

    private var menu: [AppBarMenuItem] {
        if selection.isActive {
            var items = [AppBarMenuItem(title: "cancel selection") { selection.end() }]
            if album?.isUserAlbum == true {
                items.insert(AppBarMenuItem(title: "remove from album", isEnabled: !selection.selectedIDs.isEmpty) {
                    let assets = selection.selectedAssets
                    Task {
                        try? await library.remove(assets, fromAlbum: albumID)
                        selection.end()
                    }
                }, at: 0)
            }
            return items
        }
        guard album?.isUserAlbum == true else { return [] }
        return [
            AppBarMenuItem(title: "rename") {
                newName = album?.title ?? ""
                isRenaming = true
            },
            AppBarMenuItem(title: "delete album") { confirmsDelete = true },
        ]
    }
}
