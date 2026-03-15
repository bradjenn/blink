# Per-Tab Terminal Surfaces — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Each tab gets its own independent terminal surface with its own shell process, working directory, auto-updating title, and unread activity tracking.

**Architecture:** SurfaceManager owns all surfaces keyed by tab ID. TerminalView uses `.id(tabId)` to swap surfaces on tab switch. GhosttyApp action callback routes SET_TITLE to AppStore. close_surface_cb handles shell exit.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, GhosttyKit

**Spec:** `docs/superpowers/specs/2026-03-15-per-tab-surfaces-design.md`

---

## File Structure

| File | Action | Purpose |
|------|--------|---------|
| `Blink/Terminal/SurfaceManager.swift` | Create | Owns all surfaces keyed by tab ID |
| `Blink/Terminal/TerminalSurfaceView.swift` | Modify | Add tabId, workingDirectory, focus(), teardown() |
| `Blink/Terminal/TerminalView.swift` | Modify | Look up surfaces from SurfaceManager |
| `Blink/Terminal/GhosttyApp.swift` | Modify | Wire action callback + close_surface_cb |
| `Blink/Models/Tab.swift` | Modify | Make label var, remove dummy data, add openTab |
| `Blink/Store/AppStore.swift` | Modify | Add openTab(), unreadTabs |
| `Blink/Views/Shell.swift` | Modify | Pass tabId, use .id(tabId) |
| `Blink/Views/TabBar.swift` | Modify | Wire + button, wire close to destroySurface |
| `Blink/Views/SidebarProjectItem.swift` | Modify | Wire pulse to unreadTabs |
| `Blink/BApp.swift` | Modify | Create SurfaceManager, wire refs |

---

## Chunk 1: SurfaceManager + TerminalSurfaceView Changes

### Task 1: Create SurfaceManager

**Files:**
- Create: `Blink/Terminal/SurfaceManager.swift`

- [ ] **Step 1: Write SurfaceManager.swift**

```swift
import SwiftUI
import GhosttyKit

@Observable
final class SurfaceManager {
    /// Tab ID → live terminal view
    var surfaces: [String: TerminalSurfaceView] = [:]

    /// Create a new terminal surface for a tab.
    func createSurface(tabId: String, app: GhosttyApp, workingDirectory: String) -> TerminalSurfaceView {
        let view = TerminalSurfaceView(app: app, tabId: tabId, workingDirectory: workingDirectory)
        surfaces[tabId] = view
        return view
    }

    /// Destroy a terminal surface — kills the shell process immediately.
    func destroySurface(tabId: String) {
        if let view = surfaces.removeValue(forKey: tabId) {
            view.teardown()
        }
    }

    /// Look up an existing surface by tab ID.
    func surface(for tabId: String) -> TerminalSurfaceView? {
        surfaces[tabId]
    }

    /// Find the tab ID for a given surface view.
    func tabId(for view: TerminalSurfaceView) -> String? {
        view.tabId
    }

    /// Destroy all surfaces for a project's tabs.
    func destroySurfaces(tabIds: [String]) {
        for tabId in tabIds {
            destroySurface(tabId: tabId)
        }
    }
}
```

- [ ] **Step 2: Verify build**

```bash
cd ~/Code/blink
xcodegen generate && xcodebuild -scheme Blink -destination 'platform=macOS' build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Blink/Terminal/SurfaceManager.swift
git commit -m "feat: add SurfaceManager for per-tab terminal surfaces"
```

---

### Task 2: Update TerminalSurfaceView

**Files:**
- Modify: `Blink/Terminal/TerminalSurfaceView.swift`

Changes:
- Add `tabId` property (stored, immutable)
- Add `workingDirectory` property (stored, used in surface creation)
- Add `focus()` method
- Add `teardown()` method (frees surface, nils pointer)
- Update `deinit` to use `teardown()` safely
- Update `createSurface` to set `working_directory` on the config
- Update init signature to accept `tabId` and `workingDirectory`

- [ ] **Step 1: Update TerminalSurfaceView.swift**

