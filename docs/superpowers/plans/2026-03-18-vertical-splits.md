# Vertical Splits Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add niri-style vertical stacking within columns — absorb tabs into a column, expel them out, navigate up/down between panes.

**Architecture:** Introduce a `Column` model that groups tab IDs vertically. `AppStore` gains a `columns: [String: [Column]]` dictionary as the source of truth for spatial layout. Every method that currently traverses `projectTabs(for:)` for spatial ordering switches to `projectColumns(for:)`. `WorkspaceLayoutState` and `Shell.swift` re-key on `column.id`.

**Tech Stack:** Swift, SwiftUI, XCTest

**Spec:** `docs/superpowers/specs/2026-03-18-vertical-splits-design.md`

---

### Task 1: Column Model & AppStore State

**Files:**
- Create: `Blink/Models/Column.swift`
- Modify: `Blink/Utilities/Constants.swift:18-28`
- Modify: `Blink/Store/AppStore.swift:33-42`

- [ ] **Step 1: Create `Blink/Models/Column.swift`**

```swift
import Foundation

struct Column: Identifiable, Equatable, Hashable {
    let id: String
    var tabIds: [String]  // ordered top-to-bottom
}
```

- [ ] **Step 2: Add constant for pane divider height**

In `Blink/Utilities/Constants.swift`, add after the overview constants (line 28):

```swift
    // Column panes
    static let columnPaneDividerHeight: CGFloat = 1
```

- [ ] **Step 3: Add column state to AppStore**

In `Blink/Store/AppStore.swift`, replace the overview block (lines 40-42):

```swift
    // Overview
    var isOverviewMode = false
    var overviewHighlightedColumnId: String?

    // Columns — source of truth for spatial layout (left-to-right order)
    var columns: [String: [Column]] = [:]
    var columnFocusedTab: [String: String] = [:]
```

This renames `overviewHighlightedTabId` to `overviewHighlightedColumnId`. All references to the old name will be updated in Task 7.

- [ ] **Step 4: Add column helper methods to AppStore**

Add after the `hasWallpaper` computed property (line 211), before `// MARK: - Actions`:

```swift
    // MARK: - Column Helpers

    func projectColumns(for projectId: String) -> [Column] {
        columns[projectId] ?? []
    }

    func columnFor(tabId: String) -> Column? {
        guard let tab = tabs.first(where: { $0.id == tabId }) else { return nil }
        return projectColumns(for: tab.projectId).first { $0.tabIds.contains(tabId) }
    }

    var activeColumn: Column? {
        guard let tabId = activeTabId else { return nil }
        return columnFor(tabId: tabId)
    }

    /// Returns tabs in column-major order: left-to-right columns, top-to-bottom within each.
    func orderedTabs(for projectId: String) -> [AppTab] {
        let cols = projectColumns(for: projectId)
        return cols.flatMap { col in
            col.tabIds.compactMap { tabId in
                tabs.first { $0.id == tabId }
            }
        }
    }
```

- [ ] **Step 5: Write tests for column helpers**

In `BTests/AppStoreTests.swift`, update `makeStore()` to also set up columns:

```swift
    private func makeStore() -> AppStore {
        let store = AppStore()
        store.projects = [
            project(id: "1", name: "blink"),
            project(id: "2", name: "krux"),
            project(id: "3", name: "api-server"),
            project(id: "4", name: "dotfiles"),
        ]
        store.tabs = [
            AppTab(id: "t1", type: "shell", label: "Terminal 1", defaultLabel: "Terminal 1", projectId: "1"),
            AppTab(id: "t2", type: "shell", label: "Terminal 2", defaultLabel: "Terminal 2", projectId: "1"),
            AppTab(id: "t3", type: "shell", label: "Terminal 1", defaultLabel: "Terminal 1", projectId: "2"),
        ]
        store.columns = [
            "1": [
                Column(id: "c1", tabIds: ["t1"]),
                Column(id: "c2", tabIds: ["t2"]),
            ],
            "2": [
                Column(id: "c3", tabIds: ["t3"]),
            ],
        ]
        store.activeProjectId = nil
        store.activeTabId = nil
        store.lastSelectedProjectId = nil
        store.unreadTabs = []
        return store
    }
```

Add tests before `makeStore()`:

```swift
    // MARK: - Column Helper Tests

    func testProjectColumns() {
        let store = makeStore()
        let cols = store.projectColumns(for: "1")
        XCTAssertEqual(cols.count, 2)
        XCTAssertEqual(cols[0].tabIds, ["t1"])
        XCTAssertEqual(cols[1].tabIds, ["t2"])
    }

    func testProjectColumnsEmpty() {
        let store = makeStore()
        let cols = store.projectColumns(for: "4")
        XCTAssertEqual(cols.count, 0)
    }

    func testColumnForTabId() {
        let store = makeStore()
        let col = store.columnFor(tabId: "t1")
        XCTAssertEqual(col?.id, "c1")
    }

    func testActiveColumn() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t2")
        XCTAssertEqual(store.activeColumn?.id, "c2")
    }

    func testOrderedTabs() {
        let store = makeStore()
        // Put t1 and t2 in same column to test top-to-bottom ordering
        store.columns["1"] = [
            Column(id: "c1", tabIds: ["t1", "t2"]),
        ]
        let ordered = store.orderedTabs(for: "1")
        XCTAssertEqual(ordered.map(\.id), ["t1", "t2"])
    }

    func testOrderedTabsAcrossColumns() {
        let store = makeStore()
        let ordered = store.orderedTabs(for: "1")
        XCTAssertEqual(ordered.map(\.id), ["t1", "t2"])
    }
```

- [ ] **Step 6: Run tests**

Run: `xcodebuild test -scheme Blink -destination 'platform=macOS' -only-testing:BTests/AppStoreTests 2>&1 | tail -20`

Expected: All new column helper tests pass. Some existing tests may fail due to `overviewHighlightedTabId` rename — that's expected and will be fixed in Task 7.

- [ ] **Step 7: Commit**

```bash
git add Blink/Models/Column.swift Blink/Utilities/Constants.swift Blink/Store/AppStore.swift BTests/AppStoreTests.swift
git commit -m "feat: add Column model, column state, and helper methods"
```

