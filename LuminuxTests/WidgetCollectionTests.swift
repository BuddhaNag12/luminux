import Foundation
import Testing
@testable import Luminux

struct WidgetCollectionTests {
    @Test func albumIdsBecomeSafeFolderNames() {
        let album = LiveTileStore.Collection.album("6B1F2C/L0/040", title: "Waterfalls")
        #expect(album.id == "album:6B1F2C/L0/040")
        #expect(album.folderName == "c-album-6B1F2C-L0-040")
        #expect(!album.folderName.contains("/"))
    }

    @Test func photoSetsGetTheirOwnPrefix() {
        #expect(LiveTileStore.Collection.photoSet("A1", title: "Goa").id == "set:A1")
    }

    @Test func collectionsRoundTrip() throws {
        let collections = [LiveTileStore.Collection.album("x/y", title: "Trip"), .photoSet("s", title: "Best")]
        let decoded = try JSONDecoder().decode([LiveTileStore.Collection].self, from: JSONEncoder().encode(collections))
        #expect(decoded == collections)
    }
}
