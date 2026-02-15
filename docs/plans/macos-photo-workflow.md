# macOS Photo Workflow App Plan

## Overview
Goal: build a macOS app that accelerates a photo-editing workflow: ultra-fast SD card browsing, selective import into a managed library, basic adjustments (phase 2), and export to user-chosen destinations with size limits. Focus areas:
- **Browse:** detect SD card mounts, enumerate media, show instant grid + detail previews.
- **Import:** stage selections, copy into app-managed library with metadata tracking.
- **Edit:** non-destructive basic adjustments (exposure, WB, crop) added after import pipeline is stable.
- **Export:** batch export with compression presets, custom target path/folder structure.

## Milestone M1 – Foundation & Fast Browsing
- **SD Card Detection:** DiskArbitration-based watcher emitting mount/unmount events and mapping each removable disk to a logical device session.
- **Media Indexer:** lazy directory walker tuned for DCIM-like layouts; gathers path, filename, capture time (via EXIF), and file size without copying data.
- **Thumbnail Pipeline:** background queue pulls embedded previews first; falls back to Core Image thumbnail generation. Cache thumbnails in `~/Library/Caches/Darkroom/Thumbs` using `<device>/<relative-path>` keys with LRU eviction.
- **UI Shell:** SwiftUI virtualized grid with keyboard navigation, selection, filter toggles, and a preview pane streaming higher-res versions on demand.
- **Performance Validation:** stress with ~5k RAW/JPEG mix to keep scroll under 16ms/frame; add lightweight metrics overlay showing frame time and cache hit rate.

## Milestone M2 – Import Pipeline & Library Structure
- **Library Layout:** managed package `~/Pictures/DarkroomLibrary.darkroom` containing `Originals/YYYY/MM/`, `Previews/`, and `Manifests/`. Track assets in SQLite/Core Data (id, device path, import session, ratings, edit stack pointer).
- **Import Queue UI:** staging tray listing flagged photos with progress indicators, rename templates, destination collections, and metadata tweaks. Support drag/drop from browser grid.
- **Copy & Metadata Capture:** ImportManager copies originals in background, verifies checksums, extracts EXIF/IPTC, and commits records atomically. Handle collisions via counters and allow resume after failure.
- **Preview Persistence:** generate multiple preview sizes post-import so browsing works offline. Cache ties back to asset ID instead of device path.
- **Session Management:** log each import session (device id, timestamp, asset count) to prevent duplicates and show “Already Imported” badges.
- **User Feedback:** global activity center summarizing running imports, errors (disk full, permission), and completion notifications linking to the new collection.

## Milestone M3 – Editing Workspace & Adjustment Stack
- **Adjustment Engine:** implement non-destructive stack describing operations (exposure, contrast, highlights/shadows, white balance temp/tint, vibrance, crop/rotate, straighten). Store parameter blobs per asset so originals stay untouched. Back adjustments with Core Image filter graph for GPU-accelerated previews.
- **State Management:** use Combine to propagate adjustment changes to preview canvases with throttled rendering (e.g., debounce 16 ms). Persist unsaved adjustments automatically within the library database and mark dirty assets for export later.
- **Editing UI:** dedicated workspace with filmstrip of imported assets, main preview, adjustment inspector panels, histogram overlay, and before/after toggle. Include keyboard shortcuts and gesture support (pinch zoom, trackpad rotate).
- **Presets System:** allow saving/loading stacks as user presets. Ship a starter set (e.g., clean, vibrant, B&W). Presets store only overridden parameters so they can merge with existing adjustments.
- **History & Revert:** maintain undo/redo stack per asset plus snapshot bookmarks (“Baseline”, “Version B”). Provide quick reset to imported state.
- **Metadata Sync:** when adjustments change exposure/crop, update derived metadata (e.g., preview thumbnails, exported dimension hints) so the export queue has accurate info.
- **Performance Targets:** editing preview updates <50 ms, memory footprint bounded by caching only currently edited asset + neighbors.

## Milestone M4 – Export Workflow & Delivery
- **Export Presets:** define preset objects with file format (JPEG/HEIF/TIFF), target long-edge size, quality/compression, color space, watermark toggle, metadata stripping options. UI for creating/editing presets stored in user defaults.
- **Destination Picker:** build flow using `NSOpenPanel` allowing folder selection + custom subfolder naming templates (e.g., `{date}-{shoot}-{sequence}`). Remember recent destinations per preset.
- **Export Queue UI:** table showing pending/running/completed exports with per-item progress, estimated remaining time, and quick actions (reveal in Finder, retry). Support batching selections from browser/edit view directly into queue.
- **Rendering Pipeline:** use background worker pool that pulls from queue, renders adjusted image at requested size/color space, applies watermark/downscale, and writes to disk. Ensure operations are cancellable and resumable if the app quits mid-run.
- **Size Enforcement:** integrate heuristics to hit target file sizes (quality ramp for JPEG, bit rate hints for HEIF). Warn when target cannot be met (e.g., extreme downscale).
- **Error Handling:** capture disk-full, permission, and render errors; surface them inline with actionable guidance. Maintain audit log for exports for traceability.
- **Notifications & Automation Hooks:** provide system notifications when queues finish and expose Apple Shortcuts intents for “Export with preset X to destination Y”.

## Milestone M5 – Polish, Performance, and Resilience
- **Caching & Offline Mode:** refine preview caches with smart invalidation, support working entirely from library when SD card is absent, and purge cache segments when storage pressure occurs.
- **Input Efficiency:** add configurable keyboard shortcut sets, multi-select gestures, rating/flag hotkeys, and contextual menus for rapid triage.
- **Reliability:** implement background task recovery—app resumes incomplete imports/exports and reports status after relaunch. Add structured logging + analytics toggles for diagnosing field issues.
- **Settings & Preferences:** centralized pane for cache size, default library path, preset management, telemetry opt-in, and SD card auto-eject options.
- **Quality Assurance:** build automated test suites covering import collision cases, adjustment serialization, and export rendering. Integrate with CI for regression detection.
- **Accessibility & Localization Prep:** ensure VoiceOver labels and dynamic type scaling; structure copy for future localization.

## Future Considerations
- iCloud/remote library sync?
- Plug-in hooks for extra adjustments.
- Automation/shortcuts integration.

_Last updated: February 15, 2026._
