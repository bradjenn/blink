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

        XCTAssertEqual(tab.kind, .browser)
        XCTAssertEqual(tab.browserState?.urlString, BrowserDefaults.homePageURLString)
        XCTAssertEqual(tab.browserState?.preferredFocus, .webView)
        XCTAssertEqual(store.activeTabId, tab.id)
        XCTAssertTrue(store.projectColumns(for: "project-1").contains { $0.tabIds == [tab.id] })
    }

    func testOpenNewTabForActiveSurfaceCreatesBrowserTabWhenBrowserIsFocused() throws {
        let store = makeStore()
        let existing = store.openBrowserTab(projectId: "project-1", url: "https://example.com")
        store.setActiveTab(existing.id)

        store.openNewTabForActiveSurface()

        let browserTabs = store.projectTabs(for: "project-1").filter(\.isBrowser)
        XCTAssertEqual(browserTabs.count, 2)
        XCTAssertEqual(browserTabs.last?.browserState?.urlString, BrowserDefaults.homePageURLString)
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
        let firstController = manager.controller(
            for: tab.id,
            projectId: "project-1",
            initialState: tab.browserState ?? .blank
        ) { _ in }

        store.closeTab(tab.id)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let secondController = manager.controller(
            for: tab.id,
            projectId: "project-1",
            initialState: .blank
        ) { _ in }
        XCTAssertFalse((firstController as AnyObject) === (secondController as AnyObject))
    }

    func testSetBrowserFocusTargetUpdatesStoredBrowserState() {
        let store = makeStore()
        let tab = store.openBrowserTab(projectId: "project-1", url: nil)

        store.setBrowserFocusTarget(.webView, for: tab.id)

        XCTAssertEqual(store.tabsById[tab.id]?.browserState?.preferredFocus, .webView)
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
