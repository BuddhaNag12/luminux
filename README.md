# Luminux

A tile-based photo gallery for iPhone, built on the photos already in your library. Big thin type, square live tiles, one accent color, and motion that swings pages in like a turnstile.

Luminux is inspired by the Windows Phone 8.1 Photos hub. It isn't affiliated with or endorsed by Microsoft or Nokia.

## Features

**Browsing**
- **Hub:** a horizontally scrolling panorama over one of your photos. The background and title move slower than the content (parallax). Live tiles cycle through your camera roll and favorites, and there are panels for what's new and favorites.
- **Collection:** swipeable pivots for *all*, *albums*, *favorites* and *videos*. *All* is grouped by month; tap a month header to open a month grid and jump to any month.
- **Albums:** your own albums plus the automatic ones (selfies, Live Photos, portrait, panoramas, screenshots, bursts). Create, rename and delete albums, and add or remove photos.

**Viewer**
- Opens with a zoom from the tapped photo. Swipe between photos, pinch or double-tap to zoom, and swipe down to close.
- Swipe up for details: date, file, dimensions, size, camera and exposure, and location on a map.
- Live Photos play once when you open them.
- Videos play in a built-in player with play/pause, a scrubber, mute and AirPlay in the app bar.
- The ••• app bar has share, favorite, edit and delete, plus rotate, add to album, slideshow and details.

**Organizing and editing**
- **Select mode:** check off photos one at a time, a whole month at once, or start by long-pressing a photo. Then share, favorite, add to album or delete them together.
- **Edit:** rotate and crop (free, original, square or 16:9). Edits are saved through Photos, so they show up in Apple Photos and can be reverted.
- **Slideshow:** a slow pan and zoom with cross-fades.

**Look and home screen**
- **Themes:** black or white background with 20 accent colors. Text sizes follow Dynamic Type, and Reduce Motion replaces the swings and parallax with cross-fades.
- **Home-screen widget:** a live tile of your recent photos or favorites, in small, medium and large sizes.

## Privacy

Luminux reads your photo library on the device through PhotoKit. Nothing is uploaded, and there are no accounts, analytics or network calls. It works with full or limited photo access. Deletions go through the iOS confirmation dialog and land in Recently Deleted.

## Requirements

- iOS 18 or later (iPhone)
- Xcode 26 or later (developed with Xcode 27 and Swift 6)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Getting started

The Xcode project is generated from `project.yml` and isn't checked in.

```bash
xcodegen generate
open Luminux.xcodeproj
```

Before building to a device, set your own team in `project.yml`. Change `DEVELOPMENT_TEAM` and the bundle IDs (`com.buddhanag.luminux`, `.widget`, `.tests`) and the App Group (`group.com.buddhanag.luminux`, used in the entitlements and in `Shared/LiveTileStore.swift`) to IDs your team can sign. Then run `xcodegen generate` again.

Run the tests (use any iOS simulator you have):

```bash
xcodebuild -project Luminux.xcodeproj -scheme Luminux \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test
```

Debug builds include a component gallery. Launch with `-gallery panorama` or `-gallery pivot` to try the panorama, pivot, tiles, app bar, jump list and transitions on their own.

## Project layout

```
Luminux/
  App/            App entry, settings, navigation stack with turnstile transitions
  Core/           PhotoKit library, image loading, editing, live tile export
  DesignSystem/   Panorama, Pivot, tiles with tilt, app bar, jump list, live tile,
                  feather and turnstile motion, colors and type
  Features/       Hub, Collection, Albums, Grid, Viewer (details, editor, video,
                  slideshow), Settings, Permission, debug Gallery
  Resources/      Assets and the Selawik font
LuminuxWidget/    WidgetKit live tile
Shared/           Code shared by the app and the widget
LuminuxTests/     Unit tests (Swift Testing)
```

`PROGRESS.md` tracks what's done and what's next.

## Credits

- [Selawik](https://github.com/microsoft/Selawik) by Microsoft, licensed under the SIL Open Font License 1.1 (see `Luminux/Resources/Fonts/Selawik-OFL.txt`)
- Icons are [SF Symbols](https://developer.apple.com/sf-symbols/)
