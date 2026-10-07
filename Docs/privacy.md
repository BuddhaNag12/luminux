# Privacy: App Store answers and policy

Luminux collects nothing itself. Since the news panel, Google's ad SDK (Google Mobile Ads 13.x) and its consent SDK
(User Messaging Platform 3.x) do, so the App Store label is no longer "Data Not Collected". The answers below come
from the privacy manifests inside the exact SDK versions in the app (`PrivacyInfo.xcprivacy` in each framework);
check them again after an SDK update.

## App Store Connect → App Privacy

"Do you or your third-party partners collect data from this app?" **Yes.**

| Data type | Purposes | Linked to the user | Used for tracking |
|---|---|---|---|
| Location → Coarse Location | Third-Party Advertising, Developer's Advertising or Marketing, Analytics, App Functionality | Yes | No |
| Identifiers → Device ID | Third-Party Advertising, Developer's Advertising or Marketing, Analytics | Yes | No (see below) |
| Usage Data → Product Interaction | Third-Party Advertising, Developer's Advertising or Marketing, Analytics, App Functionality | Yes | No |
| Usage Data → Advertising Data | Third-Party Advertising, Developer's Advertising or Marketing, Analytics | Yes | No |
| Diagnostics → Crash Data | Analytics | No | No |
| Diagnostics → Performance Data | Third-Party Advertising, Developer's Advertising or Marketing, Analytics, App Functionality | No | No |
| Diagnostics → Other Diagnostic Data | Third-Party Advertising, Developer's Advertising or Marketing, Analytics | No | No |

App Functionality is there because the consent SDK uses coarse location, performance and interaction data to decide
whether a consent form is needed.

**Tracking:** Google's manifest marks Device ID as tracking, because it covers apps that get the user's permission to
use the advertising identifier. Luminux never asks (no App Tracking Transparency prompt), so the identifier is all
zeros, and every ad request is non-personalised (`npa=1`). Answer "No" for tracking. If App Review asks, explain
exactly that.

**Not collected, so not declared:**
- Photos and videos: read on the device, never uploaded.
- Journal place names: only locations go to Apple Maps, Apple's own service.
- News: the Luminux news server answers the request and keeps nothing (logs off). GNews only ever sees the server.
- Purchases: handled by Apple.

## Privacy policy (draft to publish)

Host this at a public URL (GitHub Pages works) and put that URL in App Store Connect and in the AdMob GDPR message.
Fill in the contact address.

> **Luminux privacy policy**
>
> *Last updated: [date]*
>
> **Your photos.** Luminux shows the photos and videos in your library. They stay on your iPhone and are never
> uploaded. Journal notes and titles are stored on your iPhone only.
>
> **Place names.** If "name places in the journal" is on, Luminux sends the locations of photos taken away from home
> to Apple Maps to look up place names. Photos are never sent. You can turn this off in settings.
>
> **News.** Without Luminux Pro, the hub has a news panel. Headlines come from GNews through Luminux's own server. When
> the app asks for headlines, the server sees your internet address to answer the request and to pick your country's
> edition; it keeps no logs and stores nothing about you. GNews never receives your request. Stories open on the
> publisher's website, which has its own privacy policy.
>
> **Ads.** The news panel shows ads from Google AdMob. Luminux asks for non-personalised ads and never asks to track
> you across other apps. Google's SDK may still collect device identifiers, approximate location from your internet
> address, ad interactions, and crash and performance data to show ads, measure them and prevent fraud. In the EEA,
> the UK and Switzerland, Google asks for your consent first, and you can change it later in settings → "ad privacy
> choices". See how Google uses this information: https://policies.google.com/technologies/partner-sites
>
> **Luminux Pro.** Buying Pro removes the news panel and its ads; Google's SDK is then never started. Purchases are
> handled by Apple; Luminux never sees your payment details.
>
> **Children.** Luminux isn't directed at children under 13.
>
> **Changes.** If this policy changes, the new version will be posted here with a new date.
>
> **Contact.** [support email]
