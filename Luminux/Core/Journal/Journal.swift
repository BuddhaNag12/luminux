import CoreLocation
import MapKit
import Photos
import Vision

nonisolated struct JournalNote: Codable, Hashable, Sendable {
    var title: String?
    var text: String?
}

/// The journal: entries built from the library, your titles and notes, and place names looked up for trips and
/// outings away from home.
@Observable
final class Journal {
    private(set) var entries: [JournalEntry] = []
    /// Every place photos were taken, the most recently visited first; built from the same scan as the entries.
    private(set) var places: [Place] = []
    private(set) var isBuilt = false
    /// Off when place names are turned off in settings; names already looked up stay cached but hidden.
    var usesPlaceNames = true
    private var notes: [String: JournalNote] = [:]
    private var placeNames: [String: String] = [:]
    /// Each entry's best photos, best first, once scored.
    private var keyPhotoPicks: [String: [String]] = [:]
    /// Entry ids are their first photo's id, so deleting that photo renames the entry; old id → the entry that took over.
    @ObservationIgnored private var successors: [String: String] = [:]

    @ObservationIgnored private var failedPlaces = Set<String>()
    @ObservationIgnored private var scoring = Set<String>()
    @ObservationIgnored private let storeURL: URL?

    private struct Store: Codable {
        var notes: [String: JournalNote] = [:]
        var placeNames: [String: String] = [:]
    }

    init(storeURL: URL? = Journal.defaultStoreURL) {
        self.storeURL = storeURL
        if let storeURL, let data = try? Data(contentsOf: storeURL), let store = try? JSONDecoder().decode(Store.self, from: data) {
            notes = store.notes
            placeNames = store.placeNames
        }
    }