---

### Task 2: Migrate openTab & closeTab to Use Columns

**Files:**
- Modify: `Blink/Store/AppStore.swift:419-549` (openTab, closeTab, removeProject, setActiveProject)
- Modify: `BTests/AppStoreTests.swift`

- [ ] **Step 1: Update `openTab()` to create a Column**

In `AppStore.swift`, replace `openTab()` (lines 419-433):

```swift
    @discardableResult
    func openTab(projectId: String, command: String? = nil, label: String? = nil) -> AppTab {
        let count = projectTabs(for: projectId).count + 1
        let defaultLabel = label ?? "Terminal \(count)"
        let tab = AppTab(
            id: UUID().uuidString,
            type: "shell",
            label: defaultLabel,
            defaultLabel: defaultLabel,
            projectId: projectId,
            command: command
        )
        tabs.append(tab)

        // Create a new single-tab column
        let column = Column(id: UUID().uuidString, tabIds: [tab.id])
        var projectCols = columns[projectId] ?? []
        projectCols.append(column)
        columns[projectId] = projectCols

        setActiveTab(tab.id)
        return tab
    }
```

- [ ] **Step 2: Update `closeTab()` with column-aware focus fallback**

Replace `closeTab()` (lines 509-531):

```swift
    func closeTab(_ id: String) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        let projectId = tab.projectId

        // Find the column and position of this tab
        var projectCols = columns[projectId] ?? []
        guard let colIdx = projectCols.firstIndex(where: { $0.tabIds.contains(id) }) else { return }
        let paneIdx = projectCols[colIdx].tabIds.firstIndex(of: id)!

        // Remove tab from column
        projectCols[colIdx].tabIds.removeAll { $0 == id }

        // Determine next focus before removing empty column
        var nextFocusTabId: String? = nil
        if activeTabId == id {
            if !projectCols[colIdx].tabIds.isEmpty {
                // Prefer next pane down, then previous pane up
                let newPaneIdx = min(paneIdx, projectCols[colIdx].tabIds.count - 1)
                nextFocusTabId = projectCols[colIdx].tabIds[newPaneIdx]
            }
        }

        // Remove column if empty
        if projectCols[colIdx].tabIds.isEmpty {
            let removedColId = projectCols[colIdx].id
            columnFocusedTab[removedColId] = nil
            projectCols.remove(at: colIdx)
        }

        columns[projectId] = projectCols

        // Remove tab data
        tabs.removeAll { $0.id == id }
        unreadTabs.remove(id)
        if lastActiveTab[projectId] == id {
            lastActiveTab[projectId] = nil
        }

        // Set next focus
        if activeTabId == id {
            if let next = nextFocusTabId {
                setActiveTab(next)
            } else {
                // Fall back to adjacent column (prefer right, then left)
                let updatedCols = projectColumns(for: projectId)
                let adjacentCol: Column? = {
                    // colIdx now points to what was the right neighbor (since we removed the empty column)
                    if colIdx < updatedCols.count {
                        return updatedCols[colIdx]
                    } else if colIdx > 0 {
                        return updatedCols[colIdx - 1]
                    }
                    return nil
                }()
                if let adjCol = adjacentCol,
                   let fallback = columnFocusedTab[adjCol.id] ?? adjCol.tabIds.first {
                    setActiveTab(fallback)
                } else {
                    activeTabId = nil
                    workspaceViewportOffsets[projectId] = nil
                }
            }
        }

        reindexTabs(for: projectId)

        let surfaceManager = surfaceManager
        DispatchQueue.main.async {
            surfaceManager?.destroySurface(tabId: id)
        }
    }
```

- [ ] **Step 3: Update `removeProject()` to clean up column state**

In `removeProject()` (line 488), add column cleanup after `workspaceViewportOffsets[id] = nil`:

```swift
        // Clean up column state
        if let projectCols = columns[id] {
            for col in projectCols {
                columnFocusedTab[col.id] = nil
            }
        }
        columns[id] = nil
```

- [ ] **Step 4: Update `setActiveProject()` to initialize columns from tabs**

In `setActiveProject()`, insert column migration logic right after `activeView = .projects` (line 225) and before the existing `if let id { // Restore last active tab` block (line 226). Add this code:

```swift
        // Ensure columns exist for all tabs (migration from pre-column model)
        if let id {
            let projectCols = projectColumns(for: id)
            let columnedTabIds = Set(projectCols.flatMap(\.tabIds))
            let uncolumnedTabs = projectTabs(for: id).filter { !columnedTabIds.contains($0.id) }
            if !uncolumnedTabs.isEmpty {
                var cols = projectCols
                for tab in uncolumnedTabs {
                    cols.append(Column(id: UUID().uuidString, tabIds: [tab.id]))
                }
                columns[id] = cols
            }
        }
```

The existing `if let id { ... }` block that restores active tabs stays unchanged below this new block.

- [ ] **Step 5: Write tests**

```swift
    func testOpenTabCreatesColumn() {
        let store = makeStore()
        store.setActiveProject("1")
        let tab = store.openTab(projectId: "1")
        let cols = store.projectColumns(for: "1")
        XCTAssertEqual(cols.count, 3) // 2 existing + 1 new
        XCTAssertEqual(cols.last?.tabIds, [tab.id])
    }

    func testCloseTabInMultiPaneColumnFocusesNext() {
        let store = makeStore()
        store.setActiveProject("1")
        // Stack t1 and t2 in same column
        store.columns["1"] = [Column(id: "c1", tabIds: ["t1", "t2"])]
        store.setActiveTab("t1")

        store.closeTab("t1")

        XCTAssertEqual(store.activeTabId, "t2")
        XCTAssertEqual(store.projectColumns(for: "1").count, 1)
        XCTAssertEqual(store.projectColumns(for: "1")[0].tabIds, ["t2"])
    }

    func testCloseLastTabInColumnRemovesColumn() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t1")

        store.closeTab("t1")

        XCTAssertEqual(store.projectColumns(for: "1").count, 1)
        XCTAssertEqual(store.activeTabId, "t2")
    }

    func testRemoveProjectCleansUpColumns() {
        let store = makeStore()
        store.columnFocusedTab["c1"] = "t1"
        store.removeProject("1")
        XCTAssertNil(store.columns["1"])
        XCTAssertNil(store.columnFocusedTab["c1"])
    }
```

