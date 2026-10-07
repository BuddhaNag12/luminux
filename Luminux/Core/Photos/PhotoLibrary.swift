import Photos
import PhotosUI
import UIKit

/// Where a grid or the viewer gets its assets from. Resolved against the library on every change.
enum AssetSource: Hashable {
    case all, favorites, videos, recent
    case album(String)
    /// A journal entry's photos, oldest first.
    case identifiers([String])
}

nonisolated struct Album: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let count: Int
    let keyAssetID: String?
    let isUserAlbum: Bool
}

/// PHFetchResult is immutable and safe to read from any thread.
nonisolated private struct FetchSnapshot: @unchecked Sendable {
    let all: PHFetchResult<PHAsset>
    let favorites: PHFetchResult<PHAsset>
    let videos: PHFetchResult<PHAsset>
    let recent: PHFetchResult<PHAsset>
    let sections: [MonthSection]
    let albums: [Album]
}

@Observable
final class PhotoLibrary: NSObject {
    enum Access: Equatable {
        case notDetermined, full, limited, denied

        init(_ status: PHAuthorizationStatus) {
            switch status {
            case .authorized: self = .full
            case .limited: self = .limited
            case .notDetermined: self = .notDetermined
            default: self = .denied
            }
        }

        var canRead: Bool { self == .full || self == .limited }
    }

    private(set) var access: Access
    private(set) var allAssets = PHFetchResult<PHAsset>()
    private(set) var favorites = PHFetchResult<PHAsset>()
    private(set) var videos = PHFetchResult<PHAsset>()
    /// Photos from the last 30 days, for the hub's "what's new".
    private(set) var recent = PHFetchResult<PHAsset>()
    private(set) var sections: [MonthSection] = []
    private(set) var albums: [Album] = []
    /// Bumps on every library change so views that resolve fetches lazily re-render.
    private(set) var changeToken = 0
    private(set) var isLoaded = false

    @ObservationIgnored private var isObserving = false
    @ObservationIgnored private var reloadGeneration = 0
    @ObservationIgnored private var albumCache: [String: PHFetchResult<PHAsset>] = [:]

    override init() {
        access = Access(PHPhotoLibrary.authorizationStatus(for: .readWrite))
        super.init()
        if access.canRead { start() }
    }

    func requestAccess() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        access = Access(status)
        if access.canRead { start() }
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func presentLimitedPicker() {
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
            .first
        else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: root)
    }

    func assets(in source: AssetSource) -> PHFetchResult<PHAsset> {
        _ = changeToken
        switch source {
        case .all: return allAssets
        case .favorites: return favorites
        case .videos: return videos
        case .recent: return recent
        case .album(let id):
            if let cached = albumCache[id] { return cached }
            guard let collection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject
            else { return PHFetchResult() }
            let result = PHAsset.fetchAssets(in: collection, options: Self.newestFirst())
            albumCache[id] = result
            return result
        case .identifiers(let ids):
            let key = ids.joined(separator: "|")
            if let cached = albumCache[key] { return cached }
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: options)
            albumCache[key] = result
            return result
        }
    }

    func album(id: String) -> Album? {
        albums.first { $0.id == id }
    }

    func asset(id: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    private func start() {
        if !isObserving {
            PHPhotoLibrary.shared().register(self)
            isObserving = true
        }
        reload()
    }

    private func reload() {
        reloadGeneration += 1
        let generation = reloadGeneration
        Task {
            let snapshot = await Task.detached(priority: .userInitiated) { Self.makeSnapshot() }.value
            guard generation == reloadGeneration else { return }
            allAssets = snapshot.all
            favorites = snapshot.favorites
            videos = snapshot.videos
            recent = snapshot.recent
            sections = snapshot.sections
            albums = snapshot.albums
            albumCache = [:]
            changeToken += 1
            isLoaded = true
        }
    }

    nonisolated private static func newestFirst(_ predicate: NSPredicate? = nil) -> PHFetchOptions {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = predicate
        return options
    }

    nonisolated private static func makeSnapshot() -> FetchSnapshot {
        let all = PHAsset.fetchAssets(with: newestFirst())
        var dates: [Date?] = []
        dates.reserveCapacity(all.count)
        all.enumerateObjects { asset, _, _ in dates.append(asset.creationDate) }

        let monthAgo = Date().addingTimeInterval(-30 * 24 * 3600)
        return FetchSnapshot(
            all: all,
            favorites: PHAsset.fetchAssets(with: newestFirst(NSPredicate(format: "favorite == YES"))),
            videos: PHAsset.fetchAssets(with: .video, options: newestFirst()),
            recent: PHAsset.fetchAssets(with: newestFirst(NSPredicate(format: "creationDate > %@", monthAgo as NSDate))),
            sections: MonthSection.group(dates),
            albums: fetchAlbums()
        )
    }

    nonisolated private static func fetchAlbums() -> [Album] {
        var albums: [Album] = []

        let user = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        user.enumerateObjects { collection, _, _ in
            if let album = makeAlbum(collection, isUserAlbum: true) { albums.append(album) }
        }

        let smartTypes: [PHAssetCollectionSubtype] = [
            .smartAlbumSelfPortraits, .smartAlbumLivePhotos, .smartAlbumDepthEffect,
            .smartAlbumPanoramas, .smartAlbumScreenshots, .smartAlbumBursts,
        ]
        for subtype in smartTypes {
            let result = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: subtype, options: nil)
            if let collection = result.firstObject, let album = makeAlbum(collection, isUserAlbum: false) {
                albums.append(album)
            }
        }
        return albums
    }

    nonisolated private static func makeAlbum(_ collection: PHAssetCollection, isUserAlbum: Bool) -> Album? {
        let assets = PHAsset.fetchAssets(in: collection, options: newestFirst())
        guard assets.count > 0 || isUserAlbum else { return nil }
        return Album(
            id: collection.localIdentifier,
            title: (collection.localizedTitle ?? "album").lowercased(),
            count: assets.count,
            keyAssetID: assets.firstObject?.localIdentifier,
            isUserAlbum: isUserAlbum
        )
    }
}