Key changes to the init:
```swift
    let tabId: String
    private let workingDirectory: String

    init(app: GhosttyApp, tabId: String, workingDirectory: String) {
        self.ghosttyApp = app
        self.tabId = tabId
        self.workingDirectory = workingDirectory
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        wantsLayer = true
        layer?.isOpaque = false
        updateTrackingAreas()
    }
```

Update `createSurface` to set working directory:
```swift
    private func createSurface(app: ghostty_app_t) {
        var cfg = ghostty_surface_config_new()
        cfg.platform_tag = GHOSTTY_PLATFORM_MACOS
        cfg.platform = ghostty_platform_u(
            macos: ghostty_platform_macos_s(
                nsview: Unmanaged.passUnretained(self).toOpaque()
            )
        )
        cfg.userdata = Unmanaged.passUnretained(self).toOpaque()
        cfg.scale_factor = Double(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0)

        // Set working directory for the shell
        workingDirectory.withCString { cPath in
            cfg.working_directory = cPath
            surface = ghostty_surface_new(app, &cfg)
        }

        if surface == nil {
            print("[TerminalSurfaceView] Failed to create surface")
            return
        }

        let fbSize = convertToBacking(frame.size)
        ghostty_surface_set_size(surface, UInt32(fbSize.width), UInt32(fbSize.height))
    }
```

Add focus and teardown:
```swift
    /// Grab keyboard focus.
    func focus() {
        guard let window else { return }
        window.makeFirstResponder(self)
    }

    /// Free the ghostty surface. Called by SurfaceManager on tab close.
    func teardown() {
        if let surface {
            ghostty_surface_free(surface)
        }
        surface = nil
    }

    deinit {
        teardown()
    }
```

- [ ] **Step 2: Verify build**
- [ ] **Step 3: Commit**

```bash
git add Blink/Terminal/TerminalSurfaceView.swift
git commit -m "feat: TerminalSurfaceView supports tabId, workingDirectory, focus, teardown"
```

---

## Chunk 2: TerminalView + Shell + BApp Wiring

### Task 3: Update TerminalView SwiftUI wrapper

**Files:**
- Modify: `Blink/Terminal/TerminalView.swift`

```swift
import SwiftUI
import GhosttyKit

struct TerminalView: NSViewRepresentable {
    let tabId: String
    let ghosttyApp: GhosttyApp
    let surfaceManager: SurfaceManager
    let workingDirectory: String

    func makeNSView(context: Context) -> TerminalSurfaceView {
        // Reuse existing surface or create new one
        if let existing = surfaceManager.surface(for: tabId) {
            return existing
        }
        return surfaceManager.createSurface(
            tabId: tabId,
            app: ghosttyApp,
            workingDirectory: workingDirectory
        )
    }

    func updateNSView(_ nsView: TerminalSurfaceView, context: Context) {
        nsView.focus()
    }
}
```

- [ ] **Step 1: Write updated TerminalView.swift**
- [ ] **Step 2: Verify build**
- [ ] **Step 3: Commit**

---

### Task 4: Update Tab model and AppStore

**Files:**
- Modify: `Blink/Models/Tab.swift`
- Modify: `Blink/Store/AppStore.swift`

Tab.swift changes — make label mutable, remove dummy data:

```swift
import Foundation

struct AppTab: Identifiable, Equatable, Hashable {
    let id: String
    let type: String
    var label: String
    let projectId: String
}
```

AppStore changes — add `openTab()`, `unreadTabs`, update `closeTab` and `removeProject`:

