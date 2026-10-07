import GoogleMobileAds
import Observation
import UIKit

/// "Watch an ad to use it once" for Pro features. The ad plays only when someone taps to watch one.
@Observable
final class RewardedAds {
    private(set) var isLoading = false
    /// Why the last attempt didn't play; the Pro page shows it.
    private(set) var message: String?

    @ObservationIgnored private let consent: AdConsent
    @ObservationIgnored private var ad: RewardedAd?
    @ObservationIgnored private var loadedAt: Date?
    @ObservationIgnored private var player: RewardedPlayer?

    /// Google expires loaded ads after an hour.
    private static let adLifetime: TimeInterval = 55 * 60

    static var adUnitID: String {
        AdConsent.adUnitID(infoKey: "LuminuxRewardedAdUnitID", test: "ca-app-pub-3940256099942544/1712485313")
    }

    init(consent: AdConsent) {
        self.consent = consent
    }

    /// Loads ahead once consent is settled this launch, so "watch an ad" can play straight away.
    func preload() async {
        guard consent.isReady, freshAd == nil, !isLoading else { return }
        ad = try? await load()
        loadedAt = ad == nil ? nil : .now
    }

    /// Plays an ad; true once the viewer has earned the reward.
    func watch() async -> Bool {
        guard !isLoading, player == nil else { return false }
        message = nil
        isLoading = true
        guard await consent.prepare() else {
            isLoading = false
            message = "Ads can't be shown with your current ad choices. You can change them in settings."
            return false
        }
        let next: RewardedAd? = if let freshAd { freshAd } else { try? await load() }
        ad = nil
        loadedAt = nil
        isLoading = false
        guard let next else {
            message = "No ad is available right now. Try again in a moment."
            return false
        }

        let player = RewardedPlayer()
        self.player = player
        let earned = await player.play(next, from: UIApplication.shared.topViewController)
        self.player = nil
        if !earned { message = "The ad was closed before the end, so the feature stays locked." }
        Task { await preload() }
        return earned
    }

    func clearMessage() {
        message = nil
    }

    private var freshAd: RewardedAd? {
        guard let ad, let loadedAt, Date.now.timeIntervalSince(loadedAt) < Self.adLifetime else { return nil }
        return ad
    }

    private func load() async throws -> RewardedAd {
        try await RewardedAd.load(with: Self.adUnitID, request: AdConsent.nonPersonalisedRequest())
    }
}

/// Presents one rewarded ad and reports, once it's closed, whether the reward was earned.
private final class RewardedPlayer: NSObject, FullScreenContentDelegate {
    private var earned = false
    private var finish: ((Bool) -> Void)?

    func play(_ ad: RewardedAd, from controller: UIViewController?) async -> Bool {
        await withCheckedContinuation { continuation in
            finish = { continuation.resume(returning: $0) }
            ad.fullScreenContentDelegate = self
            ad.present(from: controller) { [weak self] in
                self?.earned = true
            }
        }
    }

    func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        complete()
    }

    func ad(_ ad: any FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: any Error) {
        complete()
    }

    private func complete() {
        let finish = finish
        self.finish = nil
        finish?(earned)
    }
}
