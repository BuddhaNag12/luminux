import SwiftUI

enum Accent: String, CaseIterable, Identifiable, Sendable {
    case lime, green, emerald, teal, cyan, cobalt, indigo, violet, pink, magenta
    case crimson, red, mango, amber, yellow, brown, olive, steel, mauve, taupe

    var id: String { rawValue }

    var hex: UInt32 {
        switch self {
        case .lime: 0xA4C400
        case .green: 0x60A917
        case .emerald: 0x008A00
        case .teal: 0x00ABA9
        case .cyan: 0x1BA1E2
        case .cobalt: 0x0050EF
        case .indigo: 0x6A00FF
        case .violet: 0xAA00FF
        case .pink: 0xF472D0
        case .magenta: 0xD80073
        case .crimson: 0xA20025
        case .red: 0xE51400
        case .mango: 0xFA6800
        case .amber: 0xF0A30A
        case .yellow: 0xE3C800
        case .brown: 0x825A2C
        case .olive: 0x6D8764
        case .steel: 0x647687
        case .mauve: 0x76608A
        case .taupe: 0x87794E
        }
    }

    var color: Color { Color(hex: hex) }
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
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
