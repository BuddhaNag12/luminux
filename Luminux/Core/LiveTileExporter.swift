import Photos
import UIKit
import WidgetKit

/// Copies a few downscaled recent and favorite photos into the App Group for the home-screen live tile.
enum LiveTileExporter {
    private static let side: CGFloat = 600

    static func export(from library: PhotoLibrary, accent: Accent) async {
        LiveTileStore.accentHex = accent.hex
        for source in LiveTileStore.Source.allCases {
            let assets = source == .recent ? library.allAssets : library.favorites
            let photos = assets.items(limit: 30).filter { $0.asset.mediaType == .image }.prefix(LiveTileStore.maxImages)
            var jpegs: [Data] = []
            for item in photos {
                var latest: UIImage?
                for await image in ImageLoader.shared.images(for: item.asset, targetSize: CGSize(width: side, height: side)) {
                    latest = image
                }
                if let data = latest?.jpegData(compressionQuality: 0.8) { jpegs.append(data) }
            }
            try? LiveTileStore.replaceImages(jpegs, for: source)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
