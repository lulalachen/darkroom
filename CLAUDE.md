# Darkroom — Claude Context

SwiftUI macOS photo export workflow app for rapid culling, adjustments, and delivery.

## Build & Development Commands

```bash
# Compile (Swift Package Manager)
swift build

# Run all tests
swift test

# Regenerate Xcode project from project.yml
xcodegen generate

# Native debug build (required for feature review)
xcodebuild -project Darkroom.xcodeproj -scheme Darkroom -configuration Debug -destination 'platform=macOS' -derivedDataPath dist/xcode build

# Native release build
xcodebuild -project Darkroom.xcodeproj -scheme Darkroom -configuration Release -destination 'platform=macOS' -derivedDataPath dist/xcode build

# Launch the built app
open dist/xcode/Build/Products/Debug/Darkroom.app
```

Build outputs: `dist/xcode/Build/Products/{Debug,Release}/Darkroom.app`

## Feature Review Workflow

When a feature is complete, always run a native debug build and launch the app before marking it ready for review. Don't skip this step — `swift build` alone doesn't exercise the full Xcode target configuration.

## Project Structure

```
Sources/          # All app source code
  DarkroomApp.swift         # App entry point, WindowGroup/Settings/About setup
  ContentView.swift         # Main UI (large — ~100KB)
  BrowserViewModel.swift    # Central @MainActor ObservableObject (~54KB)
  AdjustmentEngine.swift    # CoreImage processing pipeline
  ExportManager.swift       # Batch export orchestration (actor)
  AdjustmentStore.swift     # Per-image adjustment persistence (actor)
  Models.swift              # Core types: PhotoAsset, PhotoTag, AdjustmentSettings, ExportPreset
  EditingModels.swift       # Editing state types
  ExportPipelineModels.swift # Export state types
  ThumbnailCache.swift      # LRU thumbnail cache (actor)
  PhotoEnumerator.swift     # Recursive photo discovery
  MetadataWriter.swift      # Writes metadata to exported images
  LUTLibrary.swift          # Bundled LUT resources (Fujifilm film sims)
  CubeLUT.swift             # .cube LUT parser, SIMD interpolation
  FinderTagManager.swift    # macOS Finder tag integration
  FullImageLoader.swift     # Full-resolution image loading
  PreviewGenerator.swift    # Thumbnail/preview generation
  AppPreferences.swift      # @MainActor singleton for user settings
  LibraryManager.swift      # Library folder structure management
  VolumeWatcher.swift       # Mount/unmount detection
  StructuredLogger.swift    # Structured logging
  ExportAppIntents.swift    # Siri/Shortcuts integration
  Resources/                # Icons, asset catalogs, LUT files
Tests/            # XCTest suites
docs/plans/       # Design and implementation planning notes
dist/xcode/       # Generated build products (gitignored)
```

## Architecture

**Concurrency model**: Swift actors for all I/O and processing (`AdjustmentStore`, `AdjustmentEngine`, `ExportManager`, `ThumbnailCache`, `LibraryManager`). View layer uses `@MainActor` ObservableObject (`BrowserViewModel`, `AppPreferences`).

**Data flow**:
1. `PhotoEnumerator` discovers photos from volumes/directories
2. `BrowserViewModel` manages asset display, filtering, tagging, undo/redo
3. `AdjustmentEngine` applies edits through a CoreImage pipeline (v2 default)
4. `ThumbnailCache` / `FullImageLoader` serve previews and high-res display
5. `ExportManager` orchestrates batch exports (max 2 concurrent workers)

**Persistence**: Adjustment settings and presets stored as JSON in `~/Pictures/DarkroomLibrary.darkroom/Manifests/`.

**Key types**:
- `PhotoAsset` — core photo model (URL, filename, capture date, file size)
- `PhotoTag` — `keep` or `reject`
- `AdjustmentSettings` — 24 parameters (exposure, contrast, highlights, shadows, color temp, LUT, grain, vignette, crop, etc.)
- `ExportPreset` — format (JPEG/HEIF/TIFF/Original), resolution, quality, color space, watermark

## Coding Style

- Language: Swift 5.8+, macOS 13+ deployment target
- Indentation: 4 spaces
- Types/protocols: `UpperCamelCase`; functions/properties/variables: `lowerCamelCase`
- Prefer small, focused types per file with explicit names (`ExportPreset`, `BrowserViewModel`)
- Test files: `*Tests.swift`; test functions: `test...` (e.g., `testRunQueueAddsNumericSuffixOnCollision`)

## Testing

Framework: XCTest. Tests cover export workflows, cache behavior, adjustment pipeline, and browser UI state. Use deterministic file-system sandboxes; assert both success counts and output artifacts. Run `swift test` before opening any PR.

## Commit Messages

Short, imperative: `Verb + scope + outcome` (e.g., `Fix export metadata and preview UI`, `Refine export preview sizing logic`).

## Supported Image Formats

JPG, PNG, HEIC, HEIF, RAW (ARW, CR2, CR3, NEF, RAF, RW2, DNG). Sorted by capture date descending by day, chronological within day.
