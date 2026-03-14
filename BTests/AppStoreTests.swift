import XCTest
@testable import Blink

final class AppStoreTests: XCTestCase {
    func testInitialState() {
        let store = AppStore()
        XCTAssertEqual(store.projects.count, 4)
        XCTAssertNil(store.activeProjectId)
        XCTAssertNil(store.activeTabId)
        XCTAssertTrue(store.sidebarVisible)
    }

    func testSetActiveProjectActivatesFirstTab() {
        let store = AppStore()
        store.setActiveProject("1") // has 2 tabs
        XCTAssertEqual(store.activeProjectId, "1")
        XCTAssertEqual(store.activeTabId, "t1")
    }

    func testSetActiveProjectNoTabs() {
        let store = AppStore()
        store.setActiveProject("4") // dotfiles — no tabs
        XCTAssertEqual(store.activeProjectId, "4")
        XCTAssertNil(store.activeTabId)
    }

    func testClearActiveProject() {
        let store = AppStore()
        store.setActiveProject("1")
        store.setActiveProject(nil)
        XCTAssertNil(store.activeProjectId)
        XCTAssertNil(store.activeTabId)
    }

    func testProjectTabs() {
        let store = AppStore()
        let tabs = store.projectTabs(for: "1")
        XCTAssertEqual(tabs.count, 2)
        XCTAssertEqual(tabs[0].label, "Terminal 1")
    }

    func testRemoveProject() {
        let store = AppStore()
        store.removeProject("1")
        XCTAssertEqual(store.projects.count, 3)
        XCTAssertFalse(store.projects.contains(where: { $0.id == "1" }))
    }

    func testRemoveActiveProjectClearsSelection() {
        let store = AppStore()
        store.setActiveProject("1")
        store.removeProject("1")
        XCTAssertNil(store.activeProjectId)
        XCTAssertNil(store.activeTabId)
    }

    func testTerminalCount() {
        let store = AppStore()
        XCTAssertEqual(store.terminalCount(for: "1"), 2)
        XCTAssertEqual(store.terminalCount(for: "2"), 1)
        XCTAssertEqual(store.terminalCount(for: "4"), 0)
    }

    func testSetActiveTab() {
        let store = AppStore()
        store.setActiveProject("1")
        store.setActiveTab("t2")
        XCTAssertEqual(store.activeTabId, "t2")
    }

    func testCloseTab() {
        let store = AppStore()
        store.setActiveProject("1")
        store.setActiveTab("t1")
        store.closeTab("t1")
        // Should activate last remaining tab in same project
        XCTAssertEqual(store.activeTabId, "t2")
        XCTAssertEqual(store.tabs.count, 2)
    }
}
