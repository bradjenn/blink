import XCTest
@testable import Blink

@MainActor
final class BrowserAppStoreTests: XCTestCase {
    private let defaults = UserDefaults.standard
    private let storageKeys = [
        "blink.projects",
        "blink.lastSelectedProjectId",
        "blink.lastActiveTabs",
        "blink.workspaceViewportOffsets",
        "blink.columns",
        "blink.projectSetups",
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

    func testOpenBrowserTabForActiveProjectDefaultsToHomePage() throws {
        let store = makeStore()
        store.setActiveProject("project-1")

        let tab = try XCTUnwrap(store.openBrowserTabForActiveProject(url: nil, maximizeColumn: false))
        let browserTab = try XCTUnwrap(tab.browserState?.selectedTab)

        XCTAssertEqual(tab.kind, .browser)
        XCTAssertEqual(browserTab.state.urlString, BrowserDefaults.homePageURLString)
        XCTAssertEqual(browserTab.state.preferredFocus, .webView)
        XCTAssertEqual(store.activeTabId, tab.id)
        XCTAssertTrue(store.projectColumns(for: "project-1").contains { $0.tabIds == [tab.id] })
    }

    func testOpenNewTabForActiveSurfaceCreatesInternalBrowserTabWhenBrowserIsFocused() throws {
        let store = makeStore()
        let existing = store.openBrowserTab(projectId: "project-1", url: "https://example.com")
        store.setActiveTab(existing.id)

        store.openNewTabForActiveSurface()

        let browserTabs = store.projectTabs(for: "project-1").filter(\.isBrowser)
        XCTAssertEqual(browserTabs.count, 1)
        XCTAssertEqual(browserTabs.first?.browserState?.tabs.count, 2)
        XCTAssertEqual(browserTabs.first?.browserState?.selectedTab?.state.urlString, BrowserDefaults.homePageURLString)
    }

    func testOpenNewTabForActiveSurfaceCreatesTerminalTabWhenTerminalIsFocused() {
        let store = makeStore()
        let terminal = store.openTab(projectId: "project-1")
        store.setActiveTab(terminal.id)

        store.openNewTabForActiveSurface()

        XCTAssertEqual(store.projectTabs(for: "project-1").filter(\.isTerminal).count, 2)
    }

    func testOpenNewTabForActiveSurfaceCreatesTerminalTabWhenSidebarIsFocused() {
        let store = makeStore()
        let browser = store.openBrowserTab(projectId: "project-1", url: "https://example.com")
        store.setActiveTab(browser.id)
        store.sidebarFocused = true

        store.openNewTabForActiveSurface()

        XCTAssertEqual(store.projectTabs(for: "project-1").filter(\.isBrowser).count, 1)
        XCTAssertEqual(store.projectTabs(for: "project-1").filter(\.isTerminal).count, 1)
    }

    func testOpenOrFocusBrowserTabReusesExistingURLTab() {
        let store = makeStore()
        let first = store.openBrowserTab(projectId: "project-1", url: "https://example.com/docs")

        let second = store.openOrFocusBrowserTab(projectId: "project-1", url: "https://example.com/docs")

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(store.projectTabs(for: "project-1").filter(\.isBrowser).count, 1)
        XCTAssertEqual(store.activeTabId, first.id)
    }

    func testClosingBrowserTabDestroysItsController() {
        let store = makeStore()
        let manager = BrowserManager()
        store.browserManager = manager

        let tab = store.openBrowserTab(projectId: "project-1", url: "https://example.com")
        let browserTab = try! XCTUnwrap(tab.browserState?.selectedTab)
        let firstController = manager.controller(
            for: browserTab.id,
            projectId: "project-1",
            initialState: browserTab.state
        ) { _ in }

        store.closeTab(tab.id)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let secondController = manager.controller(
            for: browserTab.id,
            projectId: "project-1",
            initialState: .blank
        ) { _ in }
        XCTAssertFalse((firstController as AnyObject) === (secondController as AnyObject))
    }

    func testSetBrowserFocusTargetUpdatesStoredBrowserState() {
        let store = makeStore()
        let tab = store.openBrowserTab(projectId: "project-1", url: nil)
        let browserTabId = try! XCTUnwrap(tab.browserState?.selectedTab?.id)

        store.setBrowserFocusTarget(.webView, for: browserTabId, in: tab.id)

        XCTAssertEqual(store.tabsById[tab.id]?.browserState?.selectedTab?.state.preferredFocus, .webView)
    }

    func testToggleActiveBrowserSidebarPinnedUpdatesActiveBrowserPane() {
        let store = makeStore()
        let tab = store.openBrowserTab(projectId: "project-1", url: "https://example.com")
        store.setActiveTab(tab.id)

        store.toggleActiveBrowserSidebarPinned()

        XCTAssertEqual(store.tabsById[tab.id]?.browserState?.isSidebarPinned, true)
    }

    func testCloseActiveTabClosesSelectedInternalBrowserTabBeforeClosingPane() {
        let store = makeStore()
        let tab = store.openBrowserTab(projectId: "project-1", url: "https://example.com")
        _ = store.openBrowserTabInPane(tab.id, url: "https://daily.dev")
        store.setActiveTab(tab.id)

        store.closeActiveTab()

        XCTAssertEqual(store.projectTabs(for: "project-1").filter(\.isBrowser).count, 1)
        XCTAssertEqual(store.tabsById[tab.id]?.browserState?.tabs.count, 1)
    }

    func testCloseActiveTabKeepsSingleBrowserPaneOpen() throws {
        let store = makeStore()
        let tab = store.openBrowserTab(projectId: "project-1", url: "https://example.com")
        store.setActiveTab(tab.id)

        store.closeActiveTab()

        let remainingPane = try XCTUnwrap(store.tabsById[tab.id])
        let remainingBrowserTab = try XCTUnwrap(remainingPane.browserState?.selectedTab)
        XCTAssertEqual(store.projectTabs(for: "project-1").filter(\.isBrowser).count, 1)
        XCTAssertEqual(remainingPane.browserState?.tabs.count, 1)
        XCTAssertEqual(remainingBrowserTab.state.urlString, BrowserDefaults.homePageURLString)
    }

    private func makeStore() -> AppStore {
        let store = AppStore()
        store.projects = [
            Project(
                id: "project-1",
                name: "Blink",
                path: "/tmp/blink",
                color: "#ffffff",
                createdAt: .distantPast
            )
        ]
        store.columns = [:]
        store.tabs = []
        store.activeProjectId = "project-1"
        return store
    }
}
