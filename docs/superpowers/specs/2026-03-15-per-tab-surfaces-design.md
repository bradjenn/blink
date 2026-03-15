# Per-Tab Terminal Surfaces

## Goal

Each tab gets its own independent terminal surface with its own shell process. Tabs open at the project's working directory. Switching tabs preserves running processes. Tab titles auto-update from the shell. Sidebar pulses indicate unread activity on background tabs.

## Architecture

Introduce a `SurfaceManager` that owns all terminal surfaces keyed by tab ID. The SwiftUI layer looks up surfaces by tab ID instead of creating one globally. The Ghostty action callback and close_surface callback are wired up to handle title changes and shell exit events.

## Design

### 1. SurfaceManager

**File:** `Blink/Terminal/SurfaceManager.swift`

An `@Observable` class that manages the lifecycle of all terminal surfaces:

- **`surfaces: [String: TerminalSurfaceView]`** — maps tab ID → live NSView with its terminal surface
- **`surfaceToTab: [OpaquePointer: String]`** — reverse lookup: ghostty_surface_t pointer → tab ID (for routing action callbacks back to tabs)
- **`createSurface(tabId:, app:, workingDirectory:)`** — creates a `TerminalSurfaceView`, stores it in the dictionary, registers in reverse lookup
- **`destroySurface(tabId:)`** — calls `teardown()` on the view (which frees the surface and nils the pointer), removes from both dictionaries. This kills the shell process immediately.
- **`surface(for tabId:)`** — returns the existing view or nil
- **`tabId(for surface:)`** — reverse lookup from ghostty_surface_t to tab ID

**Surface cleanup — single-owner pattern:** Only `destroySurface` frees the ghostty surface (via `view.teardown()`). The view's `deinit` checks for nil before freeing, preventing double-free. This is critical because SwiftUI may hold references to the view beyond the SurfaceManager's removal (e.g., during removal animations).

Owned by `BApp.swift` as a `@State` object (SurfaceManager is `@Observable`), passed down alongside `GhosttyApp`.

### 2. TerminalSurfaceView Changes

- **`workingDirectory` parameter** — stored at init, used in `viewDidMoveToWindow` when creating the surface. The C string lifetime is managed via `withCString` during `ghostty_surface_new`:
  ```swift
  workingDirectory.withCString { cPath in
      cfg.working_directory = cPath
      surface = ghostty_surface_new(app, &cfg)
  }
  ```
- **`focus()` method** — calls `window?.makeFirstResponder(self)` to grab keyboard focus (guards `window != nil`)
- **`teardown()` method** — frees the ghostty surface and nils the pointer. Called by SurfaceManager on tab close. Prevents double-free with `deinit`:
  ```swift
  func teardown() {
      if let surface { ghostty_surface_free(surface) }
      surface = nil
  }
  deinit { teardown() }
  ```
- Surface creation stays in `viewDidMoveToWindow` — Metal needs the NSView in a window to bind

### 3. TerminalView (SwiftUI) Changes

```swift
struct TerminalView: NSViewRepresentable {
    let tabId: String
    let ghosttyApp: GhosttyApp
    let surfaceManager: SurfaceManager
    let workingDirectory: String
}
```

- `makeNSView` — looks up `surfaceManager.surface(for: tabId)`. If found, returns it. If not, creates a new one via `surfaceManager.createSurface(...)` and returns it.
- `updateNSView` — calls `focus()` on the view

**Critical: `.id(tabId)` in Shell.swift.** `makeNSView` is called exactly once per `NSViewRepresentable` lifetime. To swap the underlying NSView when switching tabs, the `TerminalView` in Shell.swift must use `.id(tabId)` so SwiftUI treats each tab switch as a new view identity, calling `makeNSView` with the correct surface from SurfaceManager.

### 4. Tab Lifecycle in AppStore

- **`AppTab.label` changes from `let` to `var`** — required for title updates
- **New tab (+)** — creates an `AppTab` with auto-incrementing label ("Terminal 1", "Terminal 2", etc. per project). SurfaceManager creates the surface.
- **Close tab (x)** — `AppStore.closeTab()` removes the tab. The caller also tells `SurfaceManager.destroySurface(tabId:)` to free the surface.
- **Remove project** — `AppStore.removeProject()` removes all tabs for that project. All associated surfaces are destroyed.

New methods on AppStore:
- `openTab(projectId:) -> AppTab` — creates and adds a new shell tab for a project, returns it
- Tab numbering: count existing tabs for the project + 1

