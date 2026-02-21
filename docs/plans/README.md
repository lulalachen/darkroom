# Planning Documents

This directory stores long-lived planning documents for the project. Each plan should be saved as a Markdown file named `<project>-plan.md` (e.g., `macos-photo-workflow.md`).

## How to add or update a plan
1. Create a new Markdown file that summarizes goals, milestones, and decisions.
2. Keep sections decision-complete so another contributor can implement without extra clarification.
3. Update existing plan files when requirements change; include timestamps or version notes if needed.
4. Leave the `.gitkeep` file in place so the folder remains tracked even if all plans are temporarily removed.

Feel free to expand this structure with subfolders (e.g., `archive/`, `active/`) if planning documents grow over time.

## Build Context
To build a launchable macOS app bundle while working from this repository, use:

```bash
xcodebuild -project Darkroom.xcodeproj -scheme Darkroom -configuration Debug -destination 'platform=macOS' -derivedDataPath dist/xcode build
```

The app bundle is produced at `dist/xcode/Build/Products/Debug/Darkroom.app` (or `dist/xcode/Build/Products/Release/Darkroom.app` when using `-configuration Release`).

For native Xcode app development workflow, generate the project with:

```bash
xcodegen generate
```
