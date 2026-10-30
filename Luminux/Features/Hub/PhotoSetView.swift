import SwiftUI

/// Photos pinned together from select mode, oldest first, with rename, remove and unpin.
struct PhotoSetView: View {
    let setID: String

    @Environment(PhotoLibrary.self) private var library
    @Environment(Navigator.self) private var navigator
    @Environment(HubTiles.self) private var hubTiles
    @Environment(\.metro) private var metro
    @State private var selection = SelectionModel()
    @State private var isAppBarExpanded = false
    @State private var share: ShareItems?
    @State private var addToAlbum: AddToAlbumRequest?
    @State private var isRenaming = false
    @State private var newName = ""
    @State private var confirmsUnpin = false
    @State private var isWidget = false
    @State private var widgetReadyTitle: String?
    /// Keeps the title on screen while an unpinned set's page swings away.
    @State private var lastTitle = "photos"
    @State private var bottomInset: CGFloat = 0

    private var photoSet: PhotoSet? { hubTiles.photoSet(id: setID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(selection.isActive ? "LUMINUX · \(selection.selectedIDs.count) SELECTED" : "LUMINUX")
                .font(.metroOverline).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .tracking(1.5)
                .padding(.leading, MetroMetrics.margin + 4)
                .metroFeather(row: 0)
            Text(photoSet?.title ?? lastTitle)
                .font(.metroTitle)
                .lineLimit(1)
                .padding(.leading, MetroMetrics.margin + 1)
                .metroOverflowingTitle()
                .metroFeather(row: 0)
                .padding(.bottom, 8)

            AssetGrid(
                source: .identifiers(photoSet?.photoIDs ?? []),
                selection: selection,
                emptyMessage: "These photos are no longer in your library.",
                jumpTarget: .constant(nil)
            )
            // Runs under the app bar; the last row can still scroll clear of it.
            .contentMargins(.bottom, bottomInset, for: .scrollContent)
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom.rounded() } action: { bottomInset = $0 }
        .foregroundStyle(metro.foreground)
        .background(metro.background)
        .onChange(of: photoSet?.title, initial: true) { _, title in
            if let title { lastTitle = title }
        }
        .metroAppBar(photoSet == nil ? [] : buttons, menu: photoSet == nil ? [] : menu, isExpanded: $isAppBarExpanded)
        .widgetInstructions(for: $widgetReadyTitle)
        .onAppear { isWidget = LiveTileExporter.contains(widgetCollection.id) }
        .assetActionSheets(share: $share, addToAlbum: $addToAlbum)
        .alert("Rename", isPresented: $isRenaming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { hubTiles.rename(set: setID, to: newName) }
        }
        .confirmationDialog("Unpin \"\(lastTitle)\"? The photos stay in your library.", isPresented: $confirmsUnpin, titleVisibility: .visible) {
            Button("Unpin", role: .destructive) {
                hubTiles.unpin(.photoSet(setID))
                navigator.pop()
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
        return selection.isAllowed ? [AppBarButton(title: "select", systemImage: "checklist") { selection.begin() }] : []
    }

    private var widgetCollection: LiveTileStore.Collection {
        .photoSet(setID, title: photoSet?.title ?? lastTitle)
    }

    private var menu: [AppBarMenuItem] {
        if selection.isActive {
            return [
                AppBarMenuItem(title: "remove from set", isEnabled: !selection.selectedIDs.isEmpty) {
                    hubTiles.remove(selection.selectedIDs, fromSet: setID)
                    selection.end()
                },
                AppBarMenuItem(title: "cancel selection") { selection.end() },
            ]
        }
        return [
            AppBarMenuItem(title: "rename") {
                newName = photoSet?.title ?? ""
                isRenaming = true
            },
            WidgetCollection.menuItem(for: widgetCollection, isAdded: isWidget, library: library, hubTiles: hubTiles) { added in
                isWidget = added
                if added { widgetReadyTitle = photoSet?.title ?? lastTitle }
            },
            AppBarMenuItem(title: "unpin") { confirmsUnpin = true },
        ]
    }
}
