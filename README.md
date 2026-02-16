# Darkroom

SwiftUI macOS photo export workflow app for rapid culling, adjustments, and delivery.

## Build A Launchable App

Use the app bundling script to produce a `.app` you can open from Finder:

```bash
./build-app.sh            # debug build
./build-app.sh release    # release build
```

Output locations:
- `dist/debug/Darkroom.app`
- `dist/release/Darkroom.app`

Launch:

```bash
open dist/debug/Darkroom.app
```

Notes:
- The script runs `swift build` first.
- It assembles a macOS app bundle and copies SwiftPM resources so `Bundle.module` works at runtime.

## SwiftPM Command Integration

You can run the same bundling flow through SwiftPM:

```bash
swift package --allow-writing-to-package-directory bundle-app
swift package --allow-writing-to-package-directory bundle-app release
```

## Native Xcode Workflow

This repo includes an `xcodegen` spec so you can work with a native macOS App target.

Generate the project:

```bash
xcodegen generate
```

Open in Xcode:

```bash
open Darkroom.xcodeproj
```

CLI build of native app target:

```bash
xcodebuild -project Darkroom.xcodeproj -scheme Darkroom -configuration Debug -destination 'platform=macOS' build
```
