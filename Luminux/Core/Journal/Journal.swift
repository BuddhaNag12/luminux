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
    private(set) var isBuilt = false
    /// Off when place names are turned off in settings; names already looked up stay cached but hidden.
    var usesPlaceNames = true
    private var notes: [String: JournalNote] = [:]
    private var placeNames: [String: String] = [:]
    /// Each entry's best photos, best first, once scored.
    private var keyPhotoPicks: [String: [String]] = [:]

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

    func entry(id: String) -> JournalEntry? {
        entries.first { $0.id == id }
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
            JournalBuilder.entries(from: Self.loadPoints())
        }.value
        entries = built
        isBuilt = true
    }

    /// Names the places of entries away from home, newest first. Apple throttles these lookups, so they go one at a
    /// time and every name is kept, keyed by a ~5 km cell, so each place is only asked about once.
    func lookUpPlaces() async {
        for entry in entries where entry.isAway {
            guard let center = entry.center else { continue }
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
        options.predicate = NSPredicate(format: "(mediaSubtypes & %d) == 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
        let result = PHAsset.fetchAssets(with: options)
        var points: [PhotoPoint] = []
        points.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            guard let date = asset.creationDate else { return }
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
