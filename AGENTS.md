# Repository Guidelines

## Project Structure & Module Organization
Darkroom is a SwiftPM-based macOS app with SwiftUI UI and export pipeline logic.

- `Sources/`: app code (`DarkroomApp.swift`, `ContentView.swift`, view models, export/metadata/cache managers).
- `Sources/Resources/`: bundled assets (icons, asset catalogs).
- `Tests/`: XCTest suites (for export workflow, cache behavior, and browser workflow).
- `docs/plans/`: design and implementation planning notes.
- `dist/xcode/`: generated app products from native Xcode CLI builds.

## Build, Test, and Development Commands
- `swift build`: compile the package target (`darkroom`).
- `swift test`: run all XCTest suites in `Tests/`.
- `xcodegen generate`: regenerate `Darkroom.xcodeproj` from `project.yml`.
- `xcodebuild -project Darkroom.xcodeproj -scheme Darkroom -configuration Debug -destination 'platform=macOS' -derivedDataPath dist/xcode build`: native debug build.
- `xcodebuild -project Darkroom.xcodeproj -scheme Darkroom -configuration Release -destination 'platform=macOS' -derivedDataPath dist/xcode build`: native release build.

## Feature Review Handoff Workflow
- When a feature is complete and ready for review, always run a native Xcode debug build:
  `xcodebuild -project Darkroom.xcodeproj -scheme Darkroom -configuration Debug -destination 'platform=macOS' -derivedDataPath dist/xcode build`.
- After a successful debug build, launch the built app for review:
  `open /Users/lulalachen/Programming/darkroom/dist/xcode/Build/Products/Debug/Darkroom.app`.

## Coding Style & Naming Conventions
- Language: Swift 5.8+, macOS 13+.
- Indentation: 4 spaces; keep line lengths readable.
- Types/protocols: `UpperCamelCase`; functions/properties/locals: `lowerCamelCase`.
- Test files end in `*Tests.swift`; test functions use `test...` naming (for example, `testRunQueueAddsNumericSuffixOnCollision`).
- Prefer small, focused types per file and explicit model names (`ExportPreset`, `BrowserViewModel`).

## Testing Guidelines
- Framework: XCTest (`import XCTest`).
- Add or update tests for export behavior, metadata handling, and UI workflow state changes when modifying related code.
- Use deterministic file-system sandboxes in tests (see existing export tests) and assert both success counts and output artifacts.
- Run `swift test` before opening a PR.

## Commit & Pull Request Guidelines
- Existing history favors short, imperative commit messages (for example, `Fix export metadata and preview UI`, `Update browser selection labels`).
- Prefer: `Verb + scope + outcome` (for example, `Refine export preview sizing logic`).
- PRs should include a concise summary of behavior changes, test evidence (`swift test` output or equivalent), screenshots/GIFs for UI changes, and a linked issue/task when available.
