# Vertical Splits — Niri-style Column Stacking

## Overview

Add vertical stacking within columns, allowing multiple terminal panes per column. Follows niri's absorb/expel model: windows open as columns (existing behavior), then keyboard shortcuts merge/split them vertically within a column.

## Data Model

### New `Column` struct

```swift
struct Column: Identifiable, Equatable, Hashable {
    let id: String
    var tabIds: [String]  // ordered top-to-bottom
}
```

### AppStore changes

- New state: `columns: [String: [Column]]` — maps `projectId` to ordered columns. The array position is the canonical left-to-right order (replaces tab array ordering for spatial layout).
- New state: `columnFocusedTab: [String: String]` — maps `columnId` to last-focused tabId (for restoring focus when navigating between columns)
- `tabs` array stays as flat storage of all tab data (unchanged). Tab order in `tabs` is **no longer the source of truth** for rendering order — `columns` arrays are.
- `activeTabId` still points to the focused pane
- Overview: rename `overviewHighlightedTabId` to `overviewHighlightedColumnId: String?` — overview navigates columns, not individual panes

### Helpers

- `projectColumns(for:)` — returns ordered columns for a project
- `activeColumn` — the column containing `activeTabId`
- `columnFor(tabId:)` — find which column a tab belongs to
- `orderedTabs(for projectId:)` — returns tabs in column-major order (left-to-right columns, top-to-bottom within each) for flat traversals like `Cmd+1-9`, `selectNextTab`, swipe navigation

### Migration from current model

The current implicit model (one tab = one column) is replaced:

- `openTab()` creates a new single-tab `Column` and appends it to `columns[projectId]`
- `closeTab()` removes the tab from its column's `tabIds`. Focus moves to the next pane down in the same column, then the previous pane up, then falls back to the adjacent column. If the column's `tabIds` is now empty, remove the column. Also clean up `columnFocusedTab` for removed columns.
- `removeProject()` must clean up `columns[projectId]` and all `columnFocusedTab` entries for that project's column IDs (iterate columns before deleting them)
- `projectTabs(for:)` unchanged (flat list for sidebar display)
- `selectNextTab()` / `selectPreviousTab()` must use `orderedTabs(for:)` for column-major traversal order (affects both `Cmd+Tab` and swipe navigation)
- `moveActiveTabLeft()` / `moveActiveTabRight()` are replaced by `moveColumnLeft()` / `moveColumnRight()` which swap column positions in the `columns[projectId]` array

### Width tracking

- `WorkspaceLayoutState` keys on `column.id` instead of `tabId`
- All width-related operations (fractions, presets, maximize) operate on columns
- `sync()` takes `columnIds: [String]` instead of `tabIds: [String]`
- Height within a column: split equally among panes (no per-pane height fractions for V1)

### Persistence

Columns are session state for V1 — on restart, each tab gets its own column (current behavior). Column arrangement is not persisted.

## Keyboard Shortcuts

All new shortcuts (`Cmd+J`, `Cmd+K`, `Cmd+Shift+J`, `Cmd+Shift+K`, `Cmd+Shift+E`) are app-level menu intercepts via `CommandGroup` in `BApp.swift`. Like the existing `Cmd+H`/`Cmd+L`, they are intercepted at the menu level before reaching the terminal surface. This is intentional — these keys will not pass through to vim/tmux/etc running inside the terminal.

### New shortcuts

| Action | Shortcut | Description |
|--------|----------|-------------|
| Focus down | `Cmd+J` | Move focus to next pane in same column. No-op at bottom. |
| Focus up | `Cmd+K` | Move focus to previous pane in same column. No-op at top. |
| Absorb from left | `Cmd+Shift+K` | Take bottom-most tab from left column, append to current column. Removes left column if now empty. |
| Absorb from right | `Cmd+Shift+J` | Take bottom-most tab from right column, append to current column. Removes right column if now empty. |
| Expel pane | `Cmd+Shift+E` | Pop active tab out of multi-tab column into new column to the right. No-op on single-tab columns. Focus follows expelled tab. |

### Adjusted existing shortcuts

| Action | Shortcut | Change |
|--------|----------|--------|
| Focus left | `Cmd+H` | Now moves between columns. Restores last-focused pane in target column. |
| Focus right | `Cmd+L` | Same — column-level navigation with pane focus memory. |
| Move column left | `Cmd+Shift+H` | Moves the entire column (with all its panes) by swapping positions in `columns[projectId]`. Replaces `moveActiveTabLeft()`. |
| Move column right | `Cmd+Shift+L` | Same. Replaces `moveActiveTabRight()`. |
| Tab cycling | `Cmd+Tab` | Uses `orderedTabs(for:)` — left-to-right columns, top-to-bottom within each. |
| Jump to tab | `Cmd+1-9` | Same column-major ordering via `orderedTabs(for:)`. |
| Width presets | `Cmd+R` | Operates on the column, not individual panes. |
| Maximize | `Cmd+F` | Operates on the column. |

## Absorb & Expel

### Absorb

Takes a single tab from an adjacent column and appends it to the bottom of the current column.

- `absorbFromLeft()` — takes the bottom-most tab from the column to the left
- `absorbFromRight()` — takes the bottom-most tab from the column to the right
- If the source column had only one tab, the source column is removed (and its `columnFocusedTab` entry cleaned up)
- Focus stays on the current pane (does not shift to absorbed pane)

### Expel

Pops the active tab out of a multi-tab column into its own new column.

