import Photos
import SwiftUI

struct AssetItem: Identifiable {
    let asset: PHAsset
    var id: String { asset.localIdentifier }
}

extension PHFetchResult where ObjectType == PHAsset {
    func items(limit: Int) -> [AssetItem] {
        let end = Swift.min(count, limit)
        guard end > 0 else { return [] }
        return objects(at: IndexSet(integersIn: 0..<end)).map(AssetItem.init)
    }
}

/// The photos hub: a panorama with collection tiles, recent photos and favorites over a photo background.
struct HubView: View {
    @Environment(PhotoLibrary.self) private var library
    @Environment(Navigator.self) private var navigator
    @Environment(AppSettings.self) private var settings
    @Environment(\.metro) private var metro
    @Environment(\.displayScale) private var displayScale
    @State private var isAppBarExpanded = false

    private let tileColumns = [GridItem(.flexible(), spacing: MetroMetrics.gutter), GridItem(.flexible(), spacing: MetroMetrics.gutter)]
    private let photoColumns = Array(repeating: GridItem(.flexible(), spacing: MetroMetrics.gutter), count: 3)

    var body: some View {
        Panorama("photos") {
            PanoramaSection("collection") { collection }
            PanoramaSection("what's new") {
                photoGrid(.recent, limit: 60, empty: "No photos from the last 30 days.")
            }
            PanoramaSection("favorites") {
                photoGrid(.favorites, limit: 60, empty: "No favorites yet. Tap the heart on a photo to add it here.")
            }
        } background: {
            if settings.showsHubBackground {
                HubBackground()
            }
        }
        .metroAppBar([], menu: menu, isExpanded: $isAppBarExpanded)
    }

    private var menu: [AppBarMenuItem] {
        var items = [AppBarMenuItem(title: "settings") { navigator.push(.settings) }]
        if library.access == .limited {
            items.append(AppBarMenuItem(title: "choose more photos") { library.presentLimitedPicker() })
        }
        return items
    }

    private var collection: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: tileColumns, alignment: .leading, spacing: MetroMetrics.gutter) {
                MetroTile(title: "camera roll", action: { navigator.push(.collection(page: 0)) }) {
                    photoLiveTile(library.allAssets.items(limit: 8), style: .flip, fallback: "photo.on.rectangle")
                }
                .aspectRatio(1, contentMode: .fit)
                .metroFeather(row: 2, column: 0)

                MetroTile(title: "albums", action: { navigator.push(.collection(page: 1)) }) {
                    metro.accentColor.overlay {
                        Image(systemName: "rectangle.stack")
                            .font(.system(size: 34, weight: .ultraLight))
                            .foregroundStyle(.white)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .metroFeather(row: 2, column: 1)

                MetroTile(title: "date", action: { navigator.push(.collection(page: 0, showsJumpList: true)) }) {
                    metro.accentColor.overlay(alignment: .topLeading) { dateFace }
                }
                .aspectRatio(1, contentMode: .fit)
                .metroFeather(row: 3, column: 0)

                MetroTile(title: "favorites", action: { navigator.push(.collection(page: 2)) }) {
                    photoLiveTile(library.favorites.items(limit: 8), style: .slide, fallback: "heart")
                }
                .aspectRatio(1, contentMode: .fit)
                .metroFeather(row: 3, column: 1)
            }
            .padding(.trailing, MetroMetrics.margin)

            if library.access == .limited {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Luminux can see only the photos you picked.")
                        .font(.metroBody)
                        .foregroundStyle(metro.secondary)
                    Button("choose more") { library.presentLimitedPicker() }
                        .buttonStyle(.metro)
                }
            }
        }
    }

    private var dateFace: some View {
        let now = Date()
        return VStack(alignment: .leading, spacing: 0) {
            Text(now.formatted(.dateTime.month(.abbreviated)).lowercased())
                .font(.metro(22, .semilight))
            Text(now.formatted(.dateTime.day()))
                .font(.metro(56, .light))
        }
        .foregroundStyle(.white)
        .padding(10)
    }

    @ViewBuilder
    private func photoLiveTile(_ items: [AssetItem], style: LiveTile<AssetItem, AssetThumbnail>.Style, fallback: String) -> some View {
        if items.isEmpty {
            metro.accentColor.overlay {
                Image(systemName: fallback).font(.system(size: 34, weight: .ultraLight)).foregroundStyle(.white)
            }
        } else {
            LiveTile(items: items, style: style) { item in
                AssetThumbnail(asset: item.asset, pixelSide: 200 * displayScale)
            }
        }
    }

    @ViewBuilder
    private func photoGrid(_ source: AssetSource, limit: Int, empty: String) -> some View {
        let items = library.assets(in: source).items(limit: limit)
        if items.isEmpty && library.isLoaded {
            Text(empty)
                .font(.metroBody)
                .foregroundStyle(metro.secondary)
                .padding(.trailing, MetroMetrics.margin)
        } else {
            LazyVGrid(columns: photoColumns, spacing: MetroMetrics.gutter) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    Button {
                        navigator.openViewer(source, at: item.id, index: index)
                    } label: {
                        AssetThumbnail(asset: item.asset, pixelSide: 120 * displayScale)
                            .aspectRatio(1, contentMode: .fit)
                    }
                    .buttonStyle(TiltButtonStyle(touch: nil, size: .zero))
                    .metroFeather(row: 2 + index / 3, column: index % 3)
                    .zoomSource(id: item.id)
                }
            }
            .padding(.trailing, MetroMetrics.margin)
        }
    }
}

/// A recent photo behind the hub, picked once per launch.
private struct HubBackground: View {
    @Environment(PhotoLibrary.self) private var library
    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.4), value: image == nil)
            .clipped()
            .task(id: library.isLoaded) {
                guard image == nil else { return }
                let source = library.favorites.count > 0 ? library.favorites : library.allAssets
                let photos = source.items(limit: 40).filter { $0.asset.mediaType == .image }
                guard let pick = photos.randomElement() else { return }
                for await next in ImageLoader.shared.images(for: pick.asset, targetSize: CGSize(width: 2400, height: 2400)) {
                    image = next
                }
            }
    }
}
