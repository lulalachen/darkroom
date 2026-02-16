# macOS Photo Workflow App Plan

## Overview
Goal: build a macOS app that accelerates a photo-editing workflow: ultra-fast SD card browsing, non-destructive adjustments, and export to user-chosen destinations with size limits. Focus areas:
- **Browse:** detect SD card mounts, enumerate media, show instant grid + detail previews.
- **Edit:** non-destructive basic adjustments (exposure, WB, crop) with preset/history support.
- **Export:** batch export with compression presets, custom target path/folder structure.

## Status
- **Current milestone:** M5 – Polish, Performance, and Resilience (Completed February 16, 2026)
- **Last completed milestone:** M5 – Polish, Performance, and Resilience (Completed February 16, 2026)
- **M5 completion:** 100% (as of February 16, 2026)
- **Product pivot:** February 16, 2026 — import/session features deprecated in favor of a single export-first workflow.
- **Next implementation plan:** `docs/plans/m5-adjustments-export-ui-refinement.md` (Started February 16, 2026)
- **Progress cadence:** update this section at each implementation checkpoint.

## Product Direction Update (February 16, 2026)
- Darkroom is now an export-only workflow product.
- Green tags are treated as export intent and can be queued/run directly to final destination presets.
- Import session/history/activity features from M2 are considered deprecated and not part of active roadmap scope.

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

### Next Milestone Execution Plan (Current)
Focus this cycle on a shippable M2 slice: durable import records + duplicate prevention + resilient import UX.

**Why this next:** M1 browsing is usable, and the app already supports basic copy-import from Green-tagged photos. The biggest product risk now is losing provenance and re-importing duplicates without reliable session tracking.

**Scope (in):**
1. Library package bootstrap and stable folder layout (`Originals/`, `Previews/`, `Manifests/`).
2. Import manifest persistence (SQLite preferred) with `assets` and `import_sessions` tables.
3. Content hashing during import (`SHA256`) and duplicate detection before copy.
4. Import status model with explicit states (`queued`, `copying`, `hashing`, `done`, `failed`) surfaced in UI.
5. Resume-safe imports by recording partial progress and skipping completed files on retry.

**Scope (out):**
1. Adjustment stack and edit workspace.
2. Export presets and delivery queue.
3. Cloud sync and automation integrations.

**Implementation tasks:**
1. Add `LibraryManager` to create/validate library structure at startup and expose paths.
2. Replace ad-hoc `ImportManager` copy loop with a pipeline:
   - stage import session row,
   - preflight duplicate check by hash/path fingerprint,
   - copy to unique destination,
   - verify copied hash,
   - commit asset + session links transactionally.
3. Introduce a lightweight persistence layer (`ImportStore`) and migration versioning.
4. Extend `BrowserViewModel` with per-asset import progress + final summary counts (`imported`, `skipped-duplicate`, `failed`).
5. Add failure handling for permission denied, missing source file, out-of-space, and cancelled import.
6. Add tests for collision naming, duplicate detection, and interrupted import resume.

**Acceptance criteria:**
1. Re-importing the same files does not create duplicate originals.
2. Import interruption (app quit/relaunch) can continue without re-copying completed files.
3. Each import run is queryable as a session with timestamp, source volume, and outcome counts.
4. UI reports per-run outcomes with actionable errors, not generic failure text.
5. Automated tests cover at least:
   - filename collision behavior,
   - duplicate-skip behavior,
   - resume behavior after partial completion.

**Exit artifact for this milestone:**
1. `DarkroomLibrary.darkroom` created automatically and versioned.
2. Import history view (minimal list) showing last N sessions and counts.
3. Verified import reliability on a sample card with mixed JPEG/RAW files.

### M2 Completion Notes (February 16, 2026)
1. Implemented persistent import sessions/items/assets via SQLite with schema migrations.
2. Implemented resumable import processing with explicit item states, duplicate detection, and retry flows.
3. Implemented staging tray UX, activity/history panels, and “Already Imported” badges.
4. Implemented export destination flow with `YYYY-MM-DD/<photo-name>` format under chosen path/folder.
5. Implemented metadata application path (embedded when possible, sidecar fallback).
6. Added/updated tests for collision handling, duplicate skip, resume, retry, metadata sidecar, and export path behavior.

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

### M4 Completion Notes (February 16, 2026)
1. Implemented export preset system with editable options (format, long edge, quality, color space, metadata strip toggle, watermark toggle/text, max target size).
2. Implemented destination templating with `{date}`, `{shoot}`, `{sequence}` substitutions and per-preset recent destination memory.
3. Implemented export queue sheet with enqueue/start/cancel/retry/clear controls, per-item status, size, warnings, reveal-in-Finder, and ETA.
4. Implemented background export worker pool (2 workers) with cancellable run loop, resumable queue cache restored on app relaunch, and auto-resume of pending queue.
5. Implemented render/write pipeline for JPEG/HEIF/TIFF (plus original-copy mode), downscale by long edge, optional text watermark, and file-size target fallback heuristics.
6. Implemented export error mapping (disk-full/permission/path) and JSONL audit logging at `~/Library/Logs/Darkroom/export-audit.jsonl`.
7. Implemented completion notifications and Apple Shortcuts App Intent hook (`ExportWithPresetIntent`) for “preset + destination” triggering.
8. Added export-focused automated tests for destination/template behavior, collision naming, and target-size warning behavior.

## Milestone M5 – Polish, Performance, and Resilience
- **Caching & Offline Mode:** refine preview caches with smart invalidation, support working entirely from library when SD card is absent, and purge cache segments when storage pressure occurs.
- **Input Efficiency:** add configurable keyboard shortcut sets, multi-select gestures, rating/flag hotkeys, and contextual menus for rapid triage.
- **Reliability:** implement background task recovery—app resumes incomplete imports/exports and reports status after relaunch. Add structured logging + analytics toggles for diagnosing field issues.
- **Settings & Preferences:** centralized pane for cache size, default library path, preset management, telemetry opt-in, and SD card auto-eject options.
- **Quality Assurance:** build automated test suites covering import collision cases, adjustment serialization, and export rendering. Integrate with CI for regression detection.
- **Accessibility & Localization Prep:** ensure VoiceOver labels and dynamic type scaling; structure copy for future localization.

### M5 Progress Notes (February 16, 2026)
1. Added centralized Settings UI with controls for thumbnail/full-image cache size, telemetry logging toggle, auto-eject toggle, shortcut profile, and default library path.
2. Upgraded thumbnail and full-image caches to LRU with runtime-configurable limits and explicit clear operations.
3. Added memory-pressure handling that purges caches and reports status.
4. Added offline browsing fallback by exposing Darkroom library originals as a selectable sidebar source.
5. Added configurable shortcut profiles (`Z/X/C` and `1/2/0`) plus grid context menu actions for faster triage/staging/export queueing.
6. Added structured JSONL telemetry logging for import/export completion/failure and memory-pressure events (gated by preference).
7. Added automated cache behavior tests for eviction and clear paths.
8. Added thumbnail accessibility labels to improve VoiceOver announcements.
9. Added GitHub Actions CI workflow running `swift build`, `swift test`, and app bundle generation.
10. Added per-asset star ratings with quick actions (context menu + `R` hotkey cycle) for faster triage.

## Future Considerations
- iCloud/remote library sync?
- Plug-in hooks for extra adjustments.
- Automation/shortcuts integration.

_Last updated: February 16, 2026._
