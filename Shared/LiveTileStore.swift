import Foundation

/// Photos the app hands to the home-screen live tile through the shared App Group (widgets can't read the photo library).
nonisolated enum LiveTileStore {
    static let appGroup = "group.com.buddhanag.luminux"
    static let accentKey = "accentHex"
    static let maxImages = 6

    enum Source: String, CaseIterable, Sendable {
        case recent, favorites
    }

    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func folder(for source: Source) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("Tiles/\(source.rawValue)", isDirectory: true)
    }

    static func imageURLs(for source: Source) -> [URL] {
        guard let folder = folder(for: source),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return [] }
        return files.filter { $0.pathExtension == "jpg" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func replaceImages(_ jpegs: [Data], for source: Source) throws {
        guard let folder = folder(for: source) else { return }
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
}
