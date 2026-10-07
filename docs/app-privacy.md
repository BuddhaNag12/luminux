# App Store privacy answers

Luminux collects nothing itself. Google's ad SDK (Google Mobile Ads 13.x), used for the "watch an ad to use it once"
offers on Pro features, and its consent SDK (User Messaging Platform 3.x) do, so the App Store label is no longer
"Data Not Collected". The answers below come
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
- News: the panel is parked (no server address in the app). If it's switched on later, the Luminux news server
  answers requests and keeps nothing, and GNews only ever sees the server, so nothing new to declare.
- Purchases: handled by Apple.

The public policy that matches these answers is [`privacy.md`](privacy.md).