```swift
    // Unread activity
    var unreadTabs: Set<String> = []

    /// Create a new shell tab for a project.
    func openTab(projectId: String) -> AppTab {
        let count = projectTabs(for: projectId).count + 1
        let tab = AppTab(
            id: UUID().uuidString,
            type: "shell",
            label: "Terminal \(count)",
            projectId: projectId
        )
        tabs.append(tab)
        activeTabId = tab.id
        return tab
    }

    /// Mark a tab as having unread activity.
    func markUnread(_ tabId: String) {
        if tabId != activeTabId {
            unreadTabs.insert(tabId)
        }
    }

    /// Clear unread status when switching to a tab.
    func clearUnread(_ tabId: String) {
        unreadTabs.remove(tabId)
    }

    /// Check if a project has any unread tabs.
    func hasUnread(projectId: String) -> Bool {
        let projectTabIds = Set(projectTabs(for: projectId).map(\.id))
        return !unreadTabs.isDisjoint(with: projectTabIds)
    }

    /// Update a tab's title.
    func setTabTitle(_ tabId: String, title: String) {
        if let idx = tabs.firstIndex(where: { $0.id == tabId }) {
            tabs[idx].label = title
        }
    }
```

Remove dummy tabs — start with no tabs, they're created when you click +:
```swift
    var tabs: [AppTab] = []
```

Also update `setActiveTab` to clear unread:
```swift
    func setActiveTab(_ id: String) {
        activeTabId = id
        clearUnread(id)
    }
```

- [ ] **Step 1: Update Tab.swift**
- [ ] **Step 2: Update AppStore.swift**
- [ ] **Step 3: Verify build**
- [ ] **Step 4: Commit**

---

### Task 5: Update Shell.swift and BApp.swift

**Files:**
- Modify: `Blink/Views/Shell.swift`
- Modify: `Blink/BApp.swift`

BApp.swift — add SurfaceManager:
```swift
    @State private var surfaceManager = SurfaceManager()
```

Pass it to Shell:
```swift
    Shell(ghosttyApp: ghosttyApp, surfaceManager: surfaceManager)
```

Shell.swift — add surfaceManager parameter, update content area:
```swift
    let ghosttyApp: GhosttyApp
    let surfaceManager: SurfaceManager
```

Content area becomes:
```swift
                        } else if let tabId = store.activeTabId,
                                  let projectId = store.activeProjectId,
                                  let project = store.projects.first(where: { $0.id == projectId }) {
                            if !store.hasWallpaper {
                                theme.bg
                            }
                            TerminalView(
                                tabId: tabId,
                                ghosttyApp: ghosttyApp,
                                surfaceManager: surfaceManager,
                                workingDirectory: project.path
                            )
                            .id(tabId)
                        }
```

