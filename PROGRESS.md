# Luminux progress

Metro-style photo gallery for iOS over the system Photos library.

## Phase 1: Stitch mockups ✅
- [x] Stitch project `937889977077172348`, design system "Metro Cobalt"
- [x] Hub, collection pivot, viewer with app bar, select mode, settings, jump list (`Design/`)

## Phase 2: Scaffold ✅
- [x] XcodeGen project (iOS 18+, Swift 6, MainActor default isolation), `.gitignore`, `git init` (nothing committed yet)
- [x] Selawik font bundled with its OFL license (`Resources/Fonts/`)
- [x] Metro theme: 20 accents, dark/light palette, metrics, Selawik type scale, outlined button style
- [x] Photos permission flow (full, limited with "choose more", denied → Settings)
- [x] `PhotoLibrary` service (fetch newest first, month sections, change observer) + 8 unit tests passing
- [x] Builds and runs on the iPhone 18 Pro simulator (iOS 27): permission screen and the temporary hub (19 items / 6 months) checked
- [x] Run on the physical iPhone (installed on the iPhone 17 Pro on 2026-10-06; device signing with the App Group works)

## Phase 3: Metro components ✅
- [x] Panorama: background at 0.3× and title at 0.5× parallax (the title stops with its last letters on screen), panels snap with a 44 pt peek, Reduce Motion turns parallax off
- [x] Pivot: headers slide and fade with the swipe, tap a header to jump, the header row repeats so it looks looped
- [x] MetroTile + tilt: tips toward the touch point (12° max, less on big tiles) and presses in at the centre; taps and scrolling still work
- [x] Turnstile transition (hinged at the left edge, −80°/+50° like the original), cross-fade with Reduce Motion
- [x] App bar: circle buttons, ••• shows labels and a text menu, tapping outside collapses it
- [x] Jump list: month grid per year, accent for months with photos, current month outlined, undated tile
- [x] Live tile: flip or slide every 4–8 s at random, pauses off screen, still with Reduce Motion
- [x] `-gallery panorama|pivot` debug launch argument for checking components; 16 unit tests passing
- Checked in the simulator with real swipes and taps (`Design/progress/phase3-*.png`). Not checked yet: tilt mid-press and turnstile mid-animation (only their static poses were checked).
- Deferred: the pivot content doesn't wrap from the last page to the first (only the headers loop); the panorama doesn't wrap either.

## Phase 4: Screens ✅
- [x] Navigation: page stack with turnstile in and out, an interactive swipe from the left edge to go back (the page follows the finger), and pages keep their state underneath
- [x] Hub: panorama over a random recent photo (parallax), live tiles for camera roll (flip) and favorites (slide), a date tile, albums; "what's new" (last 30 days) and favorites panels; a limited-access notice
- [x] Collection pivot: all (grouped by month, a header opens the jump list and jumps), albums, favorites, videos, empty states
- [x] Album page: grid, select mode, rename and delete album (user albums), remove from album
- [x] Viewer: zooms from the tile, swipe paging, pinch and double-tap zoom, swipe down to close (follows the finger), tap toggles controls, Living Images (Live Photos play once), video, date overlay
- [x] Actions: share (original files), favorite/unfavorite, delete (system confirmation), add to album with a Metro picker and "new album"
- [x] Select mode: checkboxes, accent border, "N SELECTED", share/favorite/add/delete
- [x] Settings page (pulled forward from phase 5): dark/light, 20 accents, Metro toggles
- [x] Library loads in the background; all PhotoKit change blocks are `@Sendable`
- Checked in the simulator: hub, collection, viewer paging and app bar, favorite, new album, album page, select mode, swipe back, swipe down to close. 16 unit tests pass.
- Not checked yet: video playback, share sheet, delete, jump to a month, rename/delete album, light theme on real screens.

