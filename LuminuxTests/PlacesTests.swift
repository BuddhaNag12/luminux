import Foundation
import Testing
@testable import Luminux

struct PlacesTests {
    private func point(_ id: String, _ lat: Double?, _ lon: Double?, daysAgo: Double) -> PhotoPoint {
        PhotoPoint(
            id: id,
            date: Date(timeIntervalSince1970: 1_700_000_000 - daysAgo * 86_400),
            coordinate: lat.map { Coordinate(latitude: $0, longitude: lon!) },
            isFavorite: false
        )
    }

    // Two photos a few hundred metres apart in Goa, one in Mumbai, one with no location.
    private var points: [PhotoPoint] {
        [
            point("goa-old", 15.501, 73.811, daysAgo: 30),
            point("goa-new", 15.503, 73.814, daysAgo: 20),
            point("mumbai", 19.076, 72.877, daysAgo: 1),
            point("nowhere", nil, nil, daysAgo: 0),
        ]
    }

    @Test func groupsNearbyPhotosAndSkipsOnesWithoutALocation() {
        let places = PlaceGrouping.places(from: points)
        #expect(places.count == 2)
        #expect(places.flatMap(\.photoIDs).contains("nowhere") == false)
    }

    @Test func mostRecentlyVisitedFirstAndNewestPhotoFirst() {
        let places = PlaceGrouping.places(from: points)
        #expect(places.map(\.photoIDs) == [["mumbai"], ["goa-new", "goa-old"]])
    }

    @Test func zoomedOutPlacesMergeIntoOneBubble() {
        let places = PlaceGrouping.places(from: points)
        // Showing about the whole country: Goa and Mumbai share a bubble.
        let wide = PlaceGrouping.clusters(places, span: 40)
        #expect(wide.count == 1)
        #expect(wide[0].count == 3)
        #expect(wide[0].lead.photoIDs == ["mumbai"])
        // Zoomed in to a city: separate bubbles.
        #expect(PlaceGrouping.clusters(places, span: 1).count == 2)
    }

    @Test func theMapFramesEveryPlace() {
        let region = PlaceGrouping.region(showing: PlaceGrouping.places(from: points))!
        #expect(region.span.latitudeDelta > 19.076 - 15.501)
        #expect(abs(region.center.latitude - (19.076 + 15.502) / 2) < 0.1)
    }
}
