# Niri-Style Window Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Niri-style column sizing (1/3, 1/2, 2/3 presets), vim-style keyboard navigation (Ctrl+H/L), and column reordering (Ctrl+Shift+H/L) to Blink's workspace.

**Architecture:** Extend existing `WorkspaceLayoutState` (per-column width tracking, already built but unwired) and `AppStore` (tab navigation). Wire per-column widths into `Shell.swift`'s `stripLayout()`. Add keyboard shortcuts in `BApp.swift` that call new AppStore methods. Sidebar acts as a fixed left spatial neighbor for focus navigation.

**Tech Stack:** SwiftUI, AppKit (keyboard shortcuts via `.commands`), XCTest

**Spec:** `docs/superpowers/specs/2026-03-18-niri-window-management-design.md`

---

### Task 1: Add Width Presets to Constants

**Files:**
- Modify: `Blink/Utilities/Constants.swift:17-23`

- [ ] **Step 1: Add preset fractions and default width**

Replace the workspace constants block (lines 17-23) with:

```swift
    // Workspace
    static let workspacePaddingH: CGFloat = 10
    static let workspacePaddingV: CGFloat = 8
    static let workspaceColumnSpacing: CGFloat = 10
    static let workspaceColumnMinWidth: CGFloat = 420
    static let workspaceColumnMaxWidth: CGFloat = 4000
    static let workspaceColumnDefaultFraction: CGFloat = 0.5
    static let workspaceColumnPresets: [CGFloat] = [1.0 / 3.0, 0.5, 2.0 / 3.0]
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild build -scheme Blink -configuration Debug -destination 'platform=macOS,arch=arm64' -quiet`
Expected: Clean build, no errors.

- [ ] **Step 3: Commit**

```
git add Blink/Utilities/Constants.swift
git commit -m "feat: add workspace column width presets to constants"
```

---

### Task 2: Extend WorkspaceLayoutState with Preset Cycling and Maximize

**Files:**
- Modify: `Blink/Views/WorkspaceLayoutState.swift`

- [ ] **Step 1: Add maximize storage and preset cycling methods**

Replace the entire file with:

```swift
import SwiftUI

@MainActor @Observable
final class WorkspaceLayoutState {
    private var columnWidths: [String: [String: CGFloat]] = [:]
    private var preMaximizeWidths: [String: [String: CGFloat]] = [:]
    private var initializedProjects: Set<String> = []

    func sync(projectId: String, tabIds: [String], defaultWidth: CGFloat) {
        let existingWidths = columnWidths[projectId] ?? [:]
        var nextWidths: [String: CGFloat] = [:]

        for tabId in tabIds {
            nextWidths[tabId] = existingWidths[tabId] ?? defaultWidth
        }

        columnWidths[projectId] = nextWidths

        if tabIds.isEmpty {
            initializedProjects.remove(projectId)
        }
    }

    func width(for tabId: String, projectId: String, default defaultWidth: CGFloat) -> CGFloat {
        columnWidths[projectId]?[tabId] ?? defaultWidth
    }

    func setWidth(_ width: CGFloat, for tabId: String, projectId: String) {
        var widths = columnWidths[projectId] ?? [:]
        widths[tabId] = width
        columnWidths[projectId] = widths
    }

    /// Cycle through preset fractions. Returns the new absolute width.
    func cyclePreset(for tabId: String, projectId: String, viewportWidth: CGFloat) -> CGFloat {
        let presets = Layout.workspaceColumnPresets
        let currentWidth = width(for: tabId, projectId: projectId, default: viewportWidth * Layout.workspaceColumnDefaultFraction)
        let tolerance: CGFloat = 8

        // Find which preset we're closest to, then advance to the next
        var nextPreset = presets[0]
        for (i, fraction) in presets.enumerated() {
            let presetWidth = viewportWidth * fraction
            if abs(currentWidth - presetWidth) < tolerance {
                nextPreset = presets[(i + 1) % presets.count]
                break
            }
            // If we didn't match any preset, default to first preset
            if i == presets.count - 1 {
                nextPreset = presets[0]
            }
        }

        let newWidth = viewportWidth * nextPreset
        setWidth(newWidth, for: tabId, projectId: projectId)
        // Clear maximize state since we're now on a preset
        preMaximizeWidths[projectId]?.removeValue(forKey: tabId)
        return newWidth
    }

    /// Toggle maximize: full viewport width ↔ restore previous size.
    func toggleMaximize(for tabId: String, projectId: String, viewportWidth: CGFloat) -> CGFloat {
        let currentWidth = width(for: tabId, projectId: projectId, default: viewportWidth * Layout.workspaceColumnDefaultFraction)
        let tolerance: CGFloat = 8

        if abs(currentWidth - viewportWidth) < tolerance {
            // Currently maximized — restore previous width
            let restored = preMaximizeWidths[projectId]?[tabId] ?? (viewportWidth * Layout.workspaceColumnDefaultFraction)
            setWidth(restored, for: tabId, projectId: projectId)
            preMaximizeWidths[projectId]?.removeValue(forKey: tabId)
            return restored
        } else {
            // Save current width and maximize
            var saved = preMaximizeWidths[projectId] ?? [:]
            saved[tabId] = currentWidth
            preMaximizeWidths[projectId] = saved
            setWidth(viewportWidth, for: tabId, projectId: projectId)
            return viewportWidth
        }
    }

    func isInitialized(projectId: String) -> Bool {
        initializedProjects.contains(projectId)
    }

    func markInitialized(projectId: String) {
        initializedProjects.insert(projectId)
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild build -scheme Blink -configuration Debug -destination 'platform=macOS,arch=arm64' -quiet`
Expected: Clean build.

