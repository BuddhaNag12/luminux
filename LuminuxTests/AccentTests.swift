import Foundation
import Testing
@testable import Luminux

struct AccentTests {
    private func luminance(_ accent: Accent) -> Double {
        let channels = [accent.hex >> 16, accent.hex >> 8, accent.hex].map { Double($0 & 0xFF) / 255 }
        let linear = channels.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }

    @Test func keepsTheSixClassicPresets() {
        #expect(Accent.presets.count == 6)
        #expect(Set(Accent.presets).count == 6)
        #expect(Accent.presets.allSatisfy { $0.isPreset })
        #expect(Accent.cobalt.hex == 0x0050EF)
        #expect(Accent.cobalt.name == "cobalt")
    }

    @Test func aCustomColourInRangeIsKept() {
        let picked = Accent.custom(red: 1, green: 0, blue: 0)

        #expect(picked.hex == 0xFF0000)
        #expect(!picked.isPreset)
        #expect(picked.name == "#FF0000")
    }

    @Test func whiteIsDarkenedSoTileLabelsStayReadable() {
        let picked = Accent.custom(red: 1, green: 1, blue: 1)

        #expect(abs(luminance(picked) - Accent.maxLuminance) < 0.01)
    }

    @Test func blackIsLightenedSoItShowsOnBlack() {
        let picked = Accent.custom(red: 0, green: 0, blue: 0)

        #expect(abs(luminance(picked) - Accent.minLuminance) < 0.01)
    }

    @Test func darkeningKeepsTheHue() {
        let picked = Accent.custom(red: 1, green: 1, blue: 0.2)
        let red = picked.hex >> 16 & 0xFF, green = picked.hex >> 8 & 0xFF, blue = picked.hex & 0xFF

        #expect(red == green)
        #expect(blue < red)
    }

    @Test func textOnEveryAccentClearsBodyContrast() {
        let contrast = { (a: Double, b: Double) in (max(a, b) + 0.05) / (min(a, b) + 0.05) }
        // The presets, the custom range's ends and the switch point itself.
        let accents = Accent.presets + [0x000000, 0xFFFFFF, 0x808080, 0x7E7E7E].map { Accent.custom(red: Double($0 >> 16 & 0xFF) / 255, green: Double($0 >> 8 & 0xFF) / 255, blue: Double($0 & 0xFF) / 255) }
        for accent in accents {
            let text = AccentContrast.needsDarkText(accent.hex) ? 0.0 : 1.0
            #expect(contrast(luminance(accent), text) >= 4.5, "\(accent.name)")
        }
        #expect(AccentContrast.needsDarkText(Accent.lime.hex))
        #expect(AccentContrast.needsDarkText(Accent.teal.hex))
        #expect(AccentContrast.needsDarkText(Accent.mango.hex))
        #expect(!AccentContrast.needsDarkText(Accent.cobalt.hex))
    }
}
