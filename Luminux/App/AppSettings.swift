import CoreGraphics
import Foundation
import Observation

@Observable
final class AppSettings {
    private enum Key {
        static let accent = "accentHex"
        static let theme = "theme"
        static let showsHubBackground = "showsHubBackground"
        static let playsLivingImages = "playsLivingImages"
        static let gridColumns = "gridColumns"
        static let movesWithPhone = "movesWithPhone"
        static let namesJournalPlaces = "namesJournalPlaces"
        static let tiltStrength = "tiltStrength"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var accent: Accent {
        didSet { defaults.set(Int(accent.hex), forKey: Key.accent) }
    }

    var theme: MetroTheme {
        didSet { defaults.set(theme.rawValue, forKey: Key.theme) }
    }

    var showsHubBackground: Bool {
        didSet { defaults.set(showsHubBackground, forKey: Key.showsHubBackground) }
    }

    var playsLivingImages: Bool {
        didSet { defaults.set(playsLivingImages, forKey: Key.playsLivingImages) }
    }

    /// Photos per row in the grids; pinching steps through `GridZoom.levels`.
    var gridColumns: Int {
        didSet { defaults.set(gridColumns, forKey: Key.gridColumns) }
    }

    var movesWithPhone: Bool {
        didSet { defaults.set(movesWithPhone, forKey: Key.movesWithPhone) }
    }

    var tiltStrength: TiltStrength {
        didSet { defaults.set(tiltStrength.rawValue, forKey: Key.tiltStrength) }
    }

    /// Asks Apple Maps for the names of places photos were taken away from home.
    var namesJournalPlaces: Bool {
        didSet { defaults.set(namesJournalPlaces, forKey: Key.namesJournalPlaces) }
    }

    var palette: MetroPalette { MetroPalette(theme: theme, accent: accent) }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        accent = (defaults.object(forKey: Key.accent) as? Int).map { Accent(hex: UInt32($0)) } ?? .cobalt
        theme = defaults.string(forKey: Key.theme).flatMap(MetroTheme.init) ?? .dark
        showsHubBackground = defaults.object(forKey: Key.showsHubBackground) as? Bool ?? true
        playsLivingImages = defaults.object(forKey: Key.playsLivingImages) as? Bool ?? true
        gridColumns = GridZoom.nearestLevel(to: defaults.object(forKey: Key.gridColumns) as? Int ?? GridZoom.defaultColumns)
        movesWithPhone = defaults.object(forKey: Key.movesWithPhone) as? Bool ?? true
        namesJournalPlaces = defaults.object(forKey: Key.namesJournalPlaces) as? Bool ?? true
        tiltStrength = defaults.string(forKey: Key.tiltStrength).flatMap(TiltStrength.init) ?? .medium
    }
}

/// How far the hub moves with the phone; high is the strongest the effect goes.
nonisolated enum TiltStrength: String, CaseIterable, Identifiable, Sendable {
    case low, medium, high

    var id: String { rawValue }

    var scale: CGFloat {
        switch self {
        case .low: 0.45
        case .medium: 0.7
        case .high: 1
        }
    }
}