- [ ] **Step 3: Commit**

```
git add Blink/Views/WorkspaceLayoutState.swift
git commit -m "feat: add preset cycling and maximize toggle to WorkspaceLayoutState"
```

---

### Task 3: Add Tab Reordering and Focus Navigation to AppStore

**Files:**
- Modify: `Blink/Store/AppStore.swift`
- Test: `BTests/AppStoreTests.swift`

- [ ] **Step 1: Write tests for new navigation and reordering methods**

Add these tests to `BTests/AppStoreTests.swift` before the `private func makeStore()` line (line 165):

```swift
    func testFocusLeftFromFirstColumnGoesToSidebar() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t1")
        store.sidebarVisible = true
        store.sidebarFocused = false

        store.focusLeft()

        XCTAssertTrue(store.sidebarFocused)
    }

    func testFocusLeftFromFirstColumnNoOpWhenSidebarClosed() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t1")
        store.sidebarVisible = false

        store.focusLeft()

        XCTAssertEqual(store.activeTabId, "t1")
        XCTAssertFalse(store.sidebarFocused)
    }

    func testFocusRightFromSidebarGoesToTerminal() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t1")
        store.sidebarFocused = true

        store.focusRight()

        XCTAssertFalse(store.sidebarFocused)
        XCTAssertEqual(store.activeTabId, "t1")
    }

    func testFocusRightNoOpAtLastColumn() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t2")

        store.focusRight()

        XCTAssertEqual(store.activeTabId, "t2")
    }

    func testFocusLeftBetweenColumns() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t2")
        store.sidebarVisible = false

        store.focusLeft()

        XCTAssertEqual(store.activeTabId, "t1")
    }

    func testFocusRightBetweenColumns() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t1")

        store.focusRight()

        XCTAssertEqual(store.activeTabId, "t2")
    }

    func testMoveTabRight() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t1")

        store.moveActiveTabRight()

        let tabs = store.projectTabs(for: "1")
        XCTAssertEqual(tabs[0].id, "t2")
        XCTAssertEqual(tabs[1].id, "t1")
        XCTAssertEqual(store.activeTabId, "t1")
    }

    func testMoveTabLeft() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t2")

        store.moveActiveTabLeft()

        let tabs = store.projectTabs(for: "1")
        XCTAssertEqual(tabs[0].id, "t2")
        XCTAssertEqual(tabs[1].id, "t1")
        XCTAssertEqual(store.activeTabId, "t2")
    }

    func testMoveTabRightNoOpAtEnd() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t2")

        store.moveActiveTabRight()

        let tabs = store.projectTabs(for: "1")
        XCTAssertEqual(tabs[0].id, "t1")
        XCTAssertEqual(tabs[1].id, "t2")
    }

    func testMoveTabLeftNoOpAtStart() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t1")

        store.moveActiveTabLeft()

        let tabs = store.projectTabs(for: "1")
        XCTAssertEqual(tabs[0].id, "t1")
        XCTAssertEqual(tabs[1].id, "t2")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Blink -destination 'platform=macOS' -quiet 2>&1 | tail -20`
