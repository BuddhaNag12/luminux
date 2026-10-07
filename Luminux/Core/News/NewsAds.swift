import GoogleMobileAds
import Observation
import UIKit
import UserMessagingPlatform

/// Native ads for the news panel. Nothing here runs until the panel is first shown, so Pro users and people who never
/// swipe to the news never meet Google's SDK or its consent form.
///
/// Ads are always non-personalised and the app never asks to track, so the only prompt anyone sees is the consent
/// form Google requires in the EEA, the UK and Switzerland.
@Observable
final class NewsAds {
    private(set) var ads: [NativeAd] = []
    /// True where the law asks for a way to change the consent later; settings then shows "ad privacy choices".
    private(set) var needsPrivacyOptions = false

    @ObservationIgnored private var isPreparing = false
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var loadedAt: Date?
    @ObservationIgnored private var loader: NativeAdBatchLoader?

    /// One ad after every this many headlines.
    static let headlinesPerAd = 5
    static let maxAds = 3
    /// Google expires native ads after an hour.
    private static let adLifetime: TimeInterval = 55 * 60

    /// The ad unit from AdMob, or Google's test unit until the real one is set in `project.yml`.
    static var adUnitID: String {
        (Bundle.main.object(forInfoDictionaryKey: "LuminuxNativeAdUnitID") as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? "ca-app-pub-3940256099942544/3986624511"
    }

    /// Asks for consent where it's required, starts the SDK and loads fresh ads if the current ones are old.
    func prepare(headlineCount: Int) async {
        guard !isPreparing, loader == nil else { return }
        if let loadedAt, Date.now.timeIntervalSince(loadedAt) < Self.adLifetime, !ads.isEmpty { return }
        isPreparing = true
        defer { isPreparing = false }

        let consent = ConsentInformation.shared
        do {
            try await consent.requestConsentInfoUpdate(with: RequestParameters())
            try await ConsentForm.loadAndPresentIfRequired(from: UIApplication.shared.topViewController)
        } catch {
            // No form configured yet, or offline: Google still answers `canRequestAds` from what it last knew.
        }
        needsPrivacyOptions = consent.privacyOptionsRequirementStatus == .required
        guard consent.canRequestAds else { return }

        if !hasStarted {
            hasStarted = true
            MobileAds.shared.isApplicationMuted = true
            await MobileAds.shared.start()
        }
        let count = min(max(headlineCount / Self.headlinesPerAd, 1), Self.maxAds)
        loader = NativeAdBatchLoader(adUnitID: Self.adUnitID, count: count) { [weak self] fresh in
            guard let self else { return }
            loader = nil
            if !fresh.isEmpty {
                ads = fresh
                loadedAt = .now
            }
        }
        loader?.load(from: UIApplication.shared.topViewController)
    }

    func presentPrivacyOptions() async {
        try? await ConsentForm.presentPrivacyOptionsForm(from: UIApplication.shared.topViewController)
    }

    /// Lets go of the ads once Pro is bought.
    func clear() {
        ads = []
        loadedAt = nil
    }
}

/// Loads up to `count` native ads in one request and hands them back together.
private final class NativeAdBatchLoader: NSObject, NativeAdLoaderDelegate {
    private let adUnitID: String
    private let count: Int
    private var adLoader: AdLoader?
    private var received: [NativeAd] = []
    private var onFinish: (([NativeAd]) -> Void)?

    init(adUnitID: String, count: Int, onFinish: @escaping ([NativeAd]) -> Void) {
        self.adUnitID = adUnitID
        self.count = count
        self.onFinish = onFinish
    }

    func load(from rootViewController: UIViewController?) {
        let multiple = MultipleAdsAdLoaderOptions()
        multiple.numberOfAds = count
        let media = NativeAdMediaAdLoaderOptions()
        media.mediaAspectRatio = .landscape
        let loader = AdLoader(adUnitID: adUnitID, rootViewController: rootViewController, adTypes: [.native], options: [multiple, media])
        loader.delegate = self
        adLoader = loader
        loader.load(Self.nonPersonalisedRequest())
    }

    private static func nonPersonalisedRequest() -> Request {
        let request = Request()
        let extras = Extras()
        extras.additionalParameters = ["npa": "1"]
        request.register(extras)
        return request
    }

    func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        received.append(nativeAd)
    }

    func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        // The finish callback isn't promised after a failure, so hand back whatever arrived.
        finish()
    }

    func adLoaderDidFinishLoading(_ adLoader: AdLoader) {
        finish()
    }

    private func finish() {
        adLoader = nil
        let finish = onFinish
        onFinish = nil
        finish?(received)
    }
}
