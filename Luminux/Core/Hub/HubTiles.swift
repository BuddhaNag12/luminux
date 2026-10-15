import CoreGraphics
import Foundation
import Observation

/// What a tile on the hub's collection panel shows and opens.
nonisolated enum HubTileKind: Codable, Hashable, Sendable {
    case cameraRoll, albums, date, favorites, places
    case album(String)
    /// Photos picked in select mode and pinned together.
    case photoSet(String)

    /// The four tiles the hub ships with; they can be moved and resized but not unpinned.
    var isBuiltIn: Bool {
        switch self {
        case .cameraRoll, .albums, .date, .favorites, .places: true
        case .album, .photoSet: false
        }
    }
}

/// Windows Phone's three tile sizes on a grid four cells wide: a small tile is one cell, a medium tile a 2×2 block
/// and a wide tile the whole row, two cells tall.
nonisolated enum HubTileSize: String, Codable, CaseIterable, Sendable {
    case small, medium, wide

    var width: Int {
        switch self {
        case .small: 1
        case .medium: 2
        case .wide: 4
        }
    }

    var height: Int { self == .small ? 1 : 2 }

    /// The resize button steps medium → small → wide → medium, like the original.
    var next: HubTileSize {
        switch self {
        case .medium: .small
        case .small: .wide
        case .wide: .medium
        }
    }
}

nonisolated struct HubTile: Codable, Hashable, Identifiable, Sendable {
    var kind: HubTileKind
    var size: HubTileSize = .medium

    var id: HubTileKind { kind }
}

nonisolated struct PhotoSet: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var title: String
    var photoIDs: [String]
}

/// The collection panel's tiles in order, and the photo sets pinned there. Kept on the phone in
/// `Application Support/hub.json`.
@Observable
final class HubTiles {
    /// Albums and photo sets pinned without Pro; Pro pins as many as you like.
    static let freePinLimit = 2

    static let defaultTiles: [HubTile] = [
        HubTile(kind: .cameraRoll), HubTile(kind: .albums), HubTile(kind: .date), HubTile(kind: .favorites),
        HubTile(kind: .places),
    ]

    private(set) var tiles: [HubTile] = HubTiles.defaultTiles
    private(set) var photoSets: [String: PhotoSet] = [:]

    @ObservationIgnored private let storeURL: URL?

    private struct Store: Codable {
        var tiles: [HubTile]
        var photoSets: [String: PhotoSet]
    }

    init(storeURL: URL? = HubTiles.defaultStoreURL) {
        self.storeURL = storeURL
        if let storeURL, let data = try? Data(contentsOf: storeURL), let store = try? JSONDecoder().decode(Store.self, from: data) {
            tiles = store.tiles
            photoSets = store.photoSets
            // A built-in tile is never lost, even from a damaged file.
            for tile in Self.defaultTiles where !tiles.contains(where: { $0.kind == tile.kind }) {
                tiles.append(tile)
            }
        }
    }

    static var defaultStoreURL: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("hub.json")
    }

    /// Albums and photo sets on the panel; the built-in tiles don't count.
    var pinCount: Int { tiles.count { !$0.kind.isBuiltIn } }

    func canPin(isPro: Bool) -> Bool {
        isPro || pinCount < Self.freePinLimit
    }

    func isPinned(_ kind: HubTileKind) -> Bool {
        tiles.contains { $0.kind == kind }
    }

    func photoSet(id: String) -> PhotoSet? {
        photoSets[id]
    }

    func pinAlbum(_ id: String) {
        guard !isPinned(.album(id)) else { return }
        tiles.append(HubTile(kind: .album(id)))
        save()
    }

    /// Returns the new set's id. An empty title becomes "photos".
    @discardableResult
    func pinPhotoSet(title: String, photoIDs: [String]) -> String {
        let id = UUID().uuidString
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        photoSets[id] = PhotoSet(id: id, title: trimmed.isEmpty ? "photos" : trimmed.lowercased(), photoIDs: photoIDs)
        tiles.append(HubTile(kind: .photoSet(id)))
        save()
        return id
    }

    /// Built-in tiles stay. A photo set only lives on its tile, so unpinning one forgets it.
    func unpin(_ kind: HubTileKind) {
        guard !kind.isBuiltIn else { return }
        tiles.removeAll { $0.kind == kind }
        if case .photoSet(let id) = kind { photoSets[id] = nil }
        save()
    }

    func move(_ kind: HubTileKind, to index: Int) {
        guard let from = tiles.firstIndex(where: { $0.kind == kind }) else { return }
        let tile = tiles.remove(at: from)
        tiles.insert(tile, at: min(max(index, 0), tiles.count))
        save()
    }

    func resize(_ kind: HubTileKind) {
        guard let index = tiles.firstIndex(where: { $0.kind == kind }) else { return }
        tiles[index].size = tiles[index].size.next
        save()
    }

    /// An empty title keeps the old one.
    func rename(set id: String, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, photoSets[id] != nil else { return }
        photoSets[id]?.title = trimmed.lowercased()
        save()
    }

    func remove(_ photoIDs: Set<String>, fromSet id: String) {
        guard photoSets[id] != nil else { return }
        photoSets[id]?.photoIDs.removeAll { photoIDs.contains($0) }
        save()
    }

    /// Drops tiles for albums that are gone from the library.
    func prune(albumIDs: Set<String>) {
        let before = tiles.count
        tiles.removeAll { tile in
            if case .album(let id) = tile.kind { return !albumIDs.contains(id) }
            return false
        }
        if tiles.count != before { save() }
    }

    private func save() {
        guard let storeURL else { return }
        if let data = try? JSONEncoder().encode(Store(tiles: tiles, photoSets: photoSets)) {
            try? data.write(to: storeURL, options: .atomic)
        }
    }
}

