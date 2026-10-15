import Foundation
import Testing
@testable import Luminux

struct HubTilesTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("hub-\(UUID().uuidString).json")
    }

    @Test func startsWithTheBuiltInTiles() {
        let tiles = HubTiles(storeURL: nil)

        #expect(tiles.tiles.map(\.kind) == [.cameraRoll, .albums, .date, .favorites, .places])
        #expect(tiles.tiles.allSatisfy { $0.size == .medium })
        #expect(tiles.pinCount == 0)
    }

    @Test func freeUsersPinTwoThenPro() {
        let tiles = HubTiles(storeURL: nil)
        tiles.pinAlbum("a")
        #expect(tiles.canPin(isPro: false))
        tiles.pinPhotoSet(title: "beach", photoIDs: ["p1", "p2"])

        #expect(tiles.pinCount == 2)
        #expect(!tiles.canPin(isPro: false))
        #expect(tiles.canPin(isPro: true))
    }

    @Test func anAlbumIsPinnedOnce() {
        let tiles = HubTiles(storeURL: nil)
        tiles.pinAlbum("a")
        tiles.pinAlbum("a")

        #expect(tiles.pinCount == 1)
        #expect(tiles.isPinned(.album("a")))
    }

    @Test func builtInTilesCantBeUnpinned() {
        let tiles = HubTiles(storeURL: nil)
        tiles.unpin(.favorites)

        #expect(tiles.isPinned(.favorites))
    }

    @Test func unpinningASetForgetsIt() {
        let tiles = HubTiles(storeURL: nil)
        let id = tiles.pinPhotoSet(title: "Beach ", photoIDs: ["p1"])
        #expect(tiles.photoSet(id: id)?.title == "beach")

        tiles.unpin(.photoSet(id))

        #expect(tiles.photoSet(id: id) == nil)
        #expect(!tiles.isPinned(.photoSet(id)))
    }

    @Test func anUnnamedSetIsCalledPhotos() {
        let tiles = HubTiles(storeURL: nil)
        let id = tiles.pinPhotoSet(title: "  ", photoIDs: ["p1"])

        #expect(tiles.photoSet(id: id)?.title == "photos")
    }

    @Test func movingATileTakesTheTargetsPlace() {
        let tiles = HubTiles(storeURL: nil)
        tiles.move(.favorites, to: 0)
        #expect(tiles.tiles.map(\.kind) == [.favorites, .cameraRoll, .albums, .date, .places])

        tiles.move(.favorites, to: 3)
        #expect(tiles.tiles.map(\.kind) == [.cameraRoll, .albums, .date, .favorites, .places])
    }

    @Test func resizeStepsMediumSmallWide() {
        let tiles = HubTiles(storeURL: nil)
        tiles.resize(.date)
        #expect(tiles.tiles[2].size == .small)
        tiles.resize(.date)
        #expect(tiles.tiles[2].size == .wide)
        tiles.resize(.date)
        #expect(tiles.tiles[2].size == .medium)
    }

    @Test func removingPhotosAndRenamingASet() {
        let tiles = HubTiles(storeURL: nil)
        let id = tiles.pinPhotoSet(title: "trip", photoIDs: ["p1", "p2", "p3"])
        tiles.remove(["p2"], fromSet: id)
        tiles.rename(set: id, to: "Road Trip")
        tiles.rename(set: id, to: "")

        #expect(tiles.photoSet(id: id)?.photoIDs == ["p1", "p3"])
        #expect(tiles.photoSet(id: id)?.title == "road trip")
    }

    @Test func deletedAlbumsArePruned() {
        let tiles = HubTiles(storeURL: nil)
        tiles.pinAlbum("kept")
        tiles.pinAlbum("gone")
        tiles.prune(albumIDs: ["kept"])

        #expect(tiles.isPinned(.album("kept")))
        #expect(!tiles.isPinned(.album("gone")))
        #expect(tiles.isPinned(.cameraRoll))
    }

    @Test func layoutSurvivesARelaunch() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let tiles = HubTiles(storeURL: url)
        let id = tiles.pinPhotoSet(title: "beach", photoIDs: ["p1"])
        tiles.pinAlbum("a")
        tiles.resize(.album("a"))
        tiles.move(.photoSet(id), to: 0)

        let reloaded = HubTiles(storeURL: url)

        #expect(reloaded.tiles == tiles.tiles)
        #expect(reloaded.photoSet(id: id)?.photoIDs == ["p1"])
    }
}