### 5. Auto-Updating Tab Titles

Wire up `GHOSTTY_ACTION_SET_TITLE` in the GhosttyApp action callback:

1. The action callback receives a title string and a target surface
2. Extract the `ghostty_surface_t` from `target.target.surface`
3. Use `SurfaceManager.tabId(for: surface)` to find which tab owns it
4. Update `AppTab.label` in AppStore with the new title
5. SwiftUI tab bar re-renders automatically

**Thread safety:** The action callback can be called from any thread. All AppStore mutations must be dispatched to the main thread via `DispatchQueue.main.async`.

### 6. Sidebar Unread Activity Indicator

Track which background tabs have had new output since the user last viewed them:

- **`unreadTabs: Set<String>`** on AppStore — tab IDs with unseen activity
- When the action callback receives `GHOSTTY_ACTION_SET_TITLE` for a non-active tab, add the tab's ID to `unreadTabs` (title changes are a reasonable proxy for command activity — fires when the shell prompt re-renders after each command)
- When the user switches to a tab, remove it from `unreadTabs`
- The sidebar's per-project pulse dot activates when any tab for that project is in `unreadTabs`
- The existing pulse animation in `SidebarProjectItem` is already implemented — it just needs to be wired to this set instead of the current dummy state

### 7. Shell.swift Changes

The content area changes from:
```swift
TerminalView(app: ghosttyApp)
```
to:
```swift
if let tabId = store.activeTabId, let projectId = store.activeProjectId,
   let project = store.projects.first(where: { $0.id == projectId }) {
    TerminalView(
        tabId: tabId,
        ghosttyApp: ghosttyApp,
        surfaceManager: surfaceManager,
        workingDirectory: project.path
    )
    .id(tabId)  // Forces SwiftUI to call makeNSView on tab switch
}
```

### 8. Focus Behavior

The terminal grabs keyboard focus when:
- A new tab is created (after surface is ready)
- User clicks a tab in the tab bar
- User clicks a project in the sidebar (activates first tab)
- User dismisses settings (returns to terminal)

This is handled in `TerminalView.updateNSView` — calls `focus()` on the view. The `.id(tabId)` pattern means `makeNSView` fires on each tab switch, and `updateNSView` fires immediately after, triggering focus.

### 9. GhosttyApp Callback Wiring

**Action callback** changes from stub `return false` to handling:
- `GHOSTTY_ACTION_SET_TITLE` — update tab label (dispatch to main thread)

**`close_surface_cb`** changes from no-op to:
- Look up the tab ID from the surface via SurfaceManager
- Remove the tab from AppStore and destroy the surface
- Dispatch to main thread

Note: `GHOSTTY_ACTION_CLOSE_SURFACE` does not exist in the Ghostty API. Shell exit is detected via the `close_surface_cb` runtime callback, not the action system.

To route callbacks back to Swift, `GhosttyApp` holds weak references to `AppStore` and `SurfaceManager` (set after init in BApp.swift).

All other actions continue to return false.

## Files Summary

| File | Action | Purpose |
|------|--------|---------|
| `Blink/Terminal/SurfaceManager.swift` | Create | Owns all surfaces, keyed by tab ID, reverse lookup |
| `Blink/Terminal/TerminalSurfaceView.swift` | Modify | Accept working directory, add focus() + teardown() |
| `Blink/Terminal/TerminalView.swift` | Modify | Look up surfaces from SurfaceManager |
| `Blink/Terminal/GhosttyApp.swift` | Modify | Wire action callback + close_surface_cb, hold weak refs |
| `Blink/Store/AppStore.swift` | Modify | Add openTab(), unreadTabs, tab numbering |
| `Blink/Views/Shell.swift` | Modify | Pass tabId + workingDirectory, use .id(tabId) |
| `Blink/Views/TabBar.swift` | Modify | Wire + button to openTab() |
| `Blink/Views/SidebarProjectItem.swift` | Modify | Wire pulse to unreadTabs |
| `Blink/BApp.swift` | Modify | Create SurfaceManager, wire to GhosttyApp |
| `Blink/Models/Tab.swift` | Modify | Make label var, remove dummy data |

## Success Criteria

1. Each tab has its own independent shell — `pwd` shows the project's directory
2. Running processes (dev servers, etc.) stay alive when switching tabs
3. Closing a tab kills its shell immediately
4. The + button creates a new tab at the project's directory
5. Tab titles update automatically when running commands
6. Sidebar dots pulse when a background tab has new output
7. Terminal is focused on tab create, tab switch, and project click
