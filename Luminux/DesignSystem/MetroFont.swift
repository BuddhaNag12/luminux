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

    /// Display type that keeps its size: already bigger than any Dynamic Type size makes text, and grown further it ran
    /// off the screen.
    static func metroDisplay(_ size: CGFloat, _ weight: MetroWeight = .light) -> Font {
        .custom(weight.rawValue, fixedSize: size)
    }

    /// Panorama title, e.g. "photos".
    static let metroPanorama = metroDisplay(96)
    /// Panorama title across two panels, on iPhone Duo's inner screen.
    static let metroPanoramaWide = metroDisplay(144)
    /// Page title, e.g. "settings".
    static let metroTitle = metroDisplay(56)
    static let metroPivot = metroDisplay(44)
    static let metroSection = metro(28, .semilight, relativeTo: .title2)
    static let metroBody = metro(17, .regular, relativeTo: .body)
    static let metroCaption = metro(14, .regular, relativeTo: .caption)
    /// Uppercase app name above titles, e.g. "LUMINUX".
    static let metroOverline = metro(12, .semibold, relativeTo: .caption2)
}

extension View {
    /// Runs on past the right edge, as Metro page titles do, rather than wrapping or shrinking, without widening what
    /// it sits in: laid out at its natural width, a long title made the whole page wider than the screen and shifted
    /// it (and its app bar) off to the left.
    func metroOverflowingTitle() -> some View {
        hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) { fixedSize() }
            .fadesBeforeTrailingInset()
            .clipped()
    }
}