Expected: Compilation errors — `focusLeft()`, `focusRight()`, `moveActiveTabLeft()`, `moveActiveTabRight()` don't exist yet.

- [ ] **Step 3: Implement focusLeft, focusRight, moveActiveTabLeft, moveActiveTabRight**

Add these methods to `Blink/Store/AppStore.swift` after `selectPreviousTab()` (after line 294):

```swift
    func focusLeft() {
        guard let projectId = activeProjectId else { return }
        let tabs = projectTabs(for: projectId)

        if sidebarFocused {
            // Already at leftmost (sidebar) — no-op
            return
        }

        guard let activeTabId,
              let currentIndex = tabs.firstIndex(where: { $0.id == activeTabId }) else { return }

        if currentIndex > tabs.startIndex {
            // Move to previous column
            setActiveTab(tabs[tabs.index(before: currentIndex)].id)
        } else if sidebarVisible {
            // At first column, sidebar is open — focus sidebar
            sidebarFocused = true
        }
        // else: at first column, sidebar closed — no-op
    }

    func focusRight() {
        guard let projectId = activeProjectId else { return }
        let tabs = projectTabs(for: projectId)

        if sidebarFocused {
            // Move from sidebar to first terminal column
            sidebarFocused = false
            if let tabId = activeTabId {
                surfaceManager?.surface(for: tabId)?.focus()
            }
            return
        }

        guard let activeTabId,
              let currentIndex = tabs.firstIndex(where: { $0.id == activeTabId }) else { return }

        let nextIndex = tabs.index(after: currentIndex)
        if nextIndex < tabs.endIndex {
            setActiveTab(tabs[nextIndex].id)
        }
        // else: at last column — no-op
    }

    func moveActiveTabLeft() {
        guard let projectId = activeProjectId,
              let activeTabId,
              let currentIndex = tabs.firstIndex(where: { $0.id == activeTabId }) else { return }

        let projectTabIds = projectTabs(for: projectId).map(\.id)
        guard let localIndex = projectTabIds.firstIndex(of: activeTabId),
              localIndex > projectTabIds.startIndex else { return }

        // Find the global indices and swap
        let prevLocalIndex = projectTabIds.index(before: localIndex)
        let prevTabId = projectTabIds[prevLocalIndex]

        guard let globalCurrent = tabs.firstIndex(where: { $0.id == activeTabId }),
              let globalPrev = tabs.firstIndex(where: { $0.id == prevTabId }) else { return }

        tabs.swapAt(globalCurrent, globalPrev)
    }

    func moveActiveTabRight() {
        guard let projectId = activeProjectId,
              let activeTabId,
              let currentIndex = tabs.firstIndex(where: { $0.id == activeTabId }) else { return }

        let projectTabIds = projectTabs(for: projectId).map(\.id)
        guard let localIndex = projectTabIds.firstIndex(of: activeTabId) else { return }

        let nextLocalIndex = projectTabIds.index(after: localIndex)
        guard nextLocalIndex < projectTabIds.endIndex else { return }

        let nextTabId = projectTabIds[nextLocalIndex]

        guard let globalCurrent = tabs.firstIndex(where: { $0.id == activeTabId }),
              let globalNext = tabs.firstIndex(where: { $0.id == nextTabId }) else { return }

        tabs.swapAt(globalCurrent, globalNext)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Blink -destination 'platform=macOS' -quiet 2>&1 | tail -20`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```
git add Blink/Store/AppStore.swift BTests/AppStoreTests.swift
git commit -m "feat: add focusLeft/Right and moveActiveTab Left/Right to AppStore"
```

---

### Task 4: Update Keyboard Shortcuts in BApp

**Files:**
- Modify: `Blink/BApp.swift:72-92`

- [ ] **Step 1: Replace the toolbar command group**

