# Darkroom

SwiftUI macOS app for rapid photo culling, adjustments, and batch export.

![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue)
![Swift](https://img.shields.io/badge/swift-5.8%2B-orange)

## Features

- **Culling** — quickly tag photos as keep or reject with keyboard shortcuts
- **Adjustments** — exposure, contrast, highlights/shadows, white balance, vibrance, split-toning, grain, vignette, crop, and more (24 parameters)
- **LUT support** — apply 3D color lookup tables including bundled Fujifilm film simulations
- **Batch export** — JPEG, HEIF, TIFF, or original format with configurable resolution, quality, and color space
- **Presets** — built-in adjustment presets (Clean, Vibrant, B&W, Vintage) and export presets (Social, Web, Print, Original)
- **Thumbnail caching** — fast LRU cache for responsive browsing
- **Finder integration** — tag management synced with macOS Finder
- **Shortcuts support** — Apple Shortcuts/Siri Intents for export automation

## Requirements

- macOS 13.0+
- Xcode 15+ (for native builds)
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build

```bash
# Generate the Xcode project
xcodegen generate

# Debug build
xcodebuild -project Darkroom.xcodeproj -scheme Darkroom -configuration Debug -destination 'platform=macOS' -derivedDataPath dist/xcode build

# Release build
xcodebuild -project Darkroom.xcodeproj -scheme Darkroom -configuration Release -destination 'platform=macOS' -derivedDataPath dist/xcode build
```

Output:
- `dist/xcode/Build/Products/Debug/Darkroom.app`
- `dist/xcode/Build/Products/Release/Darkroom.app`

```bash
# Launch
open dist/xcode/Build/Products/Debug/Darkroom.app
```

## Development

```bash
# Compile (Swift Package Manager)
swift build

# Run tests
swift test

# Open in Xcode
open Darkroom.xcodeproj
```

## Supported Formats

JPG, PNG, HEIC, HEIF, and RAW (ARW, CR2, CR3, NEF, RAF, RW2, DNG).

## Library

Darkroom stores adjustments and manifests in `~/Pictures/DarkroomLibrary.darkroom/`.
