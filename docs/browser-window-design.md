# Blink Browser Window Design

## Summary

Blink should add a browser as a first-class workspace surface, not as a terminal special case and not as a full browser product.

The right first version is:

- split-able and move-able like any other pane
- focused on project workflows: localhost preview, docs, auth flows, PR links
- built on public WebKit APIs
- explicit about what it will not do yet

The wrong first version is:

- private WebKit inspector hacks
- a portal host layered over the whole window
- a full automation API
- profiles, sync, downloads, import, or browser-history product scope

This design borrows the good parts of cmux:

- browser and terminal are peer surfaces
- focus intent is explicit
- browser state is centralized
- browser edge cases get dedicated tests

It intentionally avoids the parts that make cmux expensive to own:

- private DevTools integration
- window-level `WKWebView` portal hosting
- monolithic browser files
- remote-proxy and automation scope in the MVP

## Why This Fits Blink

Blink already has the right high-level shape for a browser surface:

- [`Blink/Store/AppStore.swift`](../Blink/Store/AppStore.swift) owns workspace state and actions
- [`Blink/Views/Shell.swift`](../Blink/Views/Shell.swift) renders panes and columns
- [`Blink/Models/Tab.swift`](../Blink/Models/Tab.swift) already represents mixed surface metadata, but only with ad hoc `shell` / `chat` strings

The main limitation is that Blink still treats surface type as a stringly-typed switch:

- chat is special-cased in `Shell`
- everything else is assumed to be a terminal

That is manageable for two surface types. It becomes fragile with three.

## Product Goals

1. Open a browser as a pane in the current project workspace.
2. Keep browser, chat, and terminal as peer surfaces in the same layout model.
3. Make browser focus predictable:
   - web content focus
   - address bar focus
4. Support the core browser workflow:
   - enter URL
   - go back
   - go forward
   - reload
   - open current page in default browser
5. Handle local development targets well:
   - `localhost`
   - `127.0.0.1`
   - custom local domains
6. Keep the implementation small enough that Blink can evolve it safely.

## Non-Goals For V1

- custom browser automation API
- remote browser proxying
- built-in DevTools driven by private API
- browser profile management
- browser import/sync/history product features
- popup window fidelity beyond basic support
- browser download manager
- window-level portal hosting

## Cmux Lessons

### Borrow

- Model browser as a peer surface, not a sidecar overlay.
- Keep browser state in one main state object.
- Make focus intent explicit rather than inferring it from responder state.
- Add scenario tests for browser-specific regressions.

### Avoid

- Private WebKit inspector APIs.
- Forcing a browser portal into the entire window hosting model.
- Conflating browser state, profiles, import, persistence, automation, and UI in one file.
- Excluding `localhost` and other dev hosts from history/suggestions.

## Proposed Architecture

### 1. Replace String Tab Types With A Surface Kind

Current:

```swift
struct AppTab {
    let type: String
    var isShell: Bool { type == "shell" }
    var isChat: Bool { type == "chat" }
}
```

Proposed:

```swift
enum AppSurfaceKind: String, Codable, Hashable {
    case terminal
    case chat
    case browser
}
```

Then `AppTab` becomes:

```swift
struct AppTab {
    let id: String
    let kind: AppSurfaceKind
    var label: String
    var defaultLabel: String
    let projectId: String

    var command: String?
    var chatThreadId: String?
    var browserState: BrowserTabState?
}
```

This should replace the current branching in:

- `Blink/Models/Tab.swift`
- `Blink/Store/AppStore.swift`
- `Blink/Views/Shell.swift`

### 2. Add A Dedicated Browser State Model

Add a small model instead of stuffing browser properties into `AppStore` globals:

```swift
struct BrowserTabState: Codable, Equatable, Hashable {
    var urlString: String?
    var title: String?
    var canGoBack: Bool
    var canGoForward: Bool
    var isLoading: Bool
    var preferredFocus: BrowserFocusTarget
}

enum BrowserFocusTarget: String, Codable, Equatable, Hashable {
    case webView
    case addressBar
}
```

This keeps tab-level browser state persistent and lets Blink add session restore later without redesigning the model.

### 3. Introduce A Browser Controller Layer

Recommended new files:

- `Blink/Browser/BrowserController.swift`
- `Blink/Browser/BrowserView.swift`
- `Blink/Browser/BrowserContainerView.swift`
- `Blink/Browser/BrowserTabState.swift`

Responsibilities:

- `BrowserController`
  - owns a `WKWebView`
  - exposes state updates
  - handles navigation actions
  - updates title/loading/back-forward state
- `BrowserView`
  - SwiftUI chrome
  - address bar
  - back/forward/reload buttons
  - open-in-default-browser action
- `BrowserContainerView`
  - `NSViewRepresentable` wrapper for `WKWebView`
  - focus bridge between SwiftUI and AppKit

This should mirror Blink's existing separation for terminal surfaces:

- `SurfaceManager` owns terminal surface instances
- `TerminalView` wraps them for SwiftUI

The browser should have the same shape instead of being a one-off `WKWebView` directly inside `Shell`.

### 4. Add A Browser Manager

Blink will need a small lifecycle manager for browser instances, similar in spirit to `SurfaceManager`, but much simpler.

Recommended:

- `BrowserManager`
  - keyed by `tabId`
  - returns a stable `BrowserController` per browser tab
  - destroys controller on tab close

This keeps `WKWebView` instances stable across SwiftUI updates and avoids responder churn.

### 5. Render Surfaces Symmetrically In Shell

