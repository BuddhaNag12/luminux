import Photos
import SwiftUI

/// "make a widget" in an album's or photo set's menu. Apps can't place widgets themselves, so this readies the
/// collection's photos for the Photos tile and explains how to pick it there.
enum WidgetCollection {
    static func menuItem(
        for collection: LiveTileStore.Collection,
        isAdded: Bool,
        library: PhotoLibrary,
        hubTiles: HubTiles,
        onChange: @escaping (_ added: Bool) -> Void
    ) -> AppBarMenuItem {
        if isAdded {
            AppBarMenuItem(title: "remove from widgets") {
                LiveTileExporter.remove(collection.id)
                onChange(false)
            }
        } else {
            AppBarMenuItem(title: "make a widget") {
                Task {
                    await LiveTileExporter.add(collection, library: library, hubTiles: hubTiles)
                    onChange(true)
                }
            }
        }
    }
}

extension View {
    /// Shows how to put the Photos tile on the Home Screen with `title` once it's set.
    func widgetInstructions(for title: Binding<String?>) -> some View {
        alert("Widget ready", isPresented: Binding { title.wrappedValue != nil } set: { if !$0 { title.wrappedValue = nil } }) {
            Button("OK") {}
        } message: {
            Text(WidgetCollection.steps(for: title.wrappedValue))
        }
    }
}

extension WidgetCollection {
    /// How to show a collection on the Home Screen; apps can't place or set up widgets themselves.
    static func steps(for title: String?) -> String {
        """
        1. Touch and hold an empty spot on your Home Screen, tap Edit, then Add Widget.
        2. Choose Luminux and add the Photos tile.
        3. Touch and hold the tile and tap Edit Widget.
        4. Set Show to “A collection” and pick \(title.map { "“\($0)”" } ?? "an album or photo set").
        """
    }
}

/// Settings' "widget collections" page: every album and photo set, ticked when the Photos widget can show it. Ticking
/// one readies its photos; the widget's own settings then pick which ticked one each tile shows.
struct WidgetCollectionsPicker: View {
    @Environment(PhotoLibrary.self) private var library
    @Environment(HubTiles.self) private var hubTiles
    @Environment(\.metro) private var metro
    @State private var added = Set(LiveTileStore.collections.map(\.id))
    @State private var busy: Set<String> = []

    var body: some View {
        ChoicePage(title: "widget", caption: "Any album or photo set can go on the Photos widget. Ticked ones are ready the moment you pick them; others load the next time you open Luminux.") {
            Text(WidgetCollection.steps(for: nil))
                .font(.metroCaption)
                .foregroundStyle(metro.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(metro.chrome)

            if !library.albums.isEmpty {
                ChoiceHeader(title: "albums")
                ForEach(library.albums) { album in
                    row(.album(album.id, title: album.title), cover: album.keyAssetID.flatMap(library.asset(id:)), count: album.count)
                }
            }
            let sets = hubTiles.photoSets.values.sorted { $0.title < $1.title }
            if library.albums.isEmpty && sets.isEmpty {
                Text("No albums or photo sets yet. Make an album, or pin a few photos to the hub as a set.")
                    .font(.metroBody)
                    .foregroundStyle(metro.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 24)
            }
            if !sets.isEmpty {
                ChoiceHeader(title: "photo sets")
                ForEach(sets) { set in
                    row(.photoSet(set.id, title: set.title), cover: set.photoIDs.first.flatMap(library.asset(id:)), count: set.photoIDs.count)
                }
            }
        }
    }

    private func row(_ collection: LiveTileStore.Collection, cover: PHAsset?, count: Int) -> some View {
        let isAdded = added.contains(collection.id)
        return Button {
            guard !busy.contains(collection.id) else { return }
            if isAdded {
                LiveTileExporter.remove(collection.id)
                added.remove(collection.id)
                return
            }
            busy.insert(collection.id)
            Task {
                await LiveTileExporter.add(collection, library: library, hubTiles: hubTiles)
                busy.remove(collection.id)
                if LiveTileExporter.contains(collection.id) { added.insert(collection.id) }
            }
        } label: {
            ChoiceRow(
                cover: cover,
                title: collection.title,
                detail: isAdded ? "on the widget" : (count == 1 ? "1 photo" : "\(count) photos"),
                isSelected: isAdded,
                isBusy: busy.contains(collection.id)
            )
        }
        .buttonStyle(TiltButtonStyle(touch: nil, size: .zero))
    }
}