## Phase 5: Extras ✅
- [x] Edit: rotate 90° counterclockwise and crop (free / original / square / 16:9, corner handles, move), saved as a PhotoKit edit that shows up in Apple Photos; quick "rotate" in the ••• menu; "revert to original" for edited photos. Still photos only for now; Live Photos and videos aren't edited.
- [x] Details sheet: date, file name, dimensions and MP, size, type, camera and exposure (EXIF), location with a map, edited flag
- [x] Slideshow: slow pan and zoom with cross-fades, photos only, screen stays awake, tap to stop, no motion with Reduce Motion
- [x] Live tile widget (small, medium, large): recent photos or favorites, cycles every 20 min, accent background, Selawik label; the app shares 6 downscaled photos per set through the App Group; tapping opens the hub (`luminux://`)
- [x] Settings (done in phase 4)
- 26 unit tests pass (crop maths and edit output added). Checked in the simulator: editor (square + rotate, saved and shown in the grid), details, revert, slideshow, widget preview in the widget gallery.
- Not checked yet: crop handle dragging by hand, slideshow on a long library, the widget on a real device (needs the App Group in the provisioning profile).

## Phase 6: Polish 🚧
- [ ] Reduce Motion, VoiceOver, Dynamic Type
- [ ] 120 Hz profiling on the device
- [ ] App icon

### Feedback from device testing (iPhone 17 Pro, 2026-10-06)
- [x] **Swipe up for details in the viewer.** Dragging a photo up slides the details panel up from the bottom (date, file, size, camera, map) and the photo moves up with it. Swiping down closes the panel first, then the viewer. Replaces "details" in the ••• menu as the main way in.
  - Done: `DetailsPanel` (replaces the details sheet) covers 55% of the screen, follows the finger and rubber-bands past full height; the photo rises by half the lift so it stays centred above the panel. Close it by dragging down on the photo or the panel header, pulling the list down past its top, tapping the photo, or the VoiceOver escape gesture. Paging while it's open updates the details. "details" in the ••• menu opens the same panel. The zoom transition's own swipe-down is turned off while the panel is up (it was closing the whole viewer).
  - Checked in the simulator: swipe up, close from the photo, open from the menu, close from the header, swipe down still closes the viewer (`Design/progress/phase6-swipe-up-details.png`). Not checked yet: on the device, on videos and Live Photos.
- [x] **Select a whole month.** In select mode, each month header gets a "select all" checkbox that selects or clears every photo in that group. Long-pressing a photo starts select mode with that photo selected.
  - Done: the header box has three states (empty, a minus when part of the month is selected, a check when all of it is); tapping selects the rest or clears the month. Long-press (0.4 s, with a selection haptic) starts select mode on that photo; the tap that ends the press is ignored so it doesn't deselect it. 3 new tests for `SelectionModel` (29 total).
  - Checked in the simulator: long-press, mixed → all → none, and a tap after the long-press toggles normally (`Design/progress/phase6-select-month.png`). Not checked yet: the haptic and long-press feel on the device.
- [ ] **Smoother animation.** The transitions feel jittery on the device. Profile with Instruments (Animation Hitches, SwiftUI) on a Release build and fix the causes. Likely culprits:
  - the turnstile animating whole pages, including their scroll views (snapshot or animate tiles instead)
  - the hub parallax recomputing every frame
  - thumbnails decoding on the main thread (prefetch with `PHCachingImageManager`)
  - springs that are too soft
- [x] **Staggered "window" entrance when a page opens.** Tiles and photos turnstile in one after another, like Windows Phone: about 20–30 ms per item, by row and column, only for what's on screen, and in reverse when leaving. Applies to the hub panels, grids, albums, and the jump list.
  - Done (`DesignSystem/Feather.swift`): items tagged `.metroFeather(row:column:)` swing on a hinge at the left edge of their grid, 30 ms per row and 10 ms per column. Rows count from the first visible row (grids track it as they scroll), and off-screen rows don't animate. On a push, the old page's tiles swing out to 50°, then the new page fades in and its tiles swing in from −80°. `Navigator.pop()` swings the page out to −80° and then removes it. The interactive back swipe keeps the whole-page turn because it follows the finger. Reduce Motion: no swings, pages cross-fade.
  - Tagged: panorama title and section headers, hub tiles and photo grids, pivot overline and headers, photo grids (month headers and tiles), albums grid, album title, jump list (years and months), settings rows, empty messages.
  - Items take an explicit row and column instead of measuring their position, because measuring would update state on every scroll frame (the jitter item).
  - Fixed while testing: the covered page faded with the push before its tiles could swing; it now holds its background for 0.2 s. After deleting an album, the library reload landed mid-swing and froze it (SwiftUI drives `GeometryEffect` animations on the main thread), so the album page now waits for the album to leave the library before popping, and it keeps its title while it goes.
  - Checked in the simulator from recorded frames: push hub → collection (`Design/progress/phase6-feather-push.png`), pop settings → hub (`phase6-feather-pop.png`), pop after deleting an album, jump list, back swipe, and taps after the animation. Not checked yet: the feel at 120 Hz on the device.
