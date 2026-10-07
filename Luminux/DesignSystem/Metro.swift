import SwiftUI

/// The accent colour: one of the six classic presets, or any colour from the picker (a Pro feature).
nonisolated struct Accent: Hashable, Identifiable, Sendable {
    let hex: UInt32

    static let cobalt = Accent(hex: 0x0050EF)
    static let lime = Accent(hex: 0xA4C400)
    static let teal = Accent(hex: 0x00ABA9)
    static let magenta = Accent(hex: 0xD80073)
    static let red = Accent(hex: 0xE51400)
    static let mango = Accent(hex: 0xFA6800)

    static let presets: [Accent] = [.cobalt, .lime, .teal, .magenta, .red, .mango]
    private static let names: [UInt32: String] = [
        0x0050EF: "cobalt", 0xA4C400: "lime", 0x00ABA9: "teal",
        0xD80073: "magenta", 0xE51400: "red", 0xFA6800: "mango",
    ]

    var id: UInt32 { hex }
    var color: Color { Color(hex: hex) }
    var isPreset: Bool { Self.names[hex] != nil }
    /// The preset's name, or the hex code of a custom colour.
    var name: String { Self.names[hex] ?? String(format: "#%06X", hex) }

    /// A picked colour, nudged into the brightness range of the original Metro accents so white tile labels stay
    /// readable on it and it still shows on a black background.
    static func custom(red: Double, green: Double, blue: Double) -> Accent {
        let linear = [red, green, blue].map { channel in
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
        let adjusted: [Double]
        if luminance > maxLuminance {
            adjusted = linear.map { $0 * maxLuminance / luminance }
        } else if luminance < minLuminance {
            // Mix toward white; scaling up would leave pure black black.
            let mix = (minLuminance - luminance) / (1 - luminance)
            adjusted = linear.map { $0 + (1 - $0) * mix }
        } else {
            adjusted = linear
        }
        let bytes = adjusted.map { channel -> UInt32 in
            let encoded = channel <= 0.0031308 ? channel * 12.92 : 1.055 * pow(channel, 1 / 2.4) - 0.055
            return UInt32((min(max(encoded, 0), 1) * 255).rounded())
        }
        return Accent(hex: bytes[0] << 16 | bytes[1] << 8 | bytes[2])
    }

    /// Relative luminance bounds of the 20 Windows Phone accents (crimson to yellow).
    static let minLuminance = 0.07
    static let maxLuminance = 0.58
}

enum MetroTheme: String, CaseIterable, Identifiable, Sendable {
    case dark, light

    var id: String { rawValue }
    var colorScheme: ColorScheme { self == .dark ? .dark : .light }
}

/// Resolved colors for the current theme and accent, read through `@Environment(\.metro)`.
struct MetroPalette: Equatable {
    var theme: MetroTheme
    var accent: Accent

    var background: Color { theme == .dark ? .black : .white }
    var foreground: Color { theme == .dark ? .white : .black }
    var secondary: Color { theme == .dark ? Color(hex: 0xA0A0A0) : Color(hex: 0x666666) }
    /// App bar and empty-tile fill.
    var chrome: Color { theme == .dark ? Color(hex: 0x1F1F1F) : Color(hex: 0xDDDDDD) }
    /// Lets the photos scrolling underneath show through, darkened, like the original app bar.
    var appBar: Color { theme == .dark ? Color(hex: 0x1F1F1F).opacity(0.72) : Color(hex: 0xDDDDDD).opacity(0.8) }
    /// The open app bar is nearly solid, so its labels and menu read clearly over busy photos.
    var appBarExpanded: Color { chrome.opacity(0.95) }
    var accentColor: Color { accent.color }
}

enum MetroMetrics {
    static let margin: CGFloat = 12
    static let gutter: CGFloat = 4
    static let appBarHeight: CGFloat = 56
    static let appBarButton: CGFloat = 48
}

extension EnvironmentValues {
    @Entry var metro = MetroPalette(theme: .dark, accent: .cobalt)
}

extension Color {
    nonisolated init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
