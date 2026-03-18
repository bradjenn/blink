# Niri-Style Window Management — Design Spec

> Add Niri-inspired column sizing, keyboard navigation, and column reordering to Blink's workspace.

**Branch:** `feature/niri-workspace`
**Date:** 2026-03-18

---

## Column Sizing

- New windows open at **1/2 viewport width** (default preset).
- Each column stores its own independent width via `WorkspaceLayoutState`.
- Resizing one column never affects others — the strip grows/shrinks and the viewport scrolls to keep the focused column visible.
- Width presets: **1/3, 1/2, 2/3** of viewport, cycled with `Ctrl+R`.
- Maximize toggle with `Ctrl+F` — full viewport width, press again to restore previous size.
- Per-column width is persisted across tab switches and project reopens.

## Keyboard Bindings

| Action              | Binding          | Edge Behavior                                  |
|---------------------|------------------|-------------------------------------------------|
| Focus left          | `Ctrl+H`        | Sidebar if open, else no-op at leftmost         |
| Focus right         | `Ctrl+L`        | No-op at rightmost                              |
| Move column left    | `Ctrl+Shift+H`  | No-op at leftmost (can't swap with sidebar)     |
| Move column right   | `Ctrl+Shift+L`  | No-op at rightmost                              |
| Cycle width preset  | `Ctrl+R`        | 1/3 → 1/2 → 2/3 → 1/3...                      |
| Toggle maximize     | `Ctrl+F`        | Full viewport width ↔ previous size             |

## Sidebar as Spatial Neighbor

- Sidebar is the fixed leftmost "column" — not movable, not resizable via presets.
- `Ctrl+H` from the first terminal column focuses the sidebar (if visible).
- `Ctrl+L` from the sidebar focuses the first terminal column.
- If sidebar is closed, `Ctrl+H/L` only moves between terminal columns.

## Viewport Behavior

- Viewport auto-scrolls to keep the focused column visible after navigation or resize.
- Column spacing remains 10px.
- Strip layout uses per-column widths from `WorkspaceLayoutState` instead of uniform width.

## Files to Modify

- **`Blink/Views/Shell.swift`** — `columnWidth()` reads from `WorkspaceLayoutState`; `stripLayout()` handles non-uniform widths.
- **`Blink/Views/WorkspaceLayoutState.swift`** — wire up `setWidth()`, add preset cycling and maximize toggle logic, add pre-maximize width storage.
- **`Blink/Store/AppStore.swift`** — add `moveTabLeft()`/`moveTabRight()` for reordering; update `toggleSidebarFocus()`/`focusTerminal()` to integrate with `Ctrl+H/L` navigation.
- **`Blink/BApp.swift`** — add keyboard shortcut bindings for all new actions.
- **`Blink/Utilities/Constants.swift`** — add width preset fractions array, update default column width.

## Existing Code to Reuse

- `WorkspaceLayoutState.width(for:projectId:default:)` and `setWidth(_:for:projectId:)` — already implemented, just not called.
- `WorkspaceLayoutState.sync(projectId:tabIds:defaultWidth:)` — already keeps column state in sync with tab list.
- `selectNextTab()` / `selectPreviousTab()` — existing navigation logic to extend with sidebar awareness.
- `alignActiveTab(viewportWidth:animated:)` — existing viewport scroll logic, works with any column width.

## Out of Scope

- Floating tool layer (future iteration).
- Overview mode (future iteration).
- Multi-window columns / tabbed stacking (future iteration).
- Fine-grained resize (Mod+Minus/Equal) — presets are sufficient for now.
