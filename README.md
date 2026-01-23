# PolarClock

A modern macOS screen saver featuring a polar clock visualization with smooth animations.

Inspired by [pixelbreaker's Polar Clock](https://www.pixelbreaker.com/polarclock).

![PolarClock demo](PolarClock.gif)

## Features

- 6 concentric rings representing time units (month, day, weekday, hours, minutes, seconds)
- Smooth 60fps animation with nanosecond precision
- Snap-back animation when arcs complete full rotation
- Adaptive background (dark/light mode support)
- Optimized layout for modern MacBooks with notches

## Installation

### Homebrew (recommended)

```bash
brew install --cask ryanrishi/tap/polarclock
```

### Manual

1. Download the latest `.saver` file from [Releases](https://github.com/ryanrishi/PolarClock/releases)
2. Double-click to install, or manually copy to `~/Library/Screen Savers/`
3. Open System Settings → Screen Saver and select PolarClock

## Building from Source

```bash
# Build
xcodebuild -scheme PolarClock -configuration Debug build

# Install
cp -R ~/Library/Developer/Xcode/DerivedData/PolarClock-*/Build/Products/Debug/PolarClock.saver ~/Library/Screen\ Savers/

# Clear caches
killall cfprefsd WallpaperAgent legacyScreenSaver "System Settings" 2>/dev/null
```

See `CLAUDE.md` for detailed development notes.

## Requirements

- macOS 15.5 or later
- Xcode 17+ (for building from source)

## License

MIT