- [ ] **Step 6: Run tests**

Run: `xcodebuild test -scheme Blink -destination 'platform=macOS' -only-testing:BTests/AppStoreTests 2>&1 | tail -20`

- [ ] **Step 7: Commit**

```bash
git add Blink/Store/AppStore.swift BTests/AppStoreTests.swift
git commit -m "feat: migrate openTab/closeTab/removeProject to column model"
```

---

### Task 3: Focus Navigation — Columns + Vertical

**Files:**
- Modify: `Blink/Store/AppStore.swift:300-337` (focusLeft, focusRight) + new focusUp/focusDown
- Modify: `BTests/AppStoreTests.swift`

- [ ] **Step 1: Rewrite `focusLeft()` to use columns with focus memory**

```swift
    func focusLeft() {
        guard let projectId = activeProjectId else { return }
        let cols = projectColumns(for: projectId)

        if sidebarFocused { return }

        guard let currentCol = activeColumn,
              let colIdx = cols.firstIndex(where: { $0.id == currentCol.id }) else { return }

        // Save focus memory for current column
        if let tabId = activeTabId {
            columnFocusedTab[currentCol.id] = tabId
        }

        if colIdx > cols.startIndex {
            let targetCol = cols[cols.index(before: colIdx)]
            let targetTab = columnFocusedTab[targetCol.id] ?? targetCol.tabIds.first
            if let targetTab { setActiveTab(targetTab) }
        } else if sidebarVisible {
            sidebarFocused = true
        }
    }
```

- [ ] **Step 2: Rewrite `focusRight()` to use columns with focus memory**

```swift
    func focusRight() {
        guard let projectId = activeProjectId else { return }
        let cols = projectColumns(for: projectId)

        if sidebarFocused {
            sidebarFocused = false
            if let tabId = activeTabId {
                surfaceManager?.surface(for: tabId)?.focus()
            }
            return
        }

        guard let currentCol = activeColumn,
              let colIdx = cols.firstIndex(where: { $0.id == currentCol.id }) else { return }

        // Save focus memory for current column
        if let tabId = activeTabId {
            columnFocusedTab[currentCol.id] = tabId
        }

        let nextIdx = cols.index(after: colIdx)
        if nextIdx < cols.endIndex {
            let targetCol = cols[nextIdx]
            let targetTab = columnFocusedTab[targetCol.id] ?? targetCol.tabIds.first
            if let targetTab { setActiveTab(targetTab) }
        }
    }
```

- [ ] **Step 3: Add `focusUp()` and `focusDown()`**

Add after `focusRight()`:

```swift
    func focusDown() {
        guard let currentCol = activeColumn,
              let activeTabId,
              let paneIdx = currentCol.tabIds.firstIndex(of: activeTabId) else { return }

        let nextIdx = currentCol.tabIds.index(after: paneIdx)
        if nextIdx < currentCol.tabIds.endIndex {
            setActiveTab(currentCol.tabIds[nextIdx])
        }
    }

    func focusUp() {
        guard let currentCol = activeColumn,
              let activeTabId,
              let paneIdx = currentCol.tabIds.firstIndex(of: activeTabId) else { return }

        if paneIdx > currentCol.tabIds.startIndex {
            setActiveTab(currentCol.tabIds[currentCol.tabIds.index(before: paneIdx)])
        }
    }
```

- [ ] **Step 4: Write tests**

```swift
    // MARK: - Vertical Focus Tests

    func testFocusDown() {
        let store = makeStore()
        store.setActiveProject("1")
        store.columns["1"] = [Column(id: "c1", tabIds: ["t1", "t2"])]
        store.setActiveTab("t1")

        store.focusDown()

        XCTAssertEqual(store.activeTabId, "t2")
    }

    func testFocusDownNoOpAtBottom() {
        let store = makeStore()
        store.setActiveProject("1")
        store.columns["1"] = [Column(id: "c1", tabIds: ["t1", "t2"])]
        store.setActiveTab("t2")

        store.focusDown()

        XCTAssertEqual(store.activeTabId, "t2")
    }

    func testFocusUp() {
        let store = makeStore()
        store.setActiveProject("1")
        store.columns["1"] = [Column(id: "c1", tabIds: ["t1", "t2"])]
        store.setActiveTab("t2")

        store.focusUp()

        XCTAssertEqual(store.activeTabId, "t1")
    }

    func testFocusUpNoOpAtTop() {
        let store = makeStore()
        store.setActiveProject("1")
        store.columns["1"] = [Column(id: "c1", tabIds: ["t1", "t2"])]
        store.setActiveTab("t1")

        store.focusUp()

        XCTAssertEqual(store.activeTabId, "t1")
    }

    func testFocusLeftRestoresColumnMemory() {
        let store = makeStore()
        store.setActiveProject("1")
        store.columns["1"] = [
            Column(id: "c1", tabIds: ["t1"]),
            Column(id: "c2", tabIds: ["t2"]),
        ]
        store.sidebarVisible = false
        // Focus t2 in c2, then focus left to c1, then right back — should remember t2
        store.setActiveTab("t2")
        store.focusLeft()
        XCTAssertEqual(store.activeTabId, "t1")

        store.focusRight()
        XCTAssertEqual(store.activeTabId, "t2")
    }
```

- [ ] **Step 5: Run tests**

Run: `xcodebuild test -scheme Blink -destination 'platform=macOS' -only-testing:BTests/AppStoreTests 2>&1 | tail -20`

- [ ] **Step 6: Commit**

```bash
git add Blink/Store/AppStore.swift BTests/AppStoreTests.swift
git commit -m "feat: column-aware focus navigation with focusUp/focusDown"
```

---

### Task 4: Move Columns, Tab Cycling & Absorb/Expel

**Files:**
- Modify: `Blink/Store/AppStore.swift:339-371` (moveActiveTabLeft/Right) + new methods
- Modify: `BTests/AppStoreTests.swift`

- [ ] **Step 0: Delete old move tests that reference removed methods**