Current `Shell` behavior:

- if chat -> `ProjectChatView`
- else -> `TerminalView`

Proposed:

```swift
switch tab.kind {
case .terminal:
    TerminalView(...)
case .chat:
    ProjectChatView(...)
case .browser:
    BrowserView(...)
}
```

That change belongs in [`Blink/Views/Shell.swift`](../Blink/Views/Shell.swift).

### 6. Add Store Actions For Browser Surfaces

Recommended actions in `AppStore`:

- `openBrowserTab(projectId:url:maximizeColumn:)`
- `openBrowserTabForActiveProject(url:maximizeColumn:)`
- `openOrFocusBrowserTab(projectId:url:)`
- `setBrowserFocusTarget(_ target: BrowserFocusTarget, for tabId: String)`

V1 should not try to dedupe by full browser session state.

Reasonable initial policy:

- opening a browser always creates a new browser tab unless explicitly called through an `openOrFocus...` flow for the same URL

## MVP User Experience

### Opening

Users should be able to:

- create a browser from the new-tab menu
- open a URL from the command palette
- open project links in Blink instead of the default browser when appropriate

Add to:

- [`Blink/Views/TabBar.swift`](../Blink/Views/TabBar.swift)
- [`Blink/Views/Sidebar.swift`](../Blink/Views/Sidebar.swift)
- [`Blink/Views/CommandPalette.swift`](../Blink/Views/CommandPalette.swift)
- [`Blink/BApp.swift`](../Blink/BApp.swift)

### Chrome

V1 browser chrome should include only:

- back
- forward
- reload / stop
- address bar
- open in default browser

Skip:

- bookmarks
- tabs within the browser
- profiles
- side panels
- built-in DevTools

### Focus

V1 should support exactly two browser focus targets:

- `.webView`
- `.addressBar`

Recommended behavior:

- opening a blank browser focuses the address bar
- clicking inside content focuses the web view
- `Cmd+L` focuses the address bar
- leaving the address bar returns focus to the web view

### Localhost Policy

Blink should treat local development URLs as first-class:

- keep `localhost`
- keep `127.0.0.1`
- keep custom local domains
- do not filter them out of history or suggestions

If Blink adds history later, local hosts must remain included.

## Persistence

V1 persistence should be intentionally light.

Persist:

- current URL
- title
- preferred focus target

Do not persist yet:

- full back-forward history
- detached DevTools state
- cookies/profile import choices

Reason:

- Blink does not yet have a generalized session persistence layer for non-terminal surfaces
- exact browser restoration is expensive

## Popups And External Links

Recommended V1 behavior:

- support `target=_blank` and `window.open`
- open popup requests as new Blink browser surfaces when they are normal browser navigations
- fall back to the default browser for odd popup windows or unsupported presentation requirements

This copies the good idea from cmux without taking on popup-window chrome and lifetime complexity immediately.

## DevTools

V1 should not implement embedded DevTools.

Use one of these options instead:

1. No built-in DevTools.
2. "Open in default browser" as the debugging path.
3. Optional future support only if it can be done on public API.

Blink should explicitly reject a cmux-style private inspector implementation.

## Recommended File Changes

### Existing Files To Refactor

- `Blink/Models/Tab.swift`
  - replace string `type` with `AppSurfaceKind`
- `Blink/Store/AppStore.swift`
  - add browser tab creation / focus actions
  - centralize browser tab metadata updates
- `Blink/Views/Shell.swift`
  - switch over surface kind instead of `if isChat else terminal`
- `Blink/Views/TabBar.swift`
  - add browser entry to the new-tab menu
- `Blink/Views/Sidebar.swift`
  - add browser launch affordance if desired
- `Blink/BApp.swift`
  - add browser commands and shortcuts

### New Files

- `Blink/Browser/BrowserTabState.swift`
- `Blink/Browser/BrowserManager.swift`
- `Blink/Browser/BrowserController.swift`
- `Blink/Browser/BrowserView.swift`
- `Blink/Browser/BrowserContainerView.swift`

## Testing Plan

### Unit Tests

Add tests for:

- browser URL resolution
- browser focus-target transitions
- browser tab creation and closing
- browser state persistence serialization

Recommended file:

- `BTests/BrowserTabTests.swift`

### UI / Integration Tests

Add tests for:

- opening a blank browser focuses the address bar
- `Cmd+L` focuses the address bar from the web view
- closing a browser cleans up its controller
- browser and terminal can coexist in splits without focus drift
- opening a localhost URL works and does not get rewritten or blocked

## Phased Delivery

### Phase 1: Surface Refactor

- add `AppSurfaceKind`
- remove `type == "shell"` / `type == "chat"` branching
- render all surfaces through a single switch

### Phase 2: Minimal Browser

- add browser manager/controller/view
- support blank tab + URL entry
- support back/forward/reload
- support open in default browser

### Phase 3: Browser Workflow Polish

- command palette actions
- keyboard shortcuts
- popup routing
- better tab titles / favicon support if still justified

### Phase 4: Optional Advanced Work

- session history restore
- integrated find-in-page
- limited automation helpers
- public-API-safe developer tooling if feasible

## Explicit Decisions

- Blink should copy cmux's surface model.
- Blink should copy cmux's focus discipline.
- Blink should not copy cmux's private inspector code.
- Blink should not copy cmux's portal host as the default browser architecture.
- Blink should not exclude local dev hosts from browser history.
- Blink should ship a narrow browser first and widen scope only when the current architecture proves stable.