- Creates a new single-tab column inserted to the right of the current column
- Focus follows the expelled tab
- No-op when the column has only one tab

## Focus Navigation

### Vertical (within column)

- `Cmd+J` / `Cmd+K` move focus between panes in the same column
- Stops at edges (no wrap-around, consistent with `Cmd+H`/`Cmd+L`)

### Horizontal (between columns)

- `Cmd+H` / `Cmd+L` move focus to adjacent column
- Target column restores its last-focused pane via `columnFocusedTab` map
- Falls back to first (top) pane if no memory for that column
- When leaving a column, the current pane is saved to `columnFocusedTab`

### Sidebar interaction

- `Cmd+H` from the leftmost column's top pane goes to sidebar (existing behavior, unchanged)
- `Cmd+L` from sidebar goes to the first column's remembered pane

## Rendering

### Column view structure

```
Column (rounded rect, existing outer border)
+-- Pane 1 (terminal, top portion)
+-- Divider (1px theme.border horizontal line)
+-- Pane 2 (terminal, bottom portion)
```

- Single-tab columns: identical to current rendering, no visual change
- Multi-tab columns: panes separated by thin horizontal dividers inside the existing column border
- Focused pane gets the accent border on its individual section
- Non-focused panes in the same column get the normal `theme.border`
- Each pane clips its terminal content independently

### Height splitting

Equal split for V1:
- 2 panes = 50% / 50%
- 3 panes = 33% / 33% / 33%
- No draggable vertical resize for V1

### Viewport and scroll

- `stripLayout()` iterates `projectColumns(for:)` and keys frames by `column.id`
- `focusedViewportOffset()` resolves `activeTabId` → `columnFor(activeTabId).id` to look up the frame. It must not use `activeTabId` directly as a frame key.
- `syncColumns()` must be triggered by `onChange(of: columns)` — not just tab ID changes. Absorb/expel change the column list without opening or closing tabs, so `tabs.map(\.id)` won't trigger a re-sync.

### Overview mode

- Thumbnails represent columns, navigated via `overviewHighlightedColumnId`
- `overviewHighlightLeft()` / `overviewHighlightRight()` iterate `projectColumns(for:)` instead of flat tabs
- Multi-tab columns show stacked labels with dividers between them in the thumbnail
- Absorb/expel shortcuts are ignored during overview

## Edge Cases

- **Max panes per column**: No hard limit. Practically 3-4 is useful.
- **Close tab in multi-pane column**: Remove from column's `tabIds`. Focus priority: next pane down in same column → previous pane up in same column → adjacent column's remembered pane. Single remaining pane becomes a normal single-tab column.
- **Close last tab in column**: Column removed entirely (clean up `columnFocusedTab`). Focus moves to adjacent column.
- **Opening a new tab**: Always creates a new column. Use absorb to stack.
- **Overview mode during stacking**: Overview exits before absorb/expel can run.
- **Window resize**: Terminal surfaces auto-resize via SwiftUI frame changes — Ghostty handles this already.
- **Swipe navigation**: `selectNextTab()` / `selectPreviousTab()` (used by swipe gestures in `TerminalView`) use column-major ordering via `orderedTabs(for:)`.

## Files to Modify

| File | Changes |
|------|---------|
| `Blink/Models/Column.swift` | New file — `Column` struct |
| `Blink/Models/Tab.swift` | No changes |
| `Blink/Store/AppStore.swift` | Add `columns` state, `columnFocusedTab`, `overviewHighlightedColumnId` (replaces `overviewHighlightedTabId`). Add column helpers, absorb/expel/focusUp/focusDown, `orderedTabs(for:)`, `moveColumnLeft/Right`. Adjust `openTab`, `closeTab` (column-aware focus fallback), `removeProject` (clean up column state), `selectNextTab/PreviousTab` (column-major order), `overviewHighlightLeft/Right` (iterate columns), `focusLeft/Right` (column navigation with focus memory). |
| `Blink/Views/Shell.swift` | Iterate columns instead of tabs. `stripLayout()` keys frames by `column.id`. `focusedViewportOffset()` resolves `activeTabId → columnId` for frame lookup. Render `VStack` of panes per column. Add `onChange(of: columns)` trigger for `syncColumns()`. Adjust overview thumbnails for multi-pane display and `overviewHighlightedColumnId`. |
| `Blink/Views/WorkspaceLayoutState.swift` | Key on `column.id` instead of `tabId`. `sync()` takes `columnIds` instead of `tabIds`. |
| `Blink/BApp.swift` | Add Cmd+J, Cmd+K, Cmd+Shift+J, Cmd+Shift+K, Cmd+Shift+E shortcuts. Replace moveActiveTabLeft/Right calls with moveColumnLeft/Right. |
| `Blink/Utilities/Constants.swift` | Add column divider height constant |
| `Blink/Terminal/TerminalView.swift` | Swipe navigation callbacks use `selectNextTab()` / `selectPreviousTab()` which now use column-major order (no direct changes needed if AppStore methods are updated, but verify). |
| `BTests/AppStoreTests.swift` | Tests for column operations, absorb, expel, vertical focus, closeTab focus fallback, overview column navigation, orderedTabs ordering |

## Out of Scope (V1)

- Drag-and-drop reordering of columns or panes
- Per-pane height fractions (draggable vertical resize)
- Persisting column arrangement across restarts
- Horizontal splits (panes side-by-side within a column)
