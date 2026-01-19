# PolarClock Development Notes

## Build & Install

```bash
# Build
xcodebuild -scheme PolarClock -configuration Debug build

# Install (replace existing)
rm -rf ~/Library/Screen\ Savers/PolarClock.saver
cp -R ~/Library/Developer/Xcode/DerivedData/PolarClock-cnaqmgbdnctqymdhjhtlzabxfape/Build/Products/Debug/PolarClock.saver ~/Library/Screen\ Savers/

# IMPORTANT: Kill caches before testing (macOS aggressively caches screen savers)
killall cfprefsd WallpaperAgent legacyScreenSaver "System Settings" 2>/dev/null

# Then open System Settings → Screen Saver to preview
```

## One-liner for build + install + clear cache

```bash
xcodebuild -scheme PolarClock -configuration Debug build && rm -rf "/Users/ryanrishi/Library/Screen Savers/PolarClock.saver" && cp -R "/Users/ryanrishi/Library/Developer/Xcode/DerivedData/PolarClock-cnaqmgbdnctqymdhjhtlzabxfape/Build/Products/Debug/PolarClock.saver" "/Users/ryanrishi/Library/Screen Savers/" && killall cfprefsd WallpaperAgent legacyScreenSaver "System Settings" 2>/dev/null; echo "Installed - open System Settings"
```

## Project Structure

- `PolarClock/PolarClockView.swift` - All screen saver code (single file)
  - `PolarClockScreenSaverView` - NSView subclass that hosts SwiftUI
  - `PolarClockContentView` - Main SwiftUI view with TimelineView for 60fps animation
  - `ClockFace` - Renders all 6 rings
  - `ArcRing` - Reusable component for single arc + label
  - `TimeCalculator` - Computes progress (0-1) and labels for each time unit

## Design

- 6 rings (inner → outer): month, day, weekday, hours, minutes, seconds
- Colors: cyan, green, yellow, orange, red, purple
- Start position: 12 o'clock (top, -90 degrees)
- Labels: white text, rotated to follow arc tangent, positioned at arc endpoint
- Background: adaptive (black in dark mode, white in light mode)

## Xcode Setup (one-time)

If `xcodebuild` fails with "requires Xcode":
```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
```