Also pass surfaceManager to SettingsPage:
```swift
    SettingsPage(ghosttyApp: ghosttyApp)
```
(SettingsPage doesn't need surfaceManager, just ghosttyApp for theme/opacity)

- [ ] **Step 1: Update BApp.swift**
- [ ] **Step 2: Update Shell.swift**
- [ ] **Step 3: Verify build**
- [ ] **Step 4: Commit**

---

## Chunk 3: TabBar Wiring + Action Callbacks

### Task 6: Wire TabBar + and close buttons

**Files:**
- Modify: `Blink/Views/TabBar.swift`

The + button needs to call `store.openTab()` and create a surface.
The close button on TabPill needs to call `surfaceManager.destroySurface()`.

TabBarTabsArea needs `ghosttyApp` and `surfaceManager` parameters.
TabPill's close action needs to destroy the surface.

Pass these through from Shell.swift.

- [ ] **Step 1: Update TabBar.swift — add parameters and wire buttons**
- [ ] **Step 2: Update Shell.swift to pass ghosttyApp and surfaceManager to TabBarTabsArea**
- [ ] **Step 3: Verify build**
- [ ] **Step 4: Commit**

---

### Task 7: Wire GhosttyApp action callback for SET_TITLE

**Files:**
- Modify: `Blink/Terminal/GhosttyApp.swift`

Add weak references to AppStore and SurfaceManager:
```swift
    weak var store: AppStore?
    weak var surfaceManager: SurfaceManager?
```

Wire these in BApp.swift after init:
```swift
    .onAppear {
        ghosttyApp.store = store
        ghosttyApp.surfaceManager = surfaceManager
    }
```

Update the action callback to handle SET_TITLE:
```swift
        runtime.action_cb = { app, target, action in
            guard let app else { return false }
            guard let ud = ghostty_app_userdata(app) else { return false }
            let ghostty = Unmanaged<GhosttyApp>.fromOpaque(ud).takeUnretainedValue()

            switch action.tag {
            case GHOSTTY_ACTION_SET_TITLE:
                guard target.tag == GHOSTTY_TARGET_SURFACE else { return false }
                let surface = target.target.surface
                guard let title = action.action.set_title.title else { return false }
                let titleStr = String(cString: title)

                // Find the tab via the surface's view userdata
                if let viewPtr = ghostty_surface_userdata(surface) {
                    let view = Unmanaged<TerminalSurfaceView>.fromOpaque(viewPtr).takeUnretainedValue()
                    let tabId = view.tabId

                    DispatchQueue.main.async {
                        ghostty.store?.setTabTitle(tabId, title: titleStr)
                        ghostty.store?.markUnread(tabId)
                    }
                }
                return true

            default:
                return false
            }
        }
```

Update close_surface_cb to handle shell exit:
```swift
        runtime.close_surface_cb = { userdata, processAlive in
            guard let ud = userdata else { return }
            let view = Unmanaged<TerminalSurfaceView>.fromOpaque(ud).takeUnretainedValue()
            let tabId = view.tabId

            DispatchQueue.main.async {
                // Find the GhosttyApp via a static reference or notification
                // For simplicity, the view can hold a reference to the closure
            }
        }
```

Actually, `close_surface_cb` receives the **surface's** userdata (the TerminalSurfaceView). We can add an `onClose` callback to the view that gets set by the SurfaceManager. Simpler than threading GhosttyApp references through.

Add to TerminalSurfaceView:
```swift
    var onClose: ((String) -> Void)?
```

Set it in SurfaceManager.createSurface:
```swift
    view.onClose = { [weak self] tabId in
        self?.destroySurface(tabId: tabId)
    }
```

Then close_surface_cb becomes:
```swift
        runtime.close_surface_cb = { userdata, _ in
            guard let ud = userdata else { return }
            let view = Unmanaged<TerminalSurfaceView>.fromOpaque(ud).takeUnretainedValue()
            DispatchQueue.main.async {
                view.onClose?(view.tabId)
            }
        }
```

- [ ] **Step 1: Add weak refs + onClose pattern**
- [ ] **Step 2: Wire action callback for SET_TITLE**
- [ ] **Step 3: Wire close_surface_cb**
- [ ] **Step 4: Verify build**
- [ ] **Step 5: Commit**

---

### Task 8: Wire sidebar pulse to unreadTabs

**Files:**
- Modify: `Blink/Views/SidebarProjectItem.swift`

The pulse dot already exists visually. Wire it to `store.hasUnread(projectId:)` instead of whatever dummy state it currently uses.

- [ ] **Step 1: Update SidebarProjectItem to use store.hasUnread()**
- [ ] **Step 2: Verify build**
- [ ] **Step 3: Commit**

---

## Chunk 4: Integration + Testing

### Task 9: Build, run, and verify

- [ ] **Step 1: Build**

```bash
cd ~/Code/blink
xcodegen generate && xcodebuild -scheme Blink -destination 'platform=macOS' build 2>&1 | tail -5
```

- [ ] **Step 2: Launch and test**

```bash
osascript -e 'tell application "Blink" to quit' 2>/dev/null; sleep 1
open ~/Library/Developer/Xcode/DerivedData/Blink-*/Build/Products/Debug/Blink.app
```

**Verify:**
1. Click a project → no terminal yet (no tabs)
2. Click + → new tab appears, terminal opens at project directory (`pwd` shows path)
3. Click + again → second tab, independent terminal
4. Switch between tabs → terminals preserve their state
5. Close a tab → shell killed, tab removed
6. Tab titles update when running commands
7. Switch projects → first tab of that project activates
8. Background tab output → sidebar dot pulses

- [ ] **Step 3: Fix any issues**
- [ ] **Step 4: Final commit**
