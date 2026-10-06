import SwiftUI

enum MetroWeight: String {
    case light = "Selawik-Light"
    case semilight = "Selawik-Semilight"
    case regular = "Selawik-Regular"
    case semibold = "Selawik-Semibold"
}

extension Font {
    static func metro(_ size: CGFloat, _ weight: MetroWeight = .regular, relativeTo style: TextStyle = .body) -> Font {
        .custom(weight.rawValue, size: size, relativeTo: style)
    }

    /// Panorama title, e.g. "photos".
    static let metroPanorama = metro(96, .light, relativeTo: .largeTitle)
    /// Page title, e.g. "settings".
    static let metroTitle = metro(56, .light, relativeTo: .largeTitle)
    static let metroPivot = metro(44, .light, relativeTo: .title)
    static let metroSection = metro(28, .semilight, relativeTo: .title2)
    static let metroBody = metro(17, .regular, relativeTo: .body)
    static let metroCaption = metro(14, .regular, relativeTo: .caption)
    /// Uppercase app name above titles, e.g. "LUMINUX".
    static let metroOverline = metro(12, .semibold, relativeTo: .caption2)
}
