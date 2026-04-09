import XCTest
@testable import Blink

@MainActor
final class BrowserAppStoreTests: XCTestCase {
    private let defaults = UserDefaults.standard
    private let storageKeys = [
        "blink.workspaces",
        "blink.lastSelectedWorkspaceId",
        "blink.lastActiveTabs",
        "blink.workspaceViewportOffsets",
        "blink.columns",
        "blink.workspaceSetups",
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

    func testOpenBrowserTabForActiveWorkspaceDefaultsToHomePage() throws {
        let store = makeStore()
        store.setActiveWorkspace("workspace-1")

        let tab = try XCTUnwrap(store.openBrowserTabForActiveWorkspace())
        let browserTab = try XCTUnwrap(tab.browserState?.selectedTab)

        XCTAssertEqual(tab.kind, .browser)
        XCTAssertEqual(browserTab.state.urlString, BrowserDefaults.homePageURLString)
        XCTAssertEqual(browserTab.state.preferredFocus, .addressBar)
        XCTAssertEqual(store.activeTabId, tab.id)
        XCTAssertTrue(store.workspaceColumns(for: "workspace-1").contains { $0.tabIds == [tab.id] })
        XCTAssertTrue(store.consumePendingColumnMaximize(for: tab.id))
    }

    func testOpenNewTabForActiveSurfaceCreatesInternalBrowserTabWhenBrowserIsFocused() throws {
        let store = makeStore()
        let existing = store.openBrowserTab(workspaceId: "workspace-1", url: "https://example.com")
        store.setActiveTab(existing.id)

        store.openNewTabForActiveSurface()

        let browserTabs = store.workspaceTabs(for: "workspace-1").filter(\.isBrowser)
        XCTAssertEqual(browserTabs.count, 1)
        XCTAssertEqual(browserTabs.first?.browserState?.tabs.count, 2)
        XCTAssertEqual(browserTabs.first?.browserState?.selectedTab?.state.urlString, BrowserDefaults.homePageURLString)
        XCTAssertEqual(browserTabs.first?.browserState?.selectedTab?.state.preferredFocus, .addressBar)
    }

    func testOpenNewTabForActiveSurfaceCreatesTerminalTabWhenTerminalIsFocused() {
        let store = makeStore()
        let terminal = store.openTab(workspaceId: "workspace-1")
        store.setActiveTab(terminal.id)

        store.openNewTabForActiveSurface()

        XCTAssertEqual(store.workspaceTabs(for: "workspace-1").filter(\.isTerminal).count, 2)
    }

    func testOpenNewTabForActiveSurfaceCreatesTerminalTabWhenSidebarIsFocused() {
        let store = makeStore()
        let browser = store.openBrowserTab(workspaceId: "workspace-1", url: "https://example.com")
        store.setActiveTab(browser.id)
        store.sidebarFocused = true

        store.openNewTabForActiveSurface()

        XCTAssertEqual(store.workspaceTabs(for: "workspace-1").filter(\.isBrowser).count, 1)
        XCTAssertEqual(store.workspaceTabs(for: "workspace-1").filter(\.isTerminal).count, 1)
    }

    func testOpenOrFocusBrowserTabReusesExistingURLTab() {
        let store = makeStore()
        let first = store.openBrowserTab(workspaceId: "workspace-1", url: "https://example.com/docs")

        let second = store.openOrFocusBrowserTab(workspaceId: "workspace-1", url: "https://example.com/docs")

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(store.workspaceTabs(for: "workspace-1").filter(\.isBrowser).count, 1)
        XCTAssertEqual(store.activeTabId, first.id)
    }

    func testClosingBrowserTabDestroysItsController() {
        let store = makeStore()
        let manager = BrowserManager()
        store.browserManager = manager

        let tab = store.openBrowserTab(workspaceId: "workspace-1", url: "https://example.com")
        let browserTab = try! XCTUnwrap(tab.browserState?.selectedTab)
        let firstController = manager.controller(
            for: browserTab.id,
            workspaceId: "workspace-1",
            profileId: Profile.personalId,
            initialState: browserTab.state
        ) { _ in }

        store.closeTab(tab.id)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let secondController = manager.controller(
            for: browserTab.id,
            workspaceId: "workspace-1",
            profileId: Profile.personalId,
            initialState: .blank
        ) { _ in }
        XCTAssertFalse((firstController as AnyObject) === (secondController as AnyObject))
    }

    func testSetBrowserFocusTargetUpdatesStoredBrowserState() {
        let store = makeStore()
        let tab = store.openBrowserTab(workspaceId: "workspace-1", url: nil)
        let browserTabId = try! XCTUnwrap(tab.browserState?.selectedTab?.id)

        store.setBrowserFocusTarget(.webView, for: browserTabId, in: tab.id)

        XCTAssertEqual(store.tabsById[tab.id]?.browserState?.selectedTab?.state.preferredFocus, .webView)
    }

    func testSelectingDifferentBrowserTabFocusesWebViewInsteadOfAddressBar() throws {
        let store = makeStore()
        let tab = store.openBrowserTab(workspaceId: "workspace-1", url: nil, fullWidth: false, maximizeColumn: false)
        let firstBrowserTabId = try XCTUnwrap(tab.browserState?.selectedTab?.id)
        let secondBrowserTab = try XCTUnwrap(
            store.openBrowserTabInPane(
                tab.id,
                url: "https://daily.dev",
                preferredFocus: .addressBar
            )
        )

        store.setBrowserFocusTarget(.addressBar, for: firstBrowserTabId, in: tab.id)
        store.selectBrowserTab(firstBrowserTabId, in: tab.id)
        store.selectBrowserTab(secondBrowserTab.id, in: tab.id)

        let selectedTab = try XCTUnwrap(store.tabsById[tab.id]?.browserState?.selectedTab)
        XCTAssertEqual(selectedTab.id, secondBrowserTab.id)
        XCTAssertEqual(selectedTab.state.preferredFocus, .webView)
    }

    func testToggleActiveBrowserSidebarPinnedUpdatesActiveBrowserPane() {
        let store = makeStore()
        let tab = store.openBrowserTab(workspaceId: "workspace-1", url: "https://example.com")
        store.setActiveTab(tab.id)

        store.toggleActiveBrowserSidebarPinned()

        XCTAssertEqual(store.tabsById[tab.id]?.browserState?.isSidebarPinned, true)
    }

    func testToggleBrowserTabPinnedMovesTabIntoPinnedSectionOrder() throws {
        let store = makeStore()
        let tab = store.openBrowserTab(workspaceId: "workspace-1", url: "https://example.com", fullWidth: false, maximizeColumn: false)
        let firstBrowserTabId = try XCTUnwrap(store.tabsById[tab.id]?.browserState?.selectedTab?.id)
        let secondBrowserTab = try XCTUnwrap(store.openBrowserTabInPane(tab.id, url: "https://daily.dev"))

        store.toggleBrowserTabPinned(secondBrowserTab.id, in: tab.id)

        let orderedTabs = try XCTUnwrap(store.tabsById[tab.id]?.browserState?.tabs)
        XCTAssertEqual(orderedTabs.first?.id, secondBrowserTab.id)
        XCTAssertEqual(orderedTabs.first?.isPinned, true)
        XCTAssertEqual(orderedTabs.last?.id, firstBrowserTabId)
    }

    func testCloseActiveTabClosesSelectedInternalBrowserTabBeforeClosingPane() {
        let store = makeStore()
        let tab = store.openBrowserTab(workspaceId: "workspace-1", url: "https://example.com")
        _ = store.openBrowserTabInPane(tab.id, url: "https://daily.dev")
        store.setActiveTab(tab.id)

        store.closeActiveTab()

        XCTAssertEqual(store.workspaceTabs(for: "workspace-1").filter(\.isBrowser).count, 1)
        XCTAssertEqual(store.tabsById[tab.id]?.browserState?.tabs.count, 1)
    }

    func testCloseActiveTabClosesSingleBrowserPane() {
        let store = makeStore()
        let tab = store.openBrowserTab(workspaceId: "workspace-1", url: "https://example.com", fullWidth: false, maximizeColumn: false)
        store.setActiveTab(tab.id)

        store.closeActiveTab()

        XCTAssertNil(store.tabsById[tab.id])
        XCTAssertEqual(store.workspaceTabs(for: "workspace-1").filter(\.isBrowser).count, 0)
    }

    func testCloseActiveTabClosesSingleFullWidthBrowserPane() {
        let store = makeStore()
        let terminal = store.openTab(workspaceId: "workspace-1")
        let browser = store.openBrowserTab(workspaceId: "workspace-1", url: "https://example.com")
        store.setActiveTab(browser.id)

        store.closeActiveTab()

        XCTAssertNil(store.tabsById[browser.id])
        XCTAssertEqual(store.workspaceTabs(for: "workspace-1").filter(\.isBrowser).count, 0)
        XCTAssertEqual(store.activeTabId, terminal.id)
    }

    func testOpenBrowserTabDefaultsToMaximizedColumn() {
        let store = makeStore()

        let browser = store.openBrowserTab(workspaceId: "workspace-1", url: "https://example.com")

        XCTAssertFalse(store.isFullWidthTab(browser.id))
        XCTAssertEqual(store.workspaceColumns(for: "workspace-1").count, 1)
        XCTAssertEqual(store.workspaceColumns(for: "workspace-1").first?.tabIds, [browser.id])
        XCTAssertTrue(store.consumePendingColumnMaximize(for: browser.id))
    }

    func testOpenBrowserTabSupportsExplicitFullWidthMode() {
        let store = makeStore()
        let terminal = store.openTab(workspaceId: "workspace-1")

        let browser = store.openBrowserTab(
            workspaceId: "workspace-1",
            url: "https://example.com",
            fullWidth: true
        )

        XCTAssertTrue(store.isFullWidthTab(browser.id))
        XCTAssertEqual(store.workspaceColumns(for: "workspace-1").count, 1)
        XCTAssertEqual(store.workspaceColumns(for: "workspace-1").first?.tabIds, [browser.id])

        store.closeTab(browser.id)

        XCTAssertEqual(store.activeTabId, terminal.id)
        XCTAssertEqual(store.workspaceColumns(for: "workspace-1").count, 1)
        XCTAssertEqual(store.workspaceColumns(for: "workspace-1").first?.tabIds, [terminal.id])
    }

    private func makeStore() -> AppStore {
        let workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("blink-browser-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: workspaceURL,
            withIntermediateDirectories: true
        )

        let store = AppStore()
        store.workspaces = [
            Workspace(
                id: "workspace-1",
                name: "Blink",
                path: workspaceURL.path,
                color: "#ffffff",
                createdAt: .distantPast
            )
        ]
        store.columns = [:]
        store.tabs = []
        store.activeWorkspaceId = "workspace-1"
        return store
    }
}
