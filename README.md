# Darkroom

SwiftUI macOS photo workflow app.

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
