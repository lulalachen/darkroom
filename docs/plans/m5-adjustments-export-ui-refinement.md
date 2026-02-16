# M5 Adjustments and Export UI Refinement Plan

## Goal
Implement focused UX refinements for the preview/adjustments workspace and top toolbar export flow.

## Scope
1. Add an adjustable vertical divider between the large preview area and bottom adjustments panel.
2. Add `Cmd + E` keyboard shortcut to toggle the bottom adjustments panel.
3. Increase adjustment control row height and slider visual size for easier manipulation.
4. Remove top-toolbar `Green`, `Red`, and `Clear` actions.
5. Replace top-toolbar `Start Export` with:
   - `Shoot name` input
   - export icon action at the far right for quick export.
6. Add date-grouped headers in the left asset scroll area (next to preview):
   - section headers by created date
   - date sections ordered newest to oldest
   - assets within each date ordered chronologically.
7. Add user library loading support:
   - user can select any folder containing photo folders
   - selected folders appear under Libraries in sidebar
   - selecting a library folder browses and previews photos from that folder tree
   - library folder list persists across app relaunch.

## Implementation Notes
1. Use SwiftUI `VSplitView` in the preview pane to provide native drag-resize behavior for preview vs adjustments.
2. Handle `Cmd + E` in the existing key monitor in `BrowserDetailView`, while preserving existing arrow/tag hotkeys.
3. Bind the top-bar shoot name directly to `viewModel.exportDestination.shootName`.
4. Implement quick export icon action as:
   - queue selected asset
   - start export queue immediately.
5. Keep existing export queue sheet and detailed export settings unchanged.

## Acceptance Criteria
1. Dragging the divider resizes preview and adjustments panel height.
2. `Cmd + E` toggles adjustments panel visibility on and off.
3. Adjustment rows are visually taller and sliders use a larger control size.
4. Top toolbar no longer shows `Green`, `Red`, `Clear`, or `Start Export` text button.
5. Top toolbar shows `Shoot name` input and right-aligned export icon button.

## Status
- **State:** In Progress
- **Started:** February 16, 2026
- **Owner:** Codex
- **Update (February 16, 2026):** Added date-section grouping + ordering execution item; implementation started.
- **Update (February 16, 2026):** Added and implemented external library folder loading with persistent sidebar entries.
