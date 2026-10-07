import Foundation

nonisolated struct Coordinate: Hashable, Codable, Sendable {
    let latitude: Double
    let longitude: Double

    /// Great-circle distance in metres.
    func distance(to other: Coordinate) -> Double {
        let radius = 6_371_000.0
        let lat1 = latitude * .pi / 180, lat2 = other.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (other.longitude - longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return radius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

/// What the journal needs to know about a photo, read off the main thread.
nonisolated struct PhotoPoint: Hashable, Sendable {
    let id: String
    let date: Date
    let coordinate: Coordinate?
    let isFavorite: Bool
}

nonisolated struct JournalEntry: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// One outing: photos close together in time and place.
        case moment
        /// A day's scattered photos that don't make a moment on their own.
        case day
        /// Consecutive days far from home.
        case trip
    }

    /// The first photo's id, so renames and notes survive rebuilds.
    let id: String
    let kind: Kind
    let start: Date
    let end: Date
    /// Oldest first.
    let photoIDs: [String]
    let favoriteIDs: [String]
    /// Where most of the entry's photos were taken.
    let center: Coordinate?
    /// Far enough from home to be worth naming the place.
    let isAway: Bool
}

/// Groups a library into journal entries the way Photos and Journal suggest them: outings, days and trips.
nonisolated enum JournalBuilder {
    /// A gap this long, or a move this far, starts a new moment.
    static let momentGap: TimeInterval = 3 * 3600
    static let momentDistance: Double = 25_000
    /// Photos this far from home count as away.
    static let awayDistance: Double = 50_000
    static let minimumPhotos = 3

    /// Newest first.
    static func entries(from points: [PhotoPoint], calendar: Calendar = .current) -> [JournalEntry] {
        let sorted = points.sorted { $0.date < $1.date }
        let home = homePlace(of: sorted, calendar: calendar)
        func isAway(_ point: PhotoPoint) -> Bool {
            guard let home, let coordinate = point.coordinate else { return false }
            return coordinate.distance(to: home) > awayDistance
        }

        let days = Dictionary(grouping: sorted) { calendar.startOfDay(for: $0.date) }
        let awayDays = Set(days.compactMap { day, points -> Date? in
            let located = points.filter { $0.coordinate != nil }
            guard !located.isEmpty else { return nil }
            return located.filter(isAway).count * 2 > located.count ? day : nil
        })

        var entries: [JournalEntry] = []
        var tripDays = Set<Date>()
        for run in runs(of: awayDays.sorted(), calendar: calendar) where run.count >= 2 {
            let photos = run.flatMap { days[$0] ?? [] }
            guard photos.count >= minimumPhotos else { continue }
            tripDays.formUnion(run)
            entries.append(entry(.trip, photos, isAway: true))
        }

        let rest = sorted.filter { !tripDays.contains(calendar.startOfDay(for: $0.date)) }
        var leftovers: [Date: [PhotoPoint]] = [:]
        var daysWithMoments = Set<Date>()
        for moment in moments(in: rest) {
            let day = calendar.startOfDay(for: moment[0].date)
            if moment.count >= minimumPhotos {
                daysWithMoments.insert(day)
                entries.append(entry(.moment, moment, isAway: moment.filter(isAway).count * 2 > moment.count))
            } else {
                leftovers[day, default: []].append(contentsOf: moment)
            }
        }
        // Stray photos only make an entry on a day that has nothing else to show.
        for (day, photos) in leftovers where !daysWithMoments.contains(day) && photos.count >= minimumPhotos {
            entries.append(entry(.day, photos, isAway: photos.filter(isAway).count * 2 > photos.count))
        }

        return entries.sorted { $0.start > $1.start }
    }

    /// Home is where photos are taken on the most different days. Counting photos instead would let one busy trip
    /// outweigh months of everyday shots.
    static func homePlace(of points: [PhotoPoint], calendar: Calendar) -> Coordinate? {
        var days: [String: Set<Date>] = [:]
        var coordinates: [String: [Coordinate]] = [:]
        for point in points {
            guard let coordinate = point.coordinate else { continue }
            let key = cellKey(coordinate, size: 0.1)
            days[key, default: []].insert(calendar.startOfDay(for: point.date))
            coordinates[key, default: []].append(coordinate)
        }
        guard let key = days.max(by: { $0.value.count < $1.value.count })?.key else { return nil }
        return mostCommonPlace(in: coordinates[key] ?? [])
    }

    /// The centre of the ~11 km cell holding the most photos, such as a trip's main stop.
    static func mostCommonPlace(in coordinates: [Coordinate]) -> Coordinate? {
        guard !coordinates.isEmpty else { return nil }
        let cells = Dictionary(grouping: coordinates) { cellKey($0, size: 0.1) }
        guard let busiest = cells.values.max(by: { $0.count < $1.count }) else { return nil }
        return Coordinate(
            latitude: busiest.map(\.latitude).reduce(0, +) / Double(busiest.count),
            longitude: busiest.map(\.longitude).reduce(0, +) / Double(busiest.count)
        )
    }

    static func cellKey(_ coordinate: Coordinate, size: Double) -> String {
        let lat = (coordinate.latitude / size).rounded(.down)
        let lon = (coordinate.longitude / size).rounded(.down)
        return "\(Int(lat)),\(Int(lon))"
    }

    private static func moments(in points: [PhotoPoint]) -> [[PhotoPoint]] {
        var moments: [[PhotoPoint]] = []
        var current: [PhotoPoint] = []
        var anchor: Coordinate?
        for point in points {
            if let last = current.last {
                let isLate = point.date.timeIntervalSince(last.date) > momentGap
                let isFar = both(anchor, point.coordinate).map { $0.distance(to: $1) > momentDistance } ?? false
                if isLate || isFar {
                    moments.append(current)
                    current = []
                    anchor = nil
                }
            }
            current.append(point)
            anchor = anchor ?? point.coordinate
        }
        if !current.isEmpty { moments.append(current) }
        return moments
    }

    /// Consecutive days, allowing one day without photos in between.
    private static func runs(of days: [Date], calendar: Calendar) -> [[Date]] {
        var runs: [[Date]] = []
        for day in days {
            if let last = runs.last?.last, let gap = calendar.dateComponents([.day], from: last, to: day).day, gap <= 2 {
                runs[runs.count - 1].append(day)
            } else {
                runs.append([day])
            }
        }
        return runs
    }

    private static func entry(_ kind: JournalEntry.Kind, _ photos: [PhotoPoint], isAway: Bool) -> JournalEntry {
        let ordered = photos.sorted { $0.date < $1.date }
        return JournalEntry(
            id: ordered[0].id,
            kind: kind,
            start: ordered[0].date,
            end: ordered[ordered.count - 1].date,
            photoIDs: ordered.map(\.id),
            favoriteIDs: ordered.filter(\.isFavorite).map(\.id),
            center: mostCommonPlace(in: ordered.compactMap(\.coordinate)),
            isAway: isAway
        )
    }
}

private nonisolated func both<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
    guard let a, let b else { return nil }
    return (a, b)
}
