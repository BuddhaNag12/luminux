import Foundation

/// Which text colour reads on an accent, shared by the app and the widget.
nonisolated enum AccentContrast {
    /// True when black text reads better than white on the colour. Past a relative luminance of 0.179 black wins,
    /// and at that point both reach about 4.6:1, so every accent clears the 4.5:1 that body text needs.
    static func needsDarkText(_ hex: UInt32) -> Bool {
        let channels = [(hex >> 16) & 0xFF, (hex >> 8) & 0xFF, hex & 0xFF].map { byte -> Double in
            let value = Double(byte) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2] > 0.179
    }
}