    static var defaultStoreURL: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("journal.json")
    }

    /// Follows an entry whose first photo was deleted to the entry that now holds its photos.
    func entry(id: String) -> JournalEntry? {
        var id = id
        for _ in 0...successors.count {
            if let entry = entries.first(where: { $0.id == id }) { return entry }
            guard let next = successors[id] else { return nil }
            id = next
        }
        return nil
    }

    func title(for entry: JournalEntry) -> String {
        if let custom = notes[entry.id]?.title, !custom.isEmpty { return custom }
        return JournalTitles.title(for: entry, place: place(for: entry))
    }

    func subtitle(for entry: JournalEntry) -> String {
        JournalTitles.subtitle(for: entry)
    }

    func note(for entry: JournalEntry) -> String? {
        notes[entry.id]?.text.flatMap { $0.isEmpty ? nil : $0 }
    }

    func place(for entry: JournalEntry) -> String? {
        guard usesPlaceNames else { return nil }
        return entry.center.flatMap { placeNames[Self.placeKey($0)] }
    }

    /// The photos to lead an entry with. Until they're scored: favourites, then an even spread through the entry.
    func keyPhotos(for entry: JournalEntry, count: Int) -> [String] {
        if let picks = keyPhotoPicks[entry.id] { return Array(picks.prefix(count)) }
        return Array((entry.favoriteIDs + Self.spread(entry.photoIDs, count: count)).uniqued().prefix(count))
    }

    /// Scores a sample of the entry's photos with Vision's on-device aesthetics model. Favourites get a head start;
    /// utility shots (receipts, documents, whiteboards) go last.
    func scoreKeyPhotos(for entry: JournalEntry) async {
        guard keyPhotoPicks[entry.id] == nil, scoring.insert(entry.id).inserted else { return }
        defer { scoring.remove(entry.id) }
        let candidates = (entry.favoriteIDs + Self.spread(entry.photoIDs, count: 12)).uniqued()
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: candidates, options: nil)
        var scores: [String: Float] = [:]
        for index in 0..<assets.count {
            guard !Task.isCancelled else { return }
            let asset = assets.object(at: index)
            let bonus: Float = asset.isFavorite ? 0.5 : 0
            guard asset.mediaType == .image else {
                scores[asset.localIdentifier] = bonus - 0.2
                continue
            }
            var image: UIImage?
            for await next in ImageLoader.shared.images(for: asset, targetSize: CGSize(width: 360, height: 360)) {
                image = next
            }
            guard let cgImage = image?.cgImage,
                  let observation = try? await CalculateImageAestheticsScoresRequest().perform(on: cgImage, orientation: nil)
            else {
                scores[asset.localIdentifier] = bonus
                continue
            }
            scores[asset.localIdentifier] = observation.overallScore + bonus - (observation.isUtility ? 2 : 0)
        }
        keyPhotoPicks[entry.id] = candidates.sorted { (scores[$0] ?? -9) > (scores[$1] ?? -9) }
    }

    /// `count` ids evenly spaced through the list, so a long trip isn't represented by its first hour.
    static func spread(_ ids: [String], count: Int) -> [String] {
        guard ids.count > count, count > 1 else { return Array(ids.prefix(count)) }
        let step = Double(ids.count - 1) / Double(count - 1)
        return (0..<count).map { ids[Int((Double($0) * step).rounded())] }
    }

    /// An empty title goes back to the generated one.
    func rename(_ entry: JournalEntry, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        notes[entry.id, default: JournalNote()].title = trimmed.isEmpty ? nil : trimmed
        save()
    }

    func setNote(_ text: String, for entry: JournalEntry) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        notes[entry.id, default: JournalNote()].text = trimmed.isEmpty ? nil : trimmed
        save()
    }

    /// Regroups the whole library off the main thread.
    func rebuild() async {
        let built = await Task.detached(priority: .utility) {
            let points = Self.loadPoints()
            return (JournalBuilder.entries(from: points), PlaceGrouping.places(from: points))
        }.value
        let previous = entries
        entries = built.0
        places = built.1
        isBuilt = true
        carryOver(from: previous)
    }

    /// An entry that lost its first photo comes back under a new id; its title and note move with it.
    private func carryOver(from previous: [JournalEntry]) {
        var moved = false
        for (old, new) in Self.successors(of: previous, in: entries) {
            successors[old] = new
            if notes[new] == nil, let note = notes.removeValue(forKey: old) {
                notes[new] = note
                moved = true
            }
        }
        if moved { save() }
    }

    /// Old id → new id for each entry that's gone but whose photos live on in another entry.
    static func successors(of previous: [JournalEntry], in current: [JournalEntry]) -> [String: String] {
        let currentIDs = Set(current.map(\.id))
        var result: [String: String] = [:]
        for old in previous where !currentIDs.contains(old.id) {
            let photos = Set(old.photoIDs)
            if let successor = current.first(where: { $0.photoIDs.contains(where: photos.contains) }) {
                result[old.id] = successor.id
            }
        }
        return result
    }

    func place(id: String) -> Place? {
        places.first { $0.id == id }
    }

    /// The place's name once Apple Maps has given one (and place names are on in settings).
    func name(for place: Place) -> String? {
        guard usesPlaceNames else { return nil }
        return placeNames[Self.placeKey(place.center)]
    }

    /// The name, or the month of the latest visit while it has none.
    func title(for place: Place) -> String {
        (name(for: place) ?? place.latest.formatted(.dateTime.month(.wide).year())).lowercased()
    }

    /// Names the places of entries away from home, newest first. Apple throttles these lookups, so they go one at a
    /// time and every name is kept, keyed by a ~5 km cell, so each place is only asked about once.
    func lookUpPlaces() async {
        // Trips first, then every place on the places page, the most recent first.
        let centers = entries.filter(\.isAway).compactMap(\.center) + places.map(\.center)
        for center in centers {
            let key = Self.placeKey(center)
            guard placeNames[key] == nil, !failedPlaces.contains(key) else { continue }
            guard !Task.isCancelled else { return }
            if let name = await Self.placeName(at: center) {
                placeNames[key] = name
                save()
            } else {
                failedPlaces.insert(key)
            }
            try? await Task.sleep(for: .seconds(1.2))
        }
    }

    static func placeKey(_ coordinate: Coordinate) -> String {
        JournalBuilder.cellKey(coordinate, size: 0.05)
    }

    private static func placeName(at coordinate: Coordinate) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        if #available(iOS 26, *) {
            guard let request = MKReverseGeocodingRequest(location: location),
                  let item = try? await request.mapItems.first
            else { return nil }
            return item.addressRepresentations?.cityName ?? item.addressRepresentations?.regionName
        } else {
            let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
            return placemark?.locality ?? placemark?.administrativeArea ?? placemark?.country
        }
    }

    private func save() {
        guard let storeURL else { return }
        let store = Store(notes: notes, placeNames: placeNames)
        if let data = try? JSONEncoder().encode(store) {
            try? data.write(to: storeURL, options: .atomic)
        }
    }

    /// Every photo and video except screenshots, oldest first.
    nonisolated private static func loadPoints() -> [PhotoPoint] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let result = PHAsset.fetchAssets(with: options)
        var points: [PhotoPoint] = []
        points.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            // Filtered here, not in the fetch: iOS 27 matches almost nothing for a bitwise `mediaSubtypes` predicate.
            guard !asset.mediaSubtypes.contains(.photoScreenshot), let date = asset.creationDate else { return }
            points.append(PhotoPoint(
                id: asset.localIdentifier,
                date: date,
                coordinate: asset.location.map { Coordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) },
                isFavorite: asset.isFavorite
            ))
        }
        return points
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
