import GoogleMobileAds
import Observation
import UIKit

/// Native ads for the news panel, loaded the first time the panel is shown.
@Observable
final class NewsAds {
    private(set) var ads: [NativeAd] = []

    @ObservationIgnored private let consent: AdConsent
    @ObservationIgnored private var isPreparing = false
    @ObservationIgnored private var loadedAt: Date?
    @ObservationIgnored private var loader: NativeAdBatchLoader?

    /// One ad after every this many headlines.
    static let headlinesPerAd = 5
    static let maxAds = 3
    /// Google expires native ads after an hour.
    private static let adLifetime: TimeInterval = 55 * 60

    static var adUnitID: String {
        AdConsent.adUnitID(infoKey: "LuminuxNativeAdUnitID", test: "ca-app-pub-3940256099942544/3986624511")
    }

    init(consent: AdConsent) {
        self.consent = consent
    }

    /// Asks for consent where it's required, starts the SDK and loads fresh ads if the current ones are old.
    func prepare(headlineCount: Int) async {
        guard !isPreparing, loader == nil else { return }
        if let loadedAt, Date.now.timeIntervalSince(loadedAt) < Self.adLifetime, !ads.isEmpty { return }
        isPreparing = true
        defer { isPreparing = false }

        guard await consent.prepare() else { return }
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
        loader.load(AdConsent.nonPersonalisedRequest())
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