extension PhotoLibrary: PHPhotoLibraryChangeObserver {
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            access = Access(PHPhotoLibrary.authorizationStatus(for: .readWrite))
            reload()
        }
    }
}

// MARK: - Changes

/// Photos runs change blocks on its own queue, so every block is `@Sendable` and captures PhotoKit objects through a box.
extension PhotoLibrary {
    func setFavorite(_ assets: [PHAsset], _ isFavorite: Bool) async throws {
        let assets = UncheckedBox(value: assets)
        try await PHPhotoLibrary.shared().performChanges { @Sendable in
            for asset in assets.value {
                PHAssetChangeRequest(for: asset).isFavorite = isFavorite
            }
        }
    }

    /// iOS asks the person to confirm; deleted items go to Recently Deleted.
    func delete(_ assets: [PHAsset]) async throws {
        let assets = UncheckedBox(value: assets as NSArray)
        try await PHPhotoLibrary.shared().performChanges { @Sendable in
            PHAssetChangeRequest.deleteAssets(assets.value)
        }
    }

    func add(_ assets: [PHAsset], toAlbum id: String) async throws {
        guard let collection = Self.collection(id: id) else { return }
        let change = UncheckedBox(value: (collection, assets as NSArray))
        try await PHPhotoLibrary.shared().performChanges { @Sendable in
            PHAssetCollectionChangeRequest(for: change.value.0)?.addAssets(change.value.1)
        }
    }

    func remove(_ assets: [PHAsset], fromAlbum id: String) async throws {
        guard let collection = Self.collection(id: id) else { return }
        let change = UncheckedBox(value: (collection, assets as NSArray))
        try await PHPhotoLibrary.shared().performChanges { @Sendable in
            PHAssetCollectionChangeRequest(for: change.value.0)?.removeAssets(change.value.1)
        }
    }

    /// Returns the new album's identifier.
    @discardableResult
    func createAlbum(named title: String, with assets: [PHAsset] = []) async throws -> String? {
        let assets = UncheckedBox(value: assets as NSArray)
        let createdID = SendableReference<String?>(nil)
        try await PHPhotoLibrary.shared().performChanges { @Sendable in
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
            if assets.value.count > 0 { request.addAssets(assets.value) }
            createdID.value = request.placeholderForCreatedAssetCollection.localIdentifier
        }
        return createdID.value
    }

    func renameAlbum(id: String, to title: String) async throws {
        guard let collection = Self.collection(id: id) else { return }
        let box = UncheckedBox(value: collection)
        try await PHPhotoLibrary.shared().performChanges { @Sendable in
            PHAssetCollectionChangeRequest(for: box.value)?.title = title
        }
    }

    /// Deletes the album only; its photos stay in the library.
    func deleteAlbum(id: String) async throws {
        let collections = UncheckedBox(value: PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil))
        try await PHPhotoLibrary.shared().performChanges { @Sendable in
            PHAssetCollectionChangeRequest.deleteAssetCollections(collections.value)
        }
    }

    private static func collection(id: String) -> PHAssetCollection? {
        PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject
    }
}

/// Lets a `@Sendable` change block hand a value back; Photos finishes the block before `performChanges` returns.
nonisolated final class SendableReference<Value>: @unchecked Sendable {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}
