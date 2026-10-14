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
            Text("Touch and hold an empty spot on your Home Screen, tap Edit, then Add Widget and choose Luminux. Once the Photos tile is placed, touch and hold it, tap Edit Widget, set Show to “A collection” and choose “\(title.wrappedValue ?? "")”.")
        }
    }
}