In `BTests/AppStoreTests.swift`, delete the following tests (they call `moveActiveTabLeft()`/`moveActiveTabRight()` which are being removed):
- `testMoveTabRight` (line 232)
- `testMoveTabLeft` (line 245)
- `testMoveTabRightNoOpAtEnd` (line 258)
- `testMoveTabLeftNoOpAtStart` (line 270)

- [ ] **Step 1: Replace `moveActiveTabLeft()` / `moveActiveTabRight()` with column-based versions**

Replace both methods (lines 339-371):

```swift
    func moveColumnLeft() {
        guard let projectId = activeProjectId,
              let currentCol = activeColumn else { return }
        var cols = projectColumns(for: projectId)
        guard let idx = cols.firstIndex(where: { $0.id == currentCol.id }),
              idx > cols.startIndex else { return }
        cols.swapAt(idx, cols.index(before: idx))
        columns[projectId] = cols
    }

    func moveColumnRight() {
        guard let projectId = activeProjectId,
              let currentCol = activeColumn else { return }
        var cols = projectColumns(for: projectId)
        guard let idx = cols.firstIndex(where: { $0.id == currentCol.id }) else { return }
        let nextIdx = cols.index(after: idx)
        guard nextIdx < cols.endIndex else { return }
        cols.swapAt(idx, nextIdx)
        columns[projectId] = cols
    }
```

- [ ] **Step 2: Update `selectNextTab()` / `selectPreviousTab()` to use column-major order**

Replace both methods (lines 267-298):

```swift
    func selectNextTab() {
        guard let projectId = activeProjectId else { return }
        let ordered = orderedTabs(for: projectId)
        guard !ordered.isEmpty else { return }

        guard let activeTabId,
              let currentIndex = ordered.firstIndex(where: { $0.id == activeTabId }) else {
            setActiveTab(ordered[0].id)
            return
        }

        let nextIndex = ordered.index(after: currentIndex)
        let tab = nextIndex < ordered.endIndex ? ordered[nextIndex] : ordered[0]
        setActiveTab(tab.id)
    }

    func selectPreviousTab() {
        guard let projectId = activeProjectId else { return }
        let ordered = orderedTabs(for: projectId)
        guard !ordered.isEmpty else { return }

        guard let activeTabId,
              let currentIndex = ordered.firstIndex(where: { $0.id == activeTabId }) else {
            setActiveTab(ordered[ordered.index(before: ordered.endIndex)].id)
            return
        }

        let tab = currentIndex > ordered.startIndex
            ? ordered[ordered.index(before: currentIndex)]
            : ordered[ordered.index(before: ordered.endIndex)]
        setActiveTab(tab.id)
    }
```

- [ ] **Step 3: Add absorb methods**

Add after `moveColumnRight()`:

```swift
    func absorbFromLeft() {
        guard let projectId = activeProjectId,
              let currentCol = activeColumn else { return }
        var cols = projectColumns(for: projectId)
        guard let colIdx = cols.firstIndex(where: { $0.id == currentCol.id }),
              colIdx > cols.startIndex else { return }

        let sourceIdx = cols.index(before: colIdx)
        guard let absorbedTabId = cols[sourceIdx].tabIds.last else { return }

        // Move tab from source column to current column
        cols[sourceIdx].tabIds.removeLast()
        cols[colIdx].tabIds.append(absorbedTabId)

        // Remove source column if empty
        if cols[sourceIdx].tabIds.isEmpty {
            columnFocusedTab[cols[sourceIdx].id] = nil
            cols.remove(at: sourceIdx)
        }

        columns[projectId] = cols
    }

    func absorbFromRight() {
        guard let projectId = activeProjectId,
              let currentCol = activeColumn else { return }
        var cols = projectColumns(for: projectId)
        guard let colIdx = cols.firstIndex(where: { $0.id == currentCol.id }) else { return }

        let sourceIdx = cols.index(after: colIdx)
        guard sourceIdx < cols.endIndex,
              let absorbedTabId = cols[sourceIdx].tabIds.last else { return }

        // Move tab from source column to current column
        cols[sourceIdx].tabIds.removeLast()
        cols[colIdx].tabIds.append(absorbedTabId)

        // Remove source column if empty
        if cols[sourceIdx].tabIds.isEmpty {
            columnFocusedTab[cols[sourceIdx].id] = nil
            cols.remove(at: sourceIdx)
        }

        columns[projectId] = cols
    }

    func expelActiveTab() {
        guard let projectId = activeProjectId,
              let activeTabId,
              let currentCol = activeColumn else { return }
        guard currentCol.tabIds.count > 1 else { return }

        var cols = projectColumns(for: projectId)
        guard let colIdx = cols.firstIndex(where: { $0.id == currentCol.id }) else { return }

        // Remove tab from current column
        cols[colIdx].tabIds.removeAll { $0 == activeTabId }

        // Create new column to the right
        let newCol = Column(id: UUID().uuidString, tabIds: [activeTabId])
        cols.insert(newCol, at: cols.index(after: colIdx))

        columns[projectId] = cols
        // Focus follows expelled tab (activeTabId unchanged)
    }
```

- [ ] **Step 4: Write tests**