struct TilePackingTests {
    private func placement(_ column: Int, _ row: Int, _ size: HubTileSize) -> TilePlacement {
        TilePlacement(column: column, row: row, width: size.width, height: size.height)
    }

    @Test func mediumTilesMakeTwoColumns() {
        let placements = TilePacking.place([.medium, .medium, .medium])

        #expect(placements == [placement(0, 0, .medium), placement(2, 0, .medium), placement(0, 2, .medium)])
        #expect(TilePacking.rows(placements) == 4)
    }

    @Test func smallTilesFillABlockBeforeTheNextMedium() {
        let placements = TilePacking.place([.small, .small, .small, .medium, .small])

        #expect(placements == [
            placement(0, 0, .small), placement(1, 0, .small), placement(2, 0, .small),
            placement(0, 2, .medium),
            placement(3, 0, .small),
        ])
    }

    @Test func mediumTilesStayOnWholeBlocks() {
        // A medium never straddles two blocks, even where it would fit.
        let placements = TilePacking.place([.small, .medium])

        #expect(placements[1] == placement(2, 0, .medium))
    }

    @Test func wideTilesTakeAWholeRow() {
        let placements = TilePacking.place([.medium, .wide, .medium])

        #expect(placements == [placement(0, 0, .medium), placement(0, 2, .wide), placement(2, 0, .medium)])
    }

    @Test func framesIncludeTheGutters() {
        let frame = TilePacking.frame(for: placement(2, 0, .medium), width: 412, spacing: 4)

        #expect(frame == CGRect(x: 208, y: 0, width: 204, height: 204))
    }

    // The default hub on a 400 pt wide grid with no gaps (100 pt cells): favorites and camera roll side by side on
    // top (rows 0-1), the wide date tile below (rows 2-3), then albums and a pinned set.
    private let sizes: [HubTileSize] = [.medium, .medium, .wide, .medium, .medium]
    private func drop(_ held: CGRect, moving: Int) -> Int {
        TilePacking.dropIndex(for: held, sizes: sizes, moving: moving, width: 400, spacing: 0)
    }

    @Test func aBigTileLandsWhereItIsHeld() {
        // The wide tile dragged up over the top row.
        #expect(drop(CGRect(x: 0, y: 40, width: 400, height: 200), moving: 2) == 0)
    }

    @Test func aSlowDragMovesOnceAndDoesNotFlipBack() {
        // Favorites dragged down 10 pt at a time until it's below the wide tile, moving whenever the rule says so.
        var order = sizes
        var moving = 0
        var moves = 0
        for y in stride(from: 0, through: 300, by: 10) {
            let index = TilePacking.dropIndex(for: CGRect(x: 0, y: CGFloat(y), width: 200, height: 200), sizes: order, moving: moving, width: 400, spacing: 0)
            if index != moving {
                let size = order.remove(at: moving)
                order.insert(size, at: index)
                moving = index
                moves += 1
            }
        }
        #expect(moves == 1)
        // It ends up under the wide tile, on the left.
        let slot = TilePacking.frame(for: TilePacking.place(order)[moving], width: 400, spacing: 0)
        #expect(slot.origin == CGPoint(x: 0, y: 400))
    }

    @Test func aSmallNudgeLeavesTheOrderAlone() {
        #expect(drop(CGRect(x: 10, y: 10, width: 200, height: 200), moving: 0) == 0)
    }
}
