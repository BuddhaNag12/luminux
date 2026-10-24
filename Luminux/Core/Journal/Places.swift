import Foundation
import MapKit

/// Photos taken in roughly the same spot: one ~5 km cell of the same grid the journal names its trips on.
nonisolated struct Place: Identifiable, Hashable, Sendable {
    /// The grid cell, e.g. "301,1557".
    let id: String
    /// The average of its photos' locations.
    let center: Coordinate
    /// Newest first.
    let photoIDs: [String]
    let latest: Date

    var count: Int { photoIDs.count }
}

/// Several nearby places drawn as one bubble on the map when it's zoomed out.
nonisolated struct PlaceCluster: Identifiable, Hashable, Sendable {
    let places: [Place]

    var id: String { places.map(\.id).joined(separator: "|") }
    var count: Int { places.reduce(0) { $0 + $1.count } }
    /// The newest place leads, so its newest photo is the bubble's picture.
    var lead: Place { places.max { $0.latest < $1.latest }! }

    var center: Coordinate {
        let total = Double(count)
        return Coordinate(
            latitude: places.reduce(0) { $0 + $1.center.latitude * Double($1.count) } / total,
            longitude: places.reduce(0) { $0 + $1.center.longitude * Double($1.count) } / total
        )
    }
}

nonisolated enum PlaceGrouping {
    /// The size of a place in degrees, about 5 km.
    static let cellSize = 0.05

    /// Groups the photos that have a location into places, the most recently visited first.
    static func places(from points: [PhotoPoint]) -> [Place] {
        var cells: [String: [PhotoPoint]] = [:]
        for point in points {
            guard let coordinate = point.coordinate else { continue }
            cells[JournalBuilder.cellKey(coordinate, size: cellSize), default: []].append(point)
        }
        return cells.map { key, points in
            let sorted = points.sorted { $0.date > $1.date }
            let count = Double(points.count)
            let center = Coordinate(
                latitude: points.reduce(0) { $0 + $1.coordinate!.latitude } / count,
                longitude: points.reduce(0) { $0 + $1.coordinate!.longitude } / count
            )
            return Place(id: key, center: center, photoIDs: sorted.map(\.id), latest: sorted[0].date)
        }
        .sorted { $0.latest > $1.latest }
    }

    /// Merges places that would overlap on a map showing `span` degrees of latitude: about an eighth of the map's
    /// height per bubble.
    static func clusters(_ places: [Place], span: Double) -> [PlaceCluster] {
        let size = max(span / 8, cellSize)
        var cells: [String: [Place]] = [:]
        for place in places {
            cells[JournalBuilder.cellKey(place.center, size: size), default: []].append(place)
        }
        return cells.values.map(PlaceCluster.init).sorted { $0.lead.latest > $1.lead.latest }
    }

    /// A region showing every place, with a little room around the edges.
    static func region(showing places: [Place]) -> MKCoordinateRegion? {
        guard let first = places.first else { return nil }
        var minLat = first.center.latitude, maxLat = minLat, minLon = first.center.longitude, maxLon = minLon
        for place in places {
            minLat = min(minLat, place.center.latitude); maxLat = max(maxLat, place.center.latitude)
            minLon = min(minLon, place.center.longitude); maxLon = max(maxLon, place.center.longitude)
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.4, 0.2), longitudeDelta: max((maxLon - minLon) * 1.4, 0.2))
        )
    }

    /// The photos of every place on a map showing `region`, most recently visited place first.
    static func photoIDs(in region: MKCoordinateRegion, places: [Place]) -> [String] {
        places.filter { place in
            let latitude = abs(place.center.latitude - region.center.latitude)
            // Across the date line too: the shorter way round.
            let longitude = abs((place.center.longitude - region.center.longitude + 540).truncatingRemainder(dividingBy: 360) - 180)
            return latitude <= region.span.latitudeDelta / 2 && longitude <= region.span.longitudeDelta / 2
        }
        .flatMap(\.photoIDs)
    }
}
