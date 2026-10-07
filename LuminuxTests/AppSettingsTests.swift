import Foundation
import Testing
@testable import Luminux

struct AppSettingsTests {
    private func freshDefaults() -> UserDefaults {
        let name = "AppSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaultsToDarkCobaltWithEffectsOn() {
        let settings = AppSettings(defaults: freshDefaults())

        #expect(settings.theme == .dark)
        #expect(settings.accent == .cobalt)
        #expect(settings.showsHubBackground)
        #expect(settings.playsLivingImages)
        #expect(settings.gridColumns == 4)
        #expect(settings.movesWithPhone)
    }

    @Test func persistsChanges() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.accent = .lime
        settings.theme = .light
        settings.playsLivingImages = false

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.accent == .lime)
        #expect(reloaded.theme == .light)
        #expect(!reloaded.playsLivingImages)
    }

    @Test func hasTheTwentyMetroAccents() {
        #expect(Accent.allCases.count == 20)
        #expect(Accent.cobalt.hex == 0x0050EF)
        #expect(Set(Accent.allCases.map(\.hex)).count == 20)
    }
}
