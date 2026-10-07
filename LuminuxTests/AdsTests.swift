import Testing
@testable import Luminux

struct AdsTests {
    /// AdMob suspends accounts whose owner loads their own live ads, so development builds must never ask for them.
    @Test func debugBuildsUseGoogleTestUnits() {
        #expect(RewardedAds.adUnitID == "ca-app-pub-3940256099942544/1712485313")
        #expect(NewsAds.adUnitID == "ca-app-pub-3940256099942544/3986624511")
    }
}