Replace the `CommandGroup(after: .toolbar)` block (lines 72-92) with:

```swift
            CommandGroup(after: .toolbar) {
                Button(store.sidebarVisible ? "Hide Sidebar" : "Show Sidebar") {
                    store.toggleSidebar()
                }
                .keyboardShortcut("b", modifiers: .command)

                Button("Focus Left") {
                    store.focusLeft()
                }
                .keyboardShortcut("h", modifiers: .control)

                Button("Focus Right") {
                    store.focusRight()
                }
                .keyboardShortcut("l", modifiers: .control)

                Button("Move Window Left") {
                    store.moveActiveTabLeft()
                }
                .keyboardShortcut("h", modifiers: [.control, .shift])

                Button("Move Window Right") {
                    store.moveActiveTabRight()
                }
                .keyboardShortcut("l", modifiers: [.control, .shift])

                Divider()

                Button("Open Git") {
                    store.openOrFocusCommandTabForActiveProject(command: "lazygit", label: "lazygit")
                }
                .keyboardShortcut("g", modifiers: .command)
            }
```

Note: This removes the old `Ctrl+H` (toggleSidebarFocus) and `Ctrl+L` (focusTerminal) bindings, replacing them with `focusLeft()` and `focusRight()` which subsume that behavior.

- [ ] **Step 2: Add Ctrl+R and Ctrl+F shortcuts**

We cannot add these in `.commands` because they need the viewport width from the view. Instead, add them using `.onKeyPress` in `Shell.swift` in Task 5. Skip for now.

- [ ] **Step 3: Build to verify compilation**

Run: `xcodebuild build -scheme Blink -configuration Debug -destination 'platform=macOS,arch=arm64' -quiet`
Expected: Clean build.

- [ ] **Step 4: Commit**

```
git add Blink/BApp.swift
git commit -m "feat: add Niri-style keyboard shortcuts for focus and column move"
```

---

### Task 5: Wire Per-Column Widths and Sizing Shortcuts into Shell

**Files:**
- Modify: `Blink/Views/Shell.swift:279-375` (WorkspaceColumnsView methods)

- [ ] **Step 1: Update syncTabs to use default fraction instead of min width**

Replace `syncTabs` (line 279-285) with:

```swift
    private func syncTabs(viewportWidth: CGFloat) {
        layoutState.sync(
            projectId: project.id,
            tabIds: tabs.map(\.id),
            defaultWidth: viewportWidth * Layout.workspaceColumnDefaultFraction
        )
    }
```

- [ ] **Step 2: Update columnWidth to read from layoutState**

Replace `columnWidth` and `focusedColumnWidth` (lines 360-375) with:

```swift
    private func columnWidth(for tabId: String, viewportWidth: CGFloat) -> CGFloat {
        let width = layoutState.width(
            for: tabId,
            projectId: project.id,
            default: viewportWidth * Layout.workspaceColumnDefaultFraction
        )
        return min(max(width, Layout.workspaceColumnMinWidth), Layout.workspaceColumnMaxWidth)
    }
```

- [ ] **Step 3: Add keyboard handlers for Ctrl+R and Ctrl+F**

Add `.onKeyPress` to the `GeometryReader` content in the `body` (after the `.onChange(of: geometry.size.width)` block, around line 274):

```swift
                .onKeyPress(.init("r"), modifiers: .control) {
                    guard let tabId = store.activeTabId else { return .ignored }
                    let _ = layoutState.cyclePreset(for: tabId, projectId: project.id, viewportWidth: geometry.size.width)
                    alignActiveTab(viewportWidth: geometry.size.width, animated: true)
                    return .handled
                }
                .onKeyPress(.init("f"), modifiers: .control) {
                    guard let tabId = store.activeTabId else { return .ignored }
                    let _ = layoutState.toggleMaximize(for: tabId, projectId: project.id, viewportWidth: geometry.size.width)
                    alignActiveTab(viewportWidth: geometry.size.width, animated: true)
                    return .handled
                }
```

- [ ] **Step 4: Remove the old focusedColumnWidth method**

Delete `focusedColumnWidth(for:)` entirely — it's replaced by the per-column width lookup.

- [ ] **Step 5: Build to verify compilation**

