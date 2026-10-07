import Foundation
import Observation

@Observable
final class AppSettings {
    private enum Key {
        static let accent = "accent"
        static let theme = "theme"
        static let showsHubBackground = "showsHubBackground"
        static let playsLivingImages = "playsLivingImages"
        static let gridColumns = "gridColumns"
        static let movesWithPhone = "movesWithPhone"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var accent: Accent {
        didSet { defaults.set(accent.rawValue, forKey: Key.accent) }
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

    var palette: MetroPalette { MetroPalette(theme: theme, accent: accent) }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        accent = defaults.string(forKey: Key.accent).flatMap(Accent.init) ?? .cobalt
        theme = defaults.string(forKey: Key.theme).flatMap(MetroTheme.init) ?? .dark
        showsHubBackground = defaults.object(forKey: Key.showsHubBackground) as? Bool ?? true
        playsLivingImages = defaults.object(forKey: Key.playsLivingImages) as? Bool ?? true
        gridColumns = GridZoom.nearestLevel(to: defaults.object(forKey: Key.gridColumns) as? Int ?? GridZoom.defaultColumns)
        movesWithPhone = defaults.object(forKey: Key.movesWithPhone) as? Bool ?? true
    }
}
