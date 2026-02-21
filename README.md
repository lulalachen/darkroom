# Darkroom

SwiftUI macOS photo export workflow app for rapid culling, adjustments, and delivery.

## Build A Launchable App

Use native Xcode build tooling to produce a `.app` you can open from Finder:

```bash
xcodebuild -project Darkroom.xcodeproj -scheme Darkroom -configuration Debug -destination 'platform=macOS' -derivedDataPath dist/xcode build
xcodebuild -project Darkroom.xcodeproj -scheme Darkroom -configuration Release -destination 'platform=macOS' -derivedDataPath dist/xcode build
```

Output locations:
- `dist/xcode/Build/Products/Debug/Darkroom.app`
- `dist/xcode/Build/Products/Release/Darkroom.app`

Launch:

```bash
open dist/xcode/Build/Products/Debug/Darkroom.app
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
xcodebuild -project Darkroom.xcodeproj -scheme Darkroom -configuration Debug -destination 'platform=macOS' -derivedDataPath dist/xcode build
```
