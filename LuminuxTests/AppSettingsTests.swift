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

    @Test func persistsACustomAccent() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.accent = Accent(hex: 0x3A7D44)

        #expect(AppSettings(defaults: defaults).accent == Accent(hex: 0x3A7D44))
    }
}