Run: `xcodebuild build -scheme Blink -configuration Debug -destination 'platform=macOS,arch=arm64' -quiet`
Expected: Clean build.

- [ ] **Step 6: Commit**

```
git add Blink/Views/Shell.swift
git commit -m "feat: wire per-column widths and Ctrl+R/F sizing shortcuts"
```

---

### Task 6: Update Viewport Alignment for Non-Uniform Widths

**Files:**
- Modify: `Blink/Views/Shell.swift` (focusedViewportOffset method)

- [ ] **Step 1: Update focusedViewportOffset to center the active column**

The current `focusedViewportOffset` places the active column at `frame.minX`. For non-uniform widths, we should center the active column in the viewport when possible. Replace `focusedViewportOffset` (lines 377-386) with:

```swift
    private func focusedViewportOffset(viewportWidth: CGFloat) -> CGFloat {
        guard let activeTabId = store.activeTabId else { return 0 }
        let layout = stripLayout(viewportWidth: viewportWidth)
        guard let frame = layout.frames[activeTabId] else { return 0 }

        // Center the active column in the viewport
        let centeredOffset = frame.minX - (viewportWidth - frame.width) / 2
        return clampedViewportOffset(
            centeredOffset,
            contentWidth: layout.contentWidth,
            viewportWidth: viewportWidth
        )
    }
```

- [ ] **Step 2: Build and manually test**

Run: `xcodebuild build -scheme Blink -configuration Debug -destination 'platform=macOS,arch=arm64' -quiet`
Expected: Clean build.

- [ ] **Step 3: Commit**

```
git add Blink/Views/Shell.swift
git commit -m "feat: center active column in viewport for non-uniform widths"
```

---

### Task 7: Clean Up Constants and Final Polish

**Files:**
- Modify: `Blink/Utilities/Constants.swift`

- [ ] **Step 1: Remove unused constant**

Remove `workspaceFocusedColumnPeek` from Constants.swift — it's no longer referenced after the column width changes.

- [ ] **Step 2: Build and run full test suite**

Run: `xcodebuild test -scheme Blink -destination 'platform=macOS' -quiet 2>&1 | tail -20`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```
git add Blink/Utilities/Constants.swift
git commit -m "chore: remove unused workspaceFocusedColumnPeek constant"
```

---

### Task 8: Integration Test — Manual Verification

- [ ] **Step 1: Launch debug build**

```
pkill -x Blink; sleep 1
xcodebuild build -scheme Blink -configuration Debug -destination 'platform=macOS,arch=arm64' -quiet
open "$(find ~/Library/Developer/Xcode/DerivedData -name 'Blink.app' -path '*/Debug/*' -maxdepth 5 | head -1)"
```

- [ ] **Step 2: Verify column sizing**

1. Open a project with one terminal — should fill viewport (1/2 width = full when single, clamped by min/max)
2. Open a second terminal (Cmd+T) — both should be ~1/2 viewport width
3. Press `Ctrl+R` — active column cycles to 2/3 width
4. Press `Ctrl+R` again — cycles to 1/3
5. Press `Ctrl+R` again — back to 1/2
6. Press `Ctrl+F` — maximizes to full width
7. Press `Ctrl+F` again — restores previous size

- [ ] **Step 3: Verify keyboard navigation**

1. With sidebar open, press `Ctrl+H` from first terminal — sidebar focuses
2. Press `Ctrl+L` from sidebar — first terminal focuses
3. With two terminals, press `Ctrl+L` — focus moves right
4. Press `Ctrl+H` — focus moves left
5. At rightmost column, `Ctrl+L` is no-op
6. Close sidebar (Cmd+B), at leftmost column `Ctrl+H` is no-op

- [ ] **Step 4: Verify column reordering**

1. With two terminals, focus the first
2. Press `Ctrl+Shift+L` — column moves right (swaps with second)
3. Press `Ctrl+Shift+H` — column moves back left
4. At leftmost, `Ctrl+Shift+H` is no-op
5. At rightmost, `Ctrl+Shift+L` is no-op

- [ ] **Step 5: Final commit**

```
git add -A
git commit -m "feat: Niri-style window management — column sizing, keyboard nav, reordering"
```
