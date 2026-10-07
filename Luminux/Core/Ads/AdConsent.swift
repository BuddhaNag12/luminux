import GoogleMobileAds
import Observation
import UIKit
import UserMessagingPlatform

/// Google's consent step and SDK start, shared by every kind of ad. Nothing here runs until someone chooses an ad, so
/// Pro users and people who never do never meet Google's SDK or its consent form.
///
/// Ads are always non-personalised and the app never asks to track, so the only prompt anyone sees is the consent
/// form Google requires in the EEA, the UK and Switzerland.
@Observable
final class AdConsent {
    /// True where the law asks for a way to change the consent later; settings then shows "ad privacy choices".
    private(set) var needsPrivacyOptions = false

    @ObservationIgnored private var hasStarted = false

    /// Asks for consent where it's required and starts the SDK; false when ads can't be requested.
    func prepare() async -> Bool {
        let consent = ConsentInformation.shared
        do {
            try await consent.requestConsentInfoUpdate(with: RequestParameters())
            try await ConsentForm.loadAndPresentIfRequired(from: UIApplication.shared.topViewController)
        } catch {
            // Offline, or the form failed to load: Google still answers `canRequestAds` from what it last knew.
        }
        needsPrivacyOptions = consent.privacyOptionsRequirementStatus == .required
        guard consent.canRequestAds else { return false }

        if !hasStarted {
            hasStarted = true
            MobileAds.shared.isApplicationMuted = true
            await MobileAds.shared.start()
        }
        return true
    }

    /// True once this launch has asked and ads are allowed, so loading ahead never brings up the form unasked.
    var isReady: Bool { hasStarted && ConsentInformation.shared.canRequestAds }

    /// For settings: learns whether "ad privacy choices" applies, but only for people who've already been through
    /// Google's consent step, so nobody else's app ever contacts Google.
    func refreshPrivacyOptions() async {
        let consent = ConsentInformation.shared
        guard consent.consentStatus != .unknown else { return }
        try? await consent.requestConsentInfoUpdate(with: RequestParameters())
        needsPrivacyOptions = consent.privacyOptionsRequirementStatus == .required
    }

    func presentPrivacyOptions() async {
        try? await ConsentForm.presentPrivacyOptionsForm(from: UIApplication.shared.topViewController)
    }

    /// The real ad unit only in App Store builds: AdMob suspends accounts whose owner sees or taps their own live ads,
    /// so debug builds and test installs on the phone get Google's test unit.
    static func adUnitID(infoKey: String, test: String) -> String {
        #if DEBUG
        test
        #else
        let configured = (Bundle.main.object(forInfoDictionaryKey: infoKey) as? String).flatMap { $0.isEmpty ? nil : $0 }
        return ProStore.isTestBuild ? test : configured ?? test
        #endif
    }

    static func nonPersonalisedRequest() -> Request {
        let request = Request()
        let extras = Extras()
        extras.additionalParameters = ["npa": "1"]
        request.register(extras)
        return request
    }
}
