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
        #expect(settings.gridColumns == 5)
        #expect(settings.movesWithPhone)
        #expect(settings.tiltStrength == .medium)
        #expect(settings.animatesLiveTiles)
        #expect(settings.animatesTilePatterns)
        #expect(settings.showsStandBy)
    }

    @Test func theBackgroundSourceIsKept() {
        let defaults = freshDefaults()
        #expect(AppSettings(defaults: defaults).hubBackground == .favorites)
        for source: HubBackgroundSource in [.everything, .album("a/1"), .photoSet("s"), .photos(["p1", "p2"])] {
            AppSettings(defaults: defaults).hubBackground = source
            #expect(AppSettings(defaults: defaults).hubBackground == source)
        }
    }

    @Test func tileAnimationSwitchesAreKept() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.animatesLiveTiles = false
        settings.animatesTilePatterns = false
        settings.showsStandBy = false
        let reloaded = AppSettings(defaults: defaults)
        #expect(!reloaded.animatesLiveTiles)
        #expect(!reloaded.animatesTilePatterns)
        #expect(!reloaded.showsStandBy)
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