```swift
    // MARK: - Column Move Tests

    func testMoveColumnRight() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t1")

        store.moveColumnRight()

        let cols = store.projectColumns(for: "1")
        XCTAssertEqual(cols[0].tabIds, ["t2"])
        XCTAssertEqual(cols[1].tabIds, ["t1"])
    }

    func testMoveColumnLeft() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t2")

        store.moveColumnLeft()

        let cols = store.projectColumns(for: "1")
        XCTAssertEqual(cols[0].tabIds, ["t2"])
        XCTAssertEqual(cols[1].tabIds, ["t1"])
    }

    func testMoveColumnRightNoOpAtEnd() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t2")

        store.moveColumnRight()

        let cols = store.projectColumns(for: "1")
        XCTAssertEqual(cols[0].tabIds, ["t1"])
        XCTAssertEqual(cols[1].tabIds, ["t2"])
    }

    // MARK: - Absorb & Expel Tests

    func testAbsorbFromLeft() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t2")

        store.absorbFromLeft()

        let cols = store.projectColumns(for: "1")
        XCTAssertEqual(cols.count, 1)
        XCTAssertEqual(cols[0].tabIds, ["t2", "t1"])
    }

    func testAbsorbFromRight() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t1")

        store.absorbFromRight()

        let cols = store.projectColumns(for: "1")
        XCTAssertEqual(cols.count, 1)
        XCTAssertEqual(cols[0].tabIds, ["t1", "t2"])
    }

    func testAbsorbFromLeftNoOpAtFirstColumn() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t1")

        store.absorbFromLeft()

        XCTAssertEqual(store.projectColumns(for: "1").count, 2)
    }

    func testExpelActiveTab() {
        let store = makeStore()
        store.setActiveProject("1")
        store.columns["1"] = [Column(id: "c1", tabIds: ["t1", "t2"])]
        store.setActiveTab("t1")

        store.expelActiveTab()

        let cols = store.projectColumns(for: "1")
        XCTAssertEqual(cols.count, 2)
        XCTAssertEqual(cols[0].tabIds, ["t2"])
        XCTAssertEqual(cols[1].tabIds, ["t1"])
        XCTAssertEqual(store.activeTabId, "t1")
    }

    func testExpelNoOpOnSingleTabColumn() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t1")

        store.expelActiveTab()

        XCTAssertEqual(store.projectColumns(for: "1").count, 2)
    }
```

- [ ] **Step 5: Run tests**

Run: `xcodebuild test -scheme Blink -destination 'platform=macOS' -only-testing:BTests/AppStoreTests 2>&1 | tail -20`

- [ ] **Step 6: Commit**

```bash
git add Blink/Store/AppStore.swift BTests/AppStoreTests.swift
git commit -m "feat: add moveColumn, absorb/expel, and column-major tab cycling"
```

---

### Task 5: Overview Migration to Columns

**Files:**
- Modify: `Blink/Store/AppStore.swift:373-413` (overview methods)
- Modify: `BTests/AppStoreTests.swift:282-371` (overview tests)

- [ ] **Step 1: Update overview methods to use columns**

Replace the entire overview section (lines 373-413):

```swift
    // MARK: - Overview Actions

    func toggleOverview() {
        guard let projectId = activeProjectId else { return }
        let cols = projectColumns(for: projectId)
        guard !cols.isEmpty else { return }

        if isOverviewMode {
            exitOverview(selecting: overviewHighlightedColumnId)
        } else {
            isOverviewMode = true
            overviewHighlightedColumnId = activeColumn?.id
        }
    }

    func exitOverview(selecting columnId: String?) {
        if let columnId,
           let col = projectColumns(for: activeProjectId ?? "").first(where: { $0.id == columnId }),
           let targetTab = columnFocusedTab[columnId] ?? col.tabIds.first {
            setActiveTab(targetTab)
        }
        isOverviewMode = false
        overviewHighlightedColumnId = nil
    }

    func overviewHighlightLeft() {
        guard let projectId = activeProjectId else { return }
        let cols = projectColumns(for: projectId)
        guard let highlightId = overviewHighlightedColumnId,
              let idx = cols.firstIndex(where: { $0.id == highlightId }),
              idx > cols.startIndex else { return }
        overviewHighlightedColumnId = cols[cols.index(before: idx)].id
    }

    func overviewHighlightRight() {
        guard let projectId = activeProjectId else { return }
        let cols = projectColumns(for: projectId)
        guard let highlightId = overviewHighlightedColumnId,
              let idx = cols.firstIndex(where: { $0.id == highlightId }) else { return }
        let next = cols.index(after: idx)
        guard next < cols.endIndex else { return }
        overviewHighlightedColumnId = cols[next].id
    }
```

- [ ] **Step 2: Update overview tests**

Replace the overview tests section to use column IDs:

```swift
    // MARK: - Overview Tests

    func testToggleOverviewEntersAndExits() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t1")

        store.toggleOverview()

        XCTAssertTrue(store.isOverviewMode)
        XCTAssertEqual(store.overviewHighlightedColumnId, "c1")

        store.toggleOverview()

        XCTAssertFalse(store.isOverviewMode)
        XCTAssertNil(store.overviewHighlightedColumnId)
    }

    func testEnterOverviewSetsHighlightToActiveColumn() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t2")

        store.toggleOverview()

        XCTAssertEqual(store.overviewHighlightedColumnId, "c2")
    }

    func testOverviewHighlightLeftRight() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t1")
        store.toggleOverview()

        store.overviewHighlightRight()
        XCTAssertEqual(store.overviewHighlightedColumnId, "c2")

        store.overviewHighlightLeft()
        XCTAssertEqual(store.overviewHighlightedColumnId, "c1")
    }

    func testOverviewHighlightStopsAtEdges() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t1")
        store.toggleOverview()

        store.overviewHighlightLeft()
        XCTAssertEqual(store.overviewHighlightedColumnId, "c1")

        store.overviewHighlightRight()
        store.overviewHighlightRight()
        XCTAssertEqual(store.overviewHighlightedColumnId, "c2")
    }

    func testExitOverviewWithColumnSelection() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t1")
        store.toggleOverview()

        store.exitOverview(selecting: "c2")

        XCTAssertFalse(store.isOverviewMode)
        XCTAssertNil(store.overviewHighlightedColumnId)
        XCTAssertEqual(store.activeTabId, "t2")
    }

    func testExitOverviewCancelKeepsOriginal() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t1")
        store.toggleOverview()

        store.overviewHighlightRight()
        store.exitOverview(selecting: nil)

        XCTAssertFalse(store.isOverviewMode)
        XCTAssertEqual(store.activeTabId, "t1")
    }

    func testOverviewNoOpWithNoTabs() {
        let store = makeStore()
        store.setActiveProject("4")

        store.toggleOverview()

        XCTAssertFalse(store.isOverviewMode)
        XCTAssertNil(store.overviewHighlightedColumnId)
    }
```

- [ ] **Step 3: Run tests**

Run: `xcodebuild test -scheme Blink -destination 'platform=macOS' -only-testing:BTests/AppStoreTests 2>&1 | tail -20`

- [ ] **Step 4: Commit**

