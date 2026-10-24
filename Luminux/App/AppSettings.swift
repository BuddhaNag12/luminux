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
        static let animatesLiveTiles = "animatesLiveTiles"
        static let animatesTilePatterns = "animatesTilePatterns"
        static let hubBackground = "hubBackground"
        static let showsStandBy = "showsStandBy"
        static let namesJournalPlaces = "namesJournalPlaces"
        static let tiltStrength = "tiltStrength"
        static let hasSeenOnboarding = "hasSeenOnboarding"
        static let pageTransition = "pageTransition"
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

    /// Photo tiles flip to a new picture every few seconds; off, each shows one picture and changes it each time the
    /// hub comes back into view.
    var animatesLiveTiles: Bool {
        didSet { defaults.set(animatesLiveTiles, forKey: Key.animatesLiveTiles) }
    }

    /// The albums and date tiles' slow abstract patterns.
    var animatesTilePatterns: Bool {
        didSet { defaults.set(animatesTilePatterns, forKey: Key.animatesTilePatterns) }
    }

    /// Where the hub's background photo is picked from, once per launch.
    var hubBackground: HubBackgroundSource {
        didSet { defaults.set(try? JSONEncoder().encode(hubBackground), forKey: Key.hubBackground) }
    }

    /// The small widget's StandBy face: photo tiles and today's date. Pro; the app copies it to the widget.
    var showsStandBy: Bool {
        didSet { defaults.set(showsStandBy, forKey: Key.showsStandBy) }
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

    /// How pages open and close.
    var pageTransition: PageTransition {
        didSet { defaults.set(pageTransition.rawValue, forKey: Key.pageTransition) }
    }

    /// The first-launch tour has been shown (finished or skipped to the end).
    var hasSeenOnboarding: Bool {
        didSet { defaults.set(hasSeenOnboarding, forKey: Key.hasSeenOnboarding) }
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
        animatesLiveTiles = defaults.object(forKey: Key.animatesLiveTiles) as? Bool ?? true
        animatesTilePatterns = defaults.object(forKey: Key.animatesTilePatterns) as? Bool ?? true
        hubBackground = defaults.data(forKey: Key.hubBackground).flatMap { try? JSONDecoder().decode(HubBackgroundSource.self, from: $0) } ?? .favorites
        showsStandBy = defaults.object(forKey: Key.showsStandBy) as? Bool ?? true
        namesJournalPlaces = defaults.object(forKey: Key.namesJournalPlaces) as? Bool ?? true
        tiltStrength = defaults.string(forKey: Key.tiltStrength).flatMap(TiltStrength.init) ?? .medium
        hasSeenOnboarding = defaults.bool(forKey: Key.hasSeenOnboarding)
        pageTransition = defaults.string(forKey: Key.pageTransition).flatMap(PageTransition.init) ?? .zoom
    }
}

/// `turnstile`: Windows Phone's, every line of a page turning on the screen's edge. `zoom`: the newer Windows one, the
/// page underneath growing and fading away as the new one grows into place.
nonisolated enum PageTransition: String, CaseIterable, Identifiable, Sendable {
    case turnstile, zoom

    var id: String { rawValue }
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

/// The photos the hub's background is picked from.
nonisolated enum HubBackgroundSource: Codable, Hashable, Sendable {
    case favorites
    case everything
    case album(String)
    case photoSet(String)
    /// Photos picked one by one in settings.
    case photos([String])
}
