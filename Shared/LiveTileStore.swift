import Foundation

/// Photos the app hands to the home-screen live tile through the shared App Group (widgets can't read the photo library).
nonisolated enum LiveTileStore {
    static let appGroup = "group.com.buddhanag.luminux"
    static let accentKey = "accentHex"
    static let proKey = "isPro"
    static let maxImages = 12

    static let collectionsKey = "collections"

    enum Source: String, CaseIterable, Sendable {
        case recent, favorites
    }

    /// An album or photo set someone made a widget from in the app; the widget offers these as choices.
    struct Collection: Codable, Hashable, Identifiable, Sendable {
        /// `album:<PhotoKit id>` or `set:<photo set id>`.
        let id: String
        var title: String

        static func album(_ id: String, title: String) -> Collection { Collection(id: "album:\(id)", title: title) }
        static func photoSet(_ id: String, title: String) -> Collection { Collection(id: "set:\(id)", title: title) }

        /// PhotoKit ids contain slashes, so the folder name keeps letters and digits only.
        var folderName: String {
            "c-" + id.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "-" }.joined()
        }
    }

    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static var collections: [Collection] {
        get {
            guard let data = defaults?.data(forKey: collectionsKey) else { return [] }
            return (try? JSONDecoder().decode([Collection].self, from: data)) ?? []
        }
        set { defaults?.set(try? JSONEncoder().encode(newValue), forKey: collectionsKey) }
    }

    static func folder(for source: Source) -> URL? { folder(named: source.rawValue) }

    static func folder(named name: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("Tiles/\(name)", isDirectory: true)
    }

    static func imageURLs(for source: Source) -> [URL] { imageURLs(in: folder(for: source)) }
    static func imageURLs(for collection: Collection) -> [URL] { imageURLs(in: folder(named: collection.folderName)) }

    private static func imageURLs(in folder: URL?) -> [URL] {
        guard let folder, let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return [] }
        return files.filter { $0.pathExtension == "jpg" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func replaceImages(_ jpegs: [Data], for source: Source) throws {
        try replaceImages(jpegs, in: folder(for: source))
    }

    static func replaceImages(_ jpegs: [Data], for collection: Collection) throws {
        try replaceImages(jpegs, in: folder(named: collection.folderName))
    }

    static func removeImages(for collection: Collection) {
        if let folder = folder(named: collection.folderName) { try? FileManager.default.removeItem(at: folder) }
    }

    private static func replaceImages(_ jpegs: [Data], in folder: URL?) throws {
        guard let folder else { return }
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (index, data) in jpegs.prefix(maxImages).enumerated() {
            try data.write(to: folder.appendingPathComponent("\(index).jpg"), options: .atomic)
        }
    }

    static var accentHex: UInt32 {
        get { (defaults?.object(forKey: accentKey) as? Int).map(UInt32.init) ?? 0x0050EF }
        set { defaults?.set(Int(newValue), forKey: accentKey) }
    }

    /// Whether Luminux Pro is unlocked, so the widget can offer its medium and large tiles.
    static var isPro: Bool {
        get { defaults?.bool(forKey: proKey) ?? false }
        set { defaults?.set(newValue, forKey: proKey) }
    }

    /// Written by test installs (`PRO_FREE_FOR_TESTING`) so every widget size can be tried without buying Pro; App
    /// Store builds write false on launch.
    static var isTestBuild: Bool {
        get { defaults?.bool(forKey: "isTestBuild") ?? false }
        set { defaults?.set(newValue, forKey: "isTestBuild") }
    }

    static var unlocksWideTiles: Bool { isPro || isTestBuild }
}