```bash
git add Blink/Store/AppStore.swift BTests/AppStoreTests.swift
git commit -m "feat: migrate overview mode to column-based navigation"
```

---

### Task 6: WorkspaceLayoutState Migration

**Files:**
- Modify: `Blink/Views/WorkspaceLayoutState.swift` (entire file)

- [ ] **Step 1: Rename `tabId` parameters to `columnId` throughout**

Replace the file contents — the only change is renaming `tabId`/`tabIds` to `columnId`/`columnIds` in the public API:

```swift
import SwiftUI

@MainActor @Observable
final class WorkspaceLayoutState {
    /// Stores column width as a fraction of the viewport (e.g. 0.5 = half width).
    private var columnFractions: [String: [String: CGFloat]] = [:]
    private var preMaximizeFractions: [String: [String: CGFloat]] = [:]
    private var initializedProjects: Set<String> = []

    func sync(projectId: String, columnIds: [String], defaultFraction: CGFloat) {
        let existing = columnFractions[projectId] ?? [:]
        var next: [String: CGFloat] = [:]

        for columnId in columnIds {
            next[columnId] = existing[columnId] ?? defaultFraction
        }

        columnFractions[projectId] = next

        if columnIds.isEmpty {
            initializedProjects.remove(projectId)
        }
    }

    func width(for columnId: String, projectId: String, viewportWidth: CGFloat) -> CGFloat {
        let fraction = columnFractions[projectId]?[columnId] ?? Layout.workspaceColumnDefaultFraction
        return viewportWidth * fraction
    }

    func setFraction(_ fraction: CGFloat, for columnId: String, projectId: String) {
        var fractions = columnFractions[projectId] ?? [:]
        fractions[columnId] = fraction
        columnFractions[projectId] = fractions
    }

    func cyclePreset(for columnId: String, projectId: String, viewportWidth: CGFloat) -> CGFloat {
        let presets = Layout.workspaceColumnPresets
        let currentFraction = columnFractions[projectId]?[columnId] ?? Layout.workspaceColumnDefaultFraction
        let tolerance: CGFloat = 0.02

        var nextPreset = presets[0]
        for (i, preset) in presets.enumerated() {
            if abs(currentFraction - preset) < tolerance {
                nextPreset = presets[(i + 1) % presets.count]
                break
            }
            if i == presets.count - 1 {
                nextPreset = presets[0]
            }
        }

        setFraction(nextPreset, for: columnId, projectId: projectId)
        preMaximizeFractions[projectId]?.removeValue(forKey: columnId)
        return viewportWidth * nextPreset
    }

    func toggleMaximize(for columnId: String, projectId: String, viewportWidth: CGFloat) -> CGFloat {
        let currentFraction = columnFractions[projectId]?[columnId] ?? Layout.workspaceColumnDefaultFraction
        let tolerance: CGFloat = 0.02

        if abs(currentFraction - 1.0) < tolerance {
            let restored = preMaximizeFractions[projectId]?[columnId] ?? Layout.workspaceColumnDefaultFraction
            setFraction(restored, for: columnId, projectId: projectId)
            preMaximizeFractions[projectId]?.removeValue(forKey: columnId)
            return viewportWidth * restored
        } else {
            var saved = preMaximizeFractions[projectId] ?? [:]
            saved[columnId] = currentFraction
            preMaximizeFractions[projectId] = saved
            setFraction(1.0, for: columnId, projectId: projectId)
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

**Note:** Do NOT build or commit yet. `Shell.swift` still references old `tabId` parameters. Both files will be committed together at the end of Task 7.

---

### Task 7: Shell.swift — Rendering Overhaul

**Files:**
- Modify: `Blink/Views/Shell.swift:195-601` (WorkspaceColumnsView, WorkspaceColumnView, overviewThumbnail, stripLayout)

This is the largest task. The key changes:
1. Iterate `projectColumns(for:)` instead of `tabs`
2. `stripLayout()` keys frames by `column.id`
3. `columnStrip()` renders each column as a `VStack` of panes
4. `WorkspaceColumnView` accepts a column with multiple tabs
5. `focusedViewportOffset()` resolves `activeTabId → columnId`
6. Overview thumbnails use `overviewHighlightedColumnId`
7. `syncTabs()` becomes `syncColumns()` triggered by column changes
8. `Cmd+R`/`Cmd+F` use `column.id` instead of `tabId`

- [ ] **Step 1: Update `WorkspaceColumnsView` private computed properties**

Replace `tabs` computed property (line 208) and add `columns`:

```swift
    private var columns: [Column] {
        store.projectColumns(for: project.id)
    }

    private var tabs: [AppTab] {
        store.projectTabs(for: project.id)
    }