/// Where a tile sits on the four-cell grid, in cells.
nonisolated struct TilePlacement: Equatable, Sendable {
    let column: Int
    let row: Int
    let width: Int
    let height: Int
}

/// Packs tiles the way the Windows Phone start screen did: in order, each in the first place it fits, with medium
/// and wide tiles on whole 2×2 blocks so small tiles fill in the corners around them.
nonisolated enum TilePacking {
    static let columns = 4

    static func place(_ sizes: [HubTileSize]) -> [TilePlacement] {
        var taken = Set<Int>()
        func cell(_ column: Int, _ row: Int) -> Int { row * columns + column }

        return sizes.map { size in
            let step = size == .small ? 1 : 2
            var row = 0
            while true {
                for column in stride(from: 0, through: columns - size.width, by: step) {
                    let cells = (row..<row + size.height).flatMap { r in (column..<column + size.width).map { cell($0, r) } }
                    if cells.allSatisfy({ !taken.contains($0) }) {
                        taken.formUnion(cells)
                        return TilePlacement(column: column, row: row, width: size.width, height: size.height)
                    }
                }
                row += step
            }
        }
    }

    static func rows(_ placements: [TilePlacement]) -> Int {
        placements.map { $0.row + $0.height }.max() ?? 0
    }

    static func cellSide(width: CGFloat, spacing: CGFloat) -> CGFloat {
        max((width - spacing * CGFloat(columns - 1)) / CGFloat(columns), 0)
    }

    /// Where a dragged tile should go: the position whose packed slot sits closest to where the tile is held. Every
    /// candidate is judged after the reflow it would cause, and the tile only leaves its current slot for one that's
    /// clearly closer, so it can't flip back and forth while the other tiles move underneath it.
    static func dropIndex(for held: CGRect, sizes: [HubTileSize], moving: Int, width: CGFloat, spacing: CGFloat) -> Int {
        guard sizes.indices.contains(moving) else { return moving }
        func distance(at index: Int) -> CGFloat {
            var order = sizes
            let size = order.remove(at: moving)
            order.insert(size, at: index)
            let slot = frame(for: place(order)[index], width: width, spacing: spacing)
            return hypot(slot.midX - held.midX, slot.midY - held.midY)
        }
        let current = distance(at: moving)
        let best = sizes.indices.map { (index: $0, distance: distance(at: $0)) }.min { $0.distance < $1.distance }!
        // A quarter of a cell closer before it moves.
        let margin = cellSide(width: width, spacing: spacing) / 4
        return best.distance < current - margin ? best.index : moving
    }

    static func frame(for placement: TilePlacement, width: CGFloat, spacing: CGFloat) -> CGRect {
        let side = cellSide(width: width, spacing: spacing)
        let step = side + spacing
        return CGRect(
            x: CGFloat(placement.column) * step,
            y: CGFloat(placement.row) * step,
            width: CGFloat(placement.width) * step - spacing,
            height: CGFloat(placement.height) * step - spacing
        )
    }
}