- [x] **Video controls overlap.** On videos, the viewer's date overlay and app bar collide with the iOS video controls (AirPlay, volume, scrubber). For videos, hide the date overlay and app bar while the system controls are showing, or swap `VideoPlayer` for a Metro player with its own controls in the app bar (play/pause, scrubber, mute, AirPlay). Respect safe areas.
  - Done with the Metro player option: `VideoPlayback` (one per viewer, follows the current page) drives a bare `AVPlayerLayer`, so there are no system controls. A big outlined play button sits in the middle while paused (the poster shows until the first frame). The app bar gets play/pause as its first button, and a row on top of it has mute, elapsed time, a thin accent scrubber with a square thumb, remaining time, and AirPlay. The chrome fades out 2.5 s after playback starts; tap to bring it back. At the end it rewinds and shows the play button. Audio uses the playback category, so it plays with the silent switch on, like Photos. Only the scrubber row reads the 30 Hz time, so the viewer doesn't re-render every frame.
  - Fixed while testing: hiding the status bar briefly set the pager's position to nil, which unloaded the video and restarted it.
  - Checked in the simulator with a generated 8 s clip: play, auto-hide, play to the end, scrub (`Design/progress/phase6-metro-video-player.png`). Not checked yet: sound, mute, AirPlay, and VoiceOver on the scrubber (adjustable, ±5 s), all on the device.