```

- [ ] **Step 2: Update `body` — change empty check and onChange triggers**

In the `body`, change `tabs.isEmpty` to `columns.isEmpty` (line 238).

Replace the `onChange(of: tabs.map(\.id)` block (line 250) with:

```swift
                    .onChange(of: columns.map(\.id), initial: true) { _, _ in
                        syncColumns(viewportWidth: geometry.size.width)
                        restoreViewport(viewportWidth: geometry.size.width)
                    }
```

Replace the `onKeyPress` for `rf` — change `tabId` to use column ID:

```swift
                    .onKeyPress(characters: CharacterSet(charactersIn: "rf")) { keyPress in
                        guard keyPress.modifiers == .command else { return .ignored }
                        guard !store.isOverviewMode else { return .ignored }
                        guard let colId = store.activeColumn?.id else { return .ignored }
                        switch keyPress.characters {
                        case "r":
                            let _ = layoutState.cyclePreset(for: colId, projectId: project.id, viewportWidth: geometry.size.width)
                            alignActiveTab(viewportWidth: geometry.size.width, animated: true)
                            return .handled
                        case "f":
                            let _ = layoutState.toggleMaximize(for: colId, projectId: project.id, viewportWidth: geometry.size.width)
                            alignActiveTab(viewportWidth: geometry.size.width, animated: true)
                            return .handled
                        default:
                            return .ignored
                        }
                    }
```

Replace `onChange(of: tabs.count)` (line 278) with column-aware version:

```swift
                    .onChange(of: columns.count) {
                        if store.isOverviewMode {
                            if columns.isEmpty {
                                store.exitOverview(selecting: nil)
                            } else if let highlightId = store.overviewHighlightedColumnId,
                                      !columns.contains(where: { $0.id == highlightId }) {
                                store.overviewHighlightedColumnId = columns.first?.id
                            }
                        }
                    }
```

- [ ] **Step 3: Rewrite `columnStrip()` to iterate columns**

```swift
    @ViewBuilder
    private func columnStrip(viewportWidth: CGFloat, viewportHeight: CGFloat) -> some View {
        let layout = stripLayout(viewportWidth: viewportWidth)
        let scale = overviewScale(contentWidth: layout.contentWidth, viewportWidth: viewportWidth)
        let isOverview = store.isOverviewMode

        let overviewOffsetX: CGFloat = {
            guard isOverview else { return 0 }
            let scaledContent = layout.contentWidth * scale
            let centered = (viewportWidth - scaledContent) / 2
            return max(centered, Layout.overviewPadding)
        }()

        let overviewOffsetY: CGFloat = {
            guard isOverview else { return 0 }
            let scaledHeight = viewportHeight * scale
            return (viewportHeight - scaledHeight) / 2
        }()

        ZStack(alignment: .topLeading) {
            ForEach(columns) { col in
                if let frame = layout.frames[col.id] {
                    if isOverview {
                        overviewThumbnail(column: col, frame: frame, viewportHeight: viewportHeight)
                            .frame(width: frame.width)
                            .frame(height: viewportHeight)
                            .offset(x: frame.minX)
                            .zIndex(store.overviewHighlightedColumnId == col.id ? 1 : 0)
                            .transition(workspaceColumnTransition)
                    } else {
                        WorkspaceColumnView(
                            column: col,
                            project: project,
                            activeTabId: store.activeTabId,
                            ghosttyApp: ghosttyApp,
                            surfaceManager: surfaceManager
                        )
                        .frame(width: frame.width)
                        .frame(height: viewportHeight)
                        .offset(x: frame.minX)
                        .zIndex(col.tabIds.contains(store.activeTabId ?? "") ? 1 : 0)
                        .transition(workspaceColumnTransition)
                    }
                }
            }
        }
        .frame(width: max(layout.contentWidth, viewportWidth), height: viewportHeight, alignment: .topLeading)
        .scaleEffect(scale, anchor: .topLeading)
        .offset(
            x: isOverview ? overviewOffsetX : -layout.viewportOffset,
            y: isOverview ? overviewOffsetY : 0
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .clipped()
        .contentShape(Rectangle())
        .animation(workspaceAnimation, value: columns.map(\.id))
        .animation(overviewAnimation, value: isOverview)
    }
```

- [ ] **Step 4: Rewrite `overviewThumbnail` to accept a Column**

```swift
    @ViewBuilder
    private func overviewThumbnail(column: Column, frame: CGRect, viewportHeight: CGFloat) -> some View {
        let isHighlighted = store.overviewHighlightedColumnId == column.id
        let columnTabs = column.tabIds.compactMap { tabId in
            store.tabs.first { $0.id == tabId }
        }

        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(theme.bg.opacity(0.6))
            .overlay {
                VStack(spacing: 4) {
                    ForEach(columnTabs) { tab in
                        Text(tab.label)
                            .font(Fonts.primary(size: 13))
                            .foregroundStyle(isHighlighted ? theme.text : theme.textDim)
                            .lineLimit(1)
                        if tab.id != columnTabs.last?.id {
                            theme.border.opacity(0.3).frame(height: 1)
                        }
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isHighlighted ? theme.accent.opacity(0.85) : theme.border.opacity(0.5), lineWidth: isHighlighted ? 2 : 1)
            )
            .shadow(color: isHighlighted ? theme.accent.opacity(0.3) : .clear, radius: 8)
            .animation(.easeInOut(duration: 0.15), value: isHighlighted)
            .onTapGesture {
                exitOverviewAnimated(selecting: column.id)
            }
    }
```

- [ ] **Step 5: Update `exitOverviewAnimated` to accept columnId**

```swift
    private func exitOverviewAnimated(selecting columnId: String?) {
        if let columnId,
           let col = columns.first(where: { $0.id == columnId }),
           let targetTab = store.columnFocusedTab[columnId] ?? col.tabIds.first {
            store.setActiveTab(targetTab)
            alignActiveTab(viewportWidth: currentViewportWidth, animated: false)
        }
        withAnimation(overviewAnimation) {
            store.isOverviewMode = false
            store.overviewHighlightedColumnId = nil
        }
        removeOverviewMonitor()
    }
```

Update the overview monitor's return/escape to pass column IDs:

```swift
            case 36: // return
                self.exitOverviewAnimated(selecting: store.overviewHighlightedColumnId)
                return nil
            case 53: // escape
                self.exitOverviewAnimated(selecting: nil)
                return nil
```

- [ ] **Step 6: Rewrite `stripLayout()` to use columns**

```swift
    private func stripLayout(viewportWidth: CGFloat) -> WorkspaceStripLayout {
        var frames: [String: CGRect] = [:]
        var leadingX: CGFloat = 0

        for col in columns {
            let width = columnWidth(for: col.id, viewportWidth: viewportWidth)
            frames[col.id] = CGRect(x: leadingX, y: 0, width: width, height: 0)
            leadingX += width + Layout.workspaceColumnSpacing
        }

        let contentWidth = max(0, leadingX - Layout.workspaceColumnSpacing)
        let viewportOffset = clampedViewportOffset(
            store.workspaceViewportOffset(for: project.id),
            contentWidth: contentWidth,
            viewportWidth: viewportWidth
        )

        return WorkspaceStripLayout(
            frames: frames,
            contentWidth: contentWidth,
            viewportOffset: viewportOffset
        )
    }

    private func columnWidth(for columnId: String, viewportWidth: CGFloat) -> CGFloat {
        let width = layoutState.width(
            for: columnId,
            projectId: project.id,
            viewportWidth: viewportWidth
        )
        return min(max(width, Layout.workspaceColumnMinWidth), Layout.workspaceColumnMaxWidth)
    }
```

- [ ] **Step 7: Update `focusedViewportOffset` to resolve tab → column**

```swift
    private func focusedViewportOffset(viewportWidth: CGFloat) -> CGFloat {
        guard let colId = store.activeColumn?.id else { return 0 }
        let layout = stripLayout(viewportWidth: viewportWidth)

        guard layout.contentWidth > viewportWidth else { return 0 }
        guard let frame = layout.frames[colId] else { return 0 }

        let centeredOffset = frame.minX - (viewportWidth - frame.width) / 2
        return clampedViewportOffset(
            centeredOffset,
            contentWidth: layout.contentWidth,
            viewportWidth: viewportWidth
        )
    }
```

- [ ] **Step 8: Update `syncTabs` → `syncColumns`**

```swift
    private func syncColumns(viewportWidth: CGFloat) {
        layoutState.sync(
            projectId: project.id,
            columnIds: columns.map(\.id),
            defaultFraction: Layout.workspaceColumnDefaultFraction
        )
    }
```

- [ ] **Step 9: Rewrite `WorkspaceColumnView` to render multiple panes**

```swift
private struct WorkspaceColumnView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let column: Column
    let project: Project
    let activeTabId: String?
    let ghosttyApp: GhosttyApp
    let surfaceManager: SurfaceManager

    private var columnTabs: [AppTab] {
        column.tabIds.compactMap { tabId in
            store.tabs.first { $0.id == tabId }
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(windowPanelBackground)

            VStack(spacing: 0) {
                ForEach(Array(columnTabs.enumerated()), id: \.element.id) { index, tab in
                    let isFocused = activeTabId == tab.id

                    TerminalView(
                        tabId: tab.id,
                        ghosttyApp: ghosttyApp,
                        surfaceManager: surfaceManager,
                        workingDirectory: project.path,
                        isFocused: isFocused,
                        command: tab.command
                    )
                    .overlay(
                        Group {
                            if columnTabs.count > 1 {
                                RoundedRectangle(cornerRadius: 0, style: .continuous)
                                    .strokeBorder(isFocused ? theme.accent.opacity(0.85) : .clear, lineWidth: 1)
                            }
                        }
                    )

                    if index < columnTabs.count - 1 {
                        theme.border.frame(height: Layout.columnPaneDividerHeight)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(
                    column.tabIds.contains(activeTabId ?? "")
                        ? theme.accent.opacity(0.85)
                        : theme.border,
                    lineWidth: 1
                )
        )
        .animation(.easeInOut(duration: 0.18), value: activeTabId)
    }

    private var windowPanelBackground: some ShapeStyle {
        AnyShapeStyle(Color.clear)
    }
}
```

- [ ] **Step 10: Build and verify**

Run: `xcodebuild build -scheme Blink -destination 'platform=macOS' 2>&1 | tail -10`

Fix any compilation errors. Run tests:

Run: `xcodebuild test -scheme Blink -destination 'platform=macOS' -only-testing:BTests/AppStoreTests 2>&1 | tail -20`

- [ ] **Step 11: Commit**

```bash
git add Blink/Views/Shell.swift Blink/Views/WorkspaceLayoutState.swift
git commit -m "feat: render columns with vertical pane stacking"
```

---

### Task 8: BApp.swift — Shortcuts

**Files:**
- Modify: `Blink/BApp.swift:113-178`

- [ ] **Step 1: Add vertical focus shortcuts and update move shortcuts**

In the `CommandGroup(after: .toolbar)` block, add after `Focus Right` (line 127):

```swift
                Button("Focus Down") {
                    store.focusDown()
                }
                .keyboardShortcut("j", modifiers: .command)

                Button("Focus Up") {
                    store.focusUp()
                }
                .keyboardShortcut("k", modifiers: .command)
```

Replace `Move Window Left` / `Move Window Right` (lines 129-137):

```swift
                Button("Move Column Left") {
                    store.moveColumnLeft()
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])

                Button("Move Column Right") {
                    store.moveColumnRight()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Button("Absorb from Left") {
                    store.absorbFromLeft()
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Button("Absorb from Right") {
                    store.absorbFromRight()
                }
                .keyboardShortcut("j", modifiers: [.command, .shift])

                Button("Expel Pane") {
                    store.expelActiveTab()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
```

- [ ] **Step 2: Update `Cmd+1-9` to use `orderedTabs`**

Replace the `ForEach(1...9)` block (lines 167-177):

```swift
                ForEach(1...9, id: \.self) { number in
                    Button("Window \(number)") {
                        if let projectId = store.activeProjectId {
                            let ordered = store.orderedTabs(for: projectId)
                            if number <= ordered.count {
                                store.setActiveTab(ordered[number - 1].id)
                            }
                        }
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
                }
```

- [ ] **Step 3: Build and run**

Run: `xcodebuild build -scheme Blink -destination 'platform=macOS' 2>&1 | tail -5`

- [ ] **Step 4: Commit**

```bash
git add Blink/BApp.swift
git commit -m "feat: add vertical focus, absorb/expel, and column move shortcuts"
```

---

### Task 9: Final Verification

- [ ] **Step 1: Run all tests**

Run: `xcodebuild test -scheme Blink -destination 'platform=macOS' -only-testing:BTests/AppStoreTests 2>&1 | tail -30`

Expected: All tests pass.

- [ ] **Step 2: Full build**

Run: `xcodebuild build -scheme Blink -destination 'platform=macOS' 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Manual verification**

```bash
pkill -f "Blink.app" 2>/dev/null; sleep 0.5
open $(find ~/Library/Developer/Xcode/DerivedData/Blink-*/Build/Products/Debug/Blink.app -maxdepth 0)
```

Verify:
1. Open project with 3+ terminals
2. `Cmd+Shift+K` — absorb left column into current (stacked vertically)
3. `Cmd+J` / `Cmd+K` — focus moves between stacked panes
4. `Cmd+Shift+E` — expel pane back to its own column
5. `Cmd+H` / `Cmd+L` — focus moves between columns, remembers pane
6. `Cmd+O` — overview shows columns (multi-pane columns show stacked labels)
7. `Cmd+R` — width presets cycle on the whole column
8. `Cmd+1-9` — jumps to correct tab in column-major order
