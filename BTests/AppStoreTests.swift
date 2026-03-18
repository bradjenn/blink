import XCTest
@testable import Blink

@MainActor
final class AppStoreTests: XCTestCase {
    private let defaults = UserDefaults.standard
    private let storageKeys = [
        "blink.theme",
        "blink.backgroundImage",
        "blink.backgroundOpacity",
        "blink.backgroundBlur",
        "blink.hideTitleBar",
        "blink.sidebarVisible",
        "blink.projects",
        "blink.lastSelectedProjectId",
        "blink.lastActiveTabs",
        "blink.workspaceViewportOffsets",
    ]

    private var savedDefaults: [String: Any?] = [:]

    override func setUpWithError() throws {
        savedDefaults = [:]
        for key in storageKeys {
            savedDefaults[key] = defaults.object(forKey: key)
            defaults.removeObject(forKey: key)
        }
    }

    override func tearDownWithError() throws {
        for key in storageKeys {
            if let value = savedDefaults[key] {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

    func testInitialState() {
        let store = AppStore()
        XCTAssertEqual(store.projects.count, 0)
        XCTAssertNil(store.activeProjectId)
        XCTAssertNil(store.activeTabId)
        XCTAssertTrue(store.sidebarVisible)
    }

    func testSetActiveProjectActivatesFirstTab() {
        let store = makeStore()
        store.setActiveProject("1")
        XCTAssertEqual(store.activeProjectId, "1")
        XCTAssertEqual(store.activeTabId, "t1")
    }

    func testSetActiveProjectNoTabs() {
        let store = makeStore()
        store.setActiveProject("4")
        XCTAssertEqual(store.activeProjectId, "4")
        XCTAssertNil(store.activeTabId)
    }

    func testClearActiveProject() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveProject(nil)
        XCTAssertNil(store.activeProjectId)
        XCTAssertNil(store.activeTabId)
    }

    func testProjectTabs() {
        let store = makeStore()
        let tabs = store.projectTabs(for: "1")
        XCTAssertEqual(tabs.count, 2)
        XCTAssertEqual(tabs[0].label, "Terminal 1")
    }

    func testRemoveProject() {
        let store = makeStore()
        store.removeProject("1")
        XCTAssertEqual(store.projects.count, 3)
        XCTAssertFalse(store.projects.contains(where: { $0.id == "1" }))
    }

    func testRemoveActiveProjectClearsSelection() {
        let store = makeStore()
        store.setActiveProject("1")
        store.removeProject("1")
        XCTAssertNil(store.activeProjectId)
        XCTAssertNil(store.activeTabId)
    }

    func testTerminalCount() {
        let store = makeStore()
        XCTAssertEqual(store.terminalCount(for: "1"), 2)
        XCTAssertEqual(store.terminalCount(for: "2"), 1)
        XCTAssertEqual(store.terminalCount(for: "4"), 0)
    }

    func testSetActiveTab() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t2")
        XCTAssertEqual(store.activeTabId, "t2")
    }

    func testSelectNextTabWrapsWithinProject() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t2")

        store.selectNextTab()

        XCTAssertEqual(store.activeTabId, "t1")
    }

    func testSelectPreviousTabWrapsWithinProject() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t1")

        store.selectPreviousTab()

        XCTAssertEqual(store.activeTabId, "t2")
    }

    func testCloseTab() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t1")
        store.closeTab("t1")
        XCTAssertEqual(store.activeTabId, "t2")
        XCTAssertEqual(store.tabs.count, 2)
    }

    func testHideTitleBarPersists() {
        XCTAssertFalse(AppStore().hideTitleBar)

        let store = AppStore()
        store.hideTitleBar = true

        XCTAssertTrue(AppStore().hideTitleBar)
    }

    func testLastActiveTabPersistsPerProject() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t2")

        let reloaded = AppStore()
        reloaded.projects = store.projects
        reloaded.tabs = store.tabs

        reloaded.setActiveProject("1")

        XCTAssertEqual(reloaded.activeTabId, "t2")
    }

    func testWorkspaceViewportOffsetPersists() {
        let store = AppStore()
        store.setWorkspaceViewportOffset(184, for: "1")

        XCTAssertEqual(AppStore().workspaceViewportOffset(for: "1"), 184, accuracy: 0.001)
    }

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

    // MARK: - Overview Tests

    func testToggleOverviewEntersAndExits() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t1")

        store.toggleOverview()

        XCTAssertTrue(store.isOverviewMode)
        XCTAssertEqual(store.overviewHighlightedColumnId, "t1")

        store.toggleOverview()

        XCTAssertFalse(store.isOverviewMode)
        XCTAssertNil(store.overviewHighlightedColumnId)
    }

    func testEnterOverviewSetsHighlight() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t2")

        store.toggleOverview()

        XCTAssertEqual(store.overviewHighlightedColumnId, "t2")
    }

    func testOverviewHighlightLeftRight() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t1")
        store.toggleOverview()

        store.overviewHighlightRight()
        XCTAssertEqual(store.overviewHighlightedColumnId, "t2")

        store.overviewHighlightLeft()
        XCTAssertEqual(store.overviewHighlightedColumnId, "t1")
    }

    func testOverviewHighlightStopsAtEdges() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t1")
        store.toggleOverview()

        store.overviewHighlightLeft()
        XCTAssertEqual(store.overviewHighlightedColumnId, "t1")

        store.overviewHighlightRight()
        store.overviewHighlightRight()
        XCTAssertEqual(store.overviewHighlightedColumnId, "t2")
    }

    func testExitOverviewWithSelection() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t1")
        store.toggleOverview()

        store.exitOverview(selecting: "t2")

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

    private func project(id: String, name: String) -> Project {
        Project(
            id: id,
            name: name,
            path: "/tmp/\(name)",
            color: "#7aa2f7",
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }
}
