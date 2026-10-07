import AVFoundation
import Photos
import UIKit

/// Thin async layer over PHCachingImageManager. Results stream in: a fast low-quality image first, then the final one.
nonisolated final class ImageLoader: @unchecked Sendable {
    static let shared = ImageLoader()

    private let manager = PHCachingImageManager()
    private let decodeQueue = DispatchQueue(label: "com.buddhanag.luminux.decode", qos: .userInitiated)

    func images(for asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode = .aspectFill) -> AsyncStream<UIImage> {
        let manager = manager
        return AsyncStream { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            let decodeQueue = decodeQueue
            let request = manager.requestImage(for: asset, targetSize: targetSize, contentMode: contentMode, options: options) { @Sendable image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let failed = info?[PHImageErrorKey] != nil || (info?[PHImageCancelledKey] as? Bool) == true
                // Decode before the view sees it; otherwise the first draw decodes on the main thread and stalls animations.
                // The serial queue keeps the quick low-quality image ahead of the final one.
                decodeQueue.async {
                    if let image { continuation.yield(image.preparingForDisplay() ?? image) }
                    if !isDegraded || failed { continuation.finish() }
                }
            }
            continuation.onTermination = { _ in manager.cancelImageRequest(request) }
        }
    }

    func livePhoto(for asset: PHAsset, targetSize: CGSize) -> AsyncStream<PHLivePhoto> {
        let manager = manager
        return AsyncStream { continuation in
            let options = PHLivePhotoRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = true
            let request = manager.requestLivePhoto(for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options) { @Sendable livePhoto, info in
                if let livePhoto { continuation.yield(livePhoto) }
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded || info?[PHImageErrorKey] != nil { continuation.finish() }
            }
            continuation.onTermination = { _ in manager.cancelImageRequest(request) }
        }
    }

    func playerItem(for asset: PHAsset) async -> AVPlayerItem? {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        let item: UncheckedBox<AVPlayerItem>? = await withCheckedContinuation { continuation in
            manager.requestPlayerItem(forVideo: asset, options: options) { @Sendable item, _ in
                continuation.resume(returning: item.map(UncheckedBox.init))
            }
        }
        return item?.value
    }

    /// Writes each asset's original files (photo or video) to a temporary folder, for sharing.
    func exportOriginals(_ assets: [PHAsset]) async -> [URL] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Share-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var urls: [URL] = []
        for asset in assets {
            let resources = PHAssetResource.assetResources(for: asset)
            let preferred = resources.first { $0.type == .fullSizePhoto || $0.type == .fullSizeVideo }
                ?? resources.first { $0.type == .photo || $0.type == .video }
            guard let resource = preferred else { continue }
            let url = folder.appendingPathComponent(resource.originalFilename)
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            do {
                try await PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options)
                urls.append(url)
            } catch {
                continue
            }
        }
        return urls
    }
}

/// Carries a non-Sendable value across a callback that Photos guarantees not to touch again.
nonisolated struct UncheckedBox<Value>: @unchecked Sendable {
    let value: Value
}
