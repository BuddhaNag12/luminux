import Photos
import UIKit
import WidgetKit

/// Copies a few downscaled photos into the App Group for the home-screen live tile: recent, favorites, and every
/// album or photo set someone made a widget from.
enum LiveTileExporter {
    private static let side: CGFloat = 600

    static func export(from library: PhotoLibrary, hubTiles: HubTiles, accent: Accent) async {
        LiveTileStore.accentHex = accent.hex
        for source in LiveTileStore.Source.allCases {
            let assets = source == .recent ? library.allAssets : library.favorites
            // Recent stays the newest photos; favorites shuffle like collections do.
            let data = await jpegs(from: assets, shuffled: source == .favorites)
            await Task.detached(priority: .utility) { try? LiveTileStore.replaceImages(data, for: source) }.value
        }

        // Albums and sets that are gone take their widget choice with them; the rest pick up renames and new photos.
        var kept: [LiveTileStore.Collection] = []
        for var collection in LiveTileStore.collections {
            guard let (title, assets) = contents(of: collection, library: library, hubTiles: hubTiles) else {
                LiveTileStore.removeImages(for: collection)
                continue
            }
            collection.title = title
            let data = await jpegs(from: assets, shuffled: true)
            let stored = collection
            await Task.detached(priority: .utility) { try? LiveTileStore.replaceImages(data, for: stored) }.value
            kept.append(collection)
        }
        LiveTileStore.collections = kept
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Adds an album or photo set to the widget's choices, with its photos ready, and returns its name.
    static func add(_ collection: LiveTileStore.Collection, library: PhotoLibrary, hubTiles: HubTiles) async {
        guard let (title, assets) = contents(of: collection, library: library, hubTiles: hubTiles) else { return }
        var stored = collection
        stored.title = title
        try? LiveTileStore.replaceImages(await jpegs(from: assets, shuffled: true), for: stored)
        LiveTileStore.collections = LiveTileStore.collections.filter { $0.id != stored.id } + [stored]
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func remove(_ id: String) {
        LiveTileStore.collections.filter { $0.id == id }.forEach(LiveTileStore.removeImages(for:))
        LiveTileStore.collections.removeAll { $0.id == id }
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func contains(_ id: String) -> Bool {
        LiveTileStore.collections.contains { $0.id == id }
    }

    /// The collection's current name and photos, or nil once it no longer exists.
    private static func contents(of collection: LiveTileStore.Collection, library: PhotoLibrary, hubTiles: HubTiles) -> (String, PHFetchResult<PHAsset>)? {
        if collection.id.hasPrefix("album:") {
            let id = String(collection.id.dropFirst("album:".count))
            // Asked of PhotoKit directly: the library's album list leaves out empty smart albums.
            guard let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
            return (album.localizedTitle ?? collection.title, library.assets(in: .album(id)))
        } else if collection.id.hasPrefix("set:") {
            guard let set = hubTiles.photoSet(id: String(collection.id.dropFirst("set:".count))) else { return nil }
            return (set.title, library.assets(in: .identifiers(set.photoIDs)))
        }
        return nil
    }

    /// Up to `maxImages` photos: the newest, or a random pick from across the collection.
    private static func jpegs(from assets: PHFetchResult<PHAsset>, shuffled: Bool = false) async -> [Data] {
        let pool = shuffled ? assets.items(limit: 500).shuffled() : assets.items(limit: 30)
        let photos = pool.filter { $0.asset.mediaType == .image }.prefix(LiveTileStore.maxImages)
        var jpegs: [Data] = []
        for item in photos {
            var latest: UIImage?
            for await image in ImageLoader.shared.images(for: item.asset, targetSize: CGSize(width: side, height: side)) {
                latest = image
            }
            guard let latest else { continue }
            // Encoding on the main thread dropped frames while the hub was opening.
            let box = UncheckedBox(value: latest)
            if let data = await Task.detached(priority: .utility, operation: { box.value.jpegData(compressionQuality: 0.8) }).value {
                jpegs.append(data)
            }
        }
        return jpegs
    }
}