- [ ] **Collection date and album tiles: waiting for details from you** (what's wrong or what's missing with the hub's "date" and "albums" tiles or pages)

### App Store readiness (review risk with the Metro look, 2026-10-06)
The Metro style itself is fine to ship; the risks are branding and two technical gaps. Checked on 2026-10-06: no Microsoft or Nokia names in the code or config.
- [ ] **Replace the undocumented file-size call** (`DetailsPanel.swift:115`, `resource.value(forKey: "fileSize")`). Apple's scan can flag it as non-public API (guideline 2.5.1). Use a supported way (sum the bytes from `PHAssetResourceManager.requestData`, only when the panel is open) or drop the size row.
- [ ] **Add `PrivacyInfo.xcprivacy`** to the app and the widget. Declare UserDefaults as a required-reason API (`CA92.1` for the app's own defaults, `1C8F.1` for the App Group defaults in `LiveTileStore`), plus any file-timestamp or disk-space APIs the build turns out to use. Tracking: no; collected data: none.
- [ ] **Store listing without trademarks.** Keep "Lumia", "Nokia", "Windows Phone", "Microsoft" and "Metro" out of the name, subtitle, description, keywords and screenshots (guidelines 4.1 and 5.2.1). Describe it as a tile-based gallery with bold typography and live tiles.
- [ ] **App icon brief:** a flat glyph on an accent tile; it must not look like the Windows logo, a four-pane window or the old WP Photos icon.
- [ ] **App Store name:** no live app is called exactly "Luminux" (closest: "Luminux Club", an education app). Reserved or delisted names don't show up in public searches, and Bulkypix had a game called "Luminux" in 2014. Reserve the name by creating the app record in App Store Connect (needs the $99/year Apple Developer Program). Fallbacks: "Luminux Photos", "Luminux Gallery". Check the trademark on USPTO before launch.
- [ ] **Screenshots:** use your own or properly licensed photos, not the simulator's sample images, and no private photos.
- [ ] **Usability under review:** non-standard UI is allowed if it's usable, so finish the VoiceOver / Dynamic Type / Reduce Motion pass and keep swipe back, the system permission prompts and the share sheet.
- [ ] **Release basics:** privacy label "Data Not Collected", support and privacy-policy URLs, the final bundle ID before the first upload, a Release build test, TestFlight.
- [ ] **Selawik license:** the OFL text ships with the font (`Resources/Fonts/Selawik-OFL.txt`); add it to an acknowledgements screen or the settings page.

## Resume here (next session)
- **Next:** phase 6 polish. Continue "Feedback from device testing" (swipe-up details, select a whole month, the video controls and the staggered entrance are done; next: smoother animation, which needs Instruments on the iPhone 17 Pro, and details from you about the hub's date and albums tiles), then the "App Store readiness" list (start with the two code fixes: replace the `fileSize` key and add `PrivacyInfo.xcprivacy`), then do a Reduce Motion / VoiceOver / Dynamic Type pass and check the light theme on every screen. Make the app icon (a flat Metro tile glyph). Profile at 120 Hz on the iPhone 17 Pro and run the widget there (App Group provisioning).
- **Build:** `export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH; export DEVELOPER_DIR=/Applications/Xcode-27.0.0.app/Contents/Developer`, then `xcodegen generate` and `xcodebuild -project Luminux.xcodeproj -scheme Luminux -destination "id=3FCA5EB5-E385-4214-8C67-CFF19B93810A" -derivedDataPath build test`.
- **Run:** `xcrun simctl install/launch` on the iPhone 18 Pro sim; debug component gallery with `-gallery panorama|pivot`.
- **Git:** initialized; nothing committed yet. Ask before the first commit (per phase? Co-Authored-By trailer?).
- **Skills:** apple-design (motion), ui-ux-pro-max (`references/pro-rules.md` pre-delivery checklist for phase 6).

## Log
- 2026-10-06: plan approved; Stitch mockups done; phase 2 started.
- 2026-10-06: phase 2 done. Notes for later: month grouping walks every asset on the main thread (move it off the main thread for big libraries); cobalt text on black is about 3.4:1 contrast, which passes only at 18 pt and larger.
- 2026-10-06: phase 3 done. Fixed along the way: a pivot layout bug (the wide header row widened the whole view), the panorama background not reaching the bottom, the jump list undated tile size, and the app bar not reaching the bottom edge. Debug launch takes about 3 s in the simulator; profile it in phase 6.
- 2026-10-06: phase 4 done. Bugs found and fixed while testing:
  - The hub panorama drifted to panel 2 when photos loaded. A `withAnimation` around the background fade also animated layout inside the scroll view; the animation is now scoped to the image.
  - The viewer opened on the wrong photo. Taps on the grid hit the row below because `.clipped()` doesn't limit hit testing and fill-scaled photos overflowed into the row above; fixed with `.contentShape(Rectangle())`. The viewer also now takes its start index up front.
  - Favoriting crashed. The PhotoKit change block was inferred as MainActor but runs on a background queue, so all change blocks are now `@Sendable`.
  - The system zoom dismiss didn't work over the zoomable photo, so the viewer has its own swipe down to close.
  - `rotation3DEffect` was replaced with `PerspectiveRotation`, which is an exact identity at rest (the built-in effect keeps its perspective term).
  - Test data: the simulator has a "traveltravel" album from testing.
- 2026-10-06: phase 5 done. Fixed: edited photos didn't refresh because image loads were keyed by ID only (now keyed by ID + modification date); the slideshow pan showed a black edge (the scale now stays at 1.08 or above).
- 2026-10-06: installed the Debug build (app + widget) on the iPhone 17 Pro with `-allowProvisioningUpdates`; the personal team created profiles for the app and widget, App Group included.
- 2026-10-06: phase 6 started. Swipe-up details panel done (the viewer's vertical drag now handles both directions). 26 tests pass.
- 2026-10-06: select a whole month and long-press to select done. 29 tests pass.
- 2026-10-06: Metro video player done (replaces `VideoPlayer`). The simulator now has an 8 s test clip (blue with an orange square) for video testing. 29 tests pass.
- 2026-10-06: staggered feather entrance and exit done. The simulator test album "traveltravel" was deleted while testing the pop. 29 tests pass.
- 2026-10-06: installed the Debug build with all four phase 6 feedback fixes on the iPhone 17 Pro and launched it, ready for device testing.
- 2026-10-06: added the "App Store readiness" checklist (the Metro look is fine; the risks are branding, an undocumented `fileSize` key and the missing privacy manifest). The name "Luminux" isn't taken by a live app; reserve it in App Store Connect.

