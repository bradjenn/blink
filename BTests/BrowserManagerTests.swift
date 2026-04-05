import XCTest
@testable import Blink

@MainActor
final class BrowserManagerTests: XCTestCase {
    private var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: #filePath)
        testDefaults.removePersistentDomain(forName: #filePath)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: #filePath)
        testDefaults = nil
        super.tearDown()
    }

    func testExistingControllerRemainsSourceOfTruthForLiveBrowserState() {
        let manager = BrowserManager(userDefaults: testDefaults)
        let firstController = manager.controller(
            for: "browser-tab",
            projectId: "project-1",
            initialState: .blank
        ) { _ in }

        let secondController = manager.controller(
            for: "browser-tab",
            projectId: "project-1",
            initialState: BrowserTabState(urlString: "https://example.com")
        ) { _ in }

        XCTAssertTrue((firstController as AnyObject) === (secondController as AnyObject))
        XCTAssertNil(secondController.session.state.urlString)
    }

    func testRecentDownloadsAreScopedByProjectAndSortedNewestFirst() {
        let manager = BrowserManager(userDefaults: testDefaults)
        let older = BrowserDownloadItem(
            id: "project-1:1",
            browserTabId: "tab-1",
            projectId: "project-1",
            sourceURLString: "https://example.com/one.zip",
            suggestedFileName: "one.zip",
            destinationPath: "/Users/bradley/Downloads/one.zip",
            receivedBytes: 10,
            totalBytes: 20,
            percentComplete: 50,
            currentSpeed: 10,
            isInProgress: true,
            isComplete: false,
            isCanceled: false,
            isInterrupted: false,
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let newer = BrowserDownloadItem(
            id: "project-1:2",
            browserTabId: "tab-2",
            projectId: "project-1",
            sourceURLString: "https://example.com/two.zip",
            suggestedFileName: "two.zip",
            destinationPath: "/Users/bradley/Downloads/two.zip",
            receivedBytes: 20,
            totalBytes: 20,
            percentComplete: 100,
            currentSpeed: 0,
            isInProgress: false,
            isComplete: true,
            isCanceled: false,
            isInterrupted: false,
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        let otherProject = BrowserDownloadItem(
            id: "project-2:1",
            browserTabId: "tab-3",
            projectId: "project-2",
            sourceURLString: "https://example.com/three.zip",
            suggestedFileName: "three.zip",
            destinationPath: "/Users/bradley/Downloads/three.zip",
            receivedBytes: 5,
            totalBytes: 10,
            percentComplete: 50,
            currentSpeed: 10,
            isInProgress: true,
            isComplete: false,
            isCanceled: false,
            isInterrupted: false,
            updatedAt: Date(timeIntervalSince1970: 3)
        )

        manager.downloads = [older, newer, otherProject]

        XCTAssertEqual(manager.recentDownloads(for: "project-1").map(\.id), [newer.id, older.id])
    }

    func testDownloadsPersistAcrossManagerRelaunch() {
        let persisted = BrowserDownloadItem(
            id: "project-1:1",
            browserTabId: "tab-1",
            projectId: "project-1",
            sourceURLString: "https://example.com/archive.zip",
            suggestedFileName: "archive.zip",
            destinationPath: "/Users/bradley/Downloads/archive.zip",
            receivedBytes: 20,
            totalBytes: 20,
            percentComplete: 100,
            currentSpeed: 0,
            isInProgress: false,
            isComplete: true,
            isCanceled: false,
            isInterrupted: false,
            updatedAt: Date(timeIntervalSince1970: 20)
        )

        let firstManager = BrowserManager(userDefaults: testDefaults)
        firstManager.downloads = [persisted]

        let secondManager = BrowserManager(userDefaults: testDefaults)
        XCTAssertEqual(secondManager.downloads, [persisted])
    }

    func testClearDownloadsOnlyRemovesActiveProjectHistory() {
        let projectOne = BrowserDownloadItem(
            id: "project-1:1",
            browserTabId: "tab-1",
            projectId: "project-1",
            sourceURLString: "https://example.com/one.zip",
            suggestedFileName: "one.zip",
            destinationPath: "/Users/bradley/Downloads/one.zip",
            receivedBytes: 20,
            totalBytes: 20,
            percentComplete: 100,
            currentSpeed: 0,
            isInProgress: false,
            isComplete: true,
            isCanceled: false,
            isInterrupted: false,
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let projectTwo = BrowserDownloadItem(
            id: "project-2:1",
            browserTabId: "tab-2",
            projectId: "project-2",
            sourceURLString: "https://example.com/two.zip",
            suggestedFileName: "two.zip",
            destinationPath: "/Users/bradley/Downloads/two.zip",
            receivedBytes: 20,
            totalBytes: 20,
            percentComplete: 100,
            currentSpeed: 0,
            isInProgress: false,
            isComplete: true,
            isCanceled: false,
            isInterrupted: false,
            updatedAt: Date(timeIntervalSince1970: 2)
        )

        let manager = BrowserManager(userDefaults: testDefaults)
        manager.downloads = [projectOne, projectTwo]

        manager.clearDownloads(for: "project-1")

        XCTAssertEqual(manager.downloads, [projectTwo])
        let reloadedManager = BrowserManager(userDefaults: testDefaults)
        XCTAssertEqual(reloadedManager.downloads, [projectTwo])
    }

    func testHistoryEntriesPersistAcrossManagerRelaunch() {
        let firstManager = BrowserManager(userDefaults: testDefaults)
        firstManager.recordHistoryEntry(
            from: BrowserTabState(
                urlString: "http://localhost:3000/dashboard",
                title: "Local Dashboard",
                isLoading: false,
                preferredFocus: .webView
            )
        )

        let secondManager = BrowserManager(userDefaults: testDefaults)
        XCTAssertEqual(secondManager.historyEntries.count, 1)
        XCTAssertEqual(secondManager.historyEntries.first?.urlString, "http://localhost:3000/dashboard")
        XCTAssertEqual(secondManager.historyEntries.first?.title, "Local Dashboard")
    }

    func testAddressBarSuggestionsFilterByHostTitleAndURL() {
        let manager = BrowserManager(userDefaults: testDefaults)
        manager.recordHistoryEntry(
            from: BrowserTabState(
                urlString: "https://docs.swift.org/swift-book/documentation/the-swift-programming-language/",
                title: "The Swift Programming Language",
                isLoading: false,
                preferredFocus: .webView
            )
        )
        manager.recordHistoryEntry(
            from: BrowserTabState(
                urlString: "https://github.com/openai/openai-cookbook",
                title: "openai-cookbook",
                isLoading: false,
                preferredFocus: .webView
            )
        )

        XCTAssertEqual(
            manager.addressBarSuggestions(for: "swift").map(\.urlString),
            ["https://docs.swift.org/swift-book/documentation/the-swift-programming-language/"]
        )
        XCTAssertEqual(
            manager.addressBarSuggestions(for: "github").map(\.urlString),
            ["https://github.com/openai/openai-cookbook"]
        )
    }

    func testAddressBarSuggestionsPreferLocalMatches() {
        let manager = BrowserManager(userDefaults: testDefaults)
        manager.recordHistoryEntry(
            from: BrowserTabState(
                urlString: "https://dashboard.example.com/projects",
                title: "Dashboard",
                isLoading: false,
                preferredFocus: .webView
            )
        )
        manager.recordHistoryEntry(
            from: BrowserTabState(
                urlString: "http://localhost:3000/dashboard",
                title: "Local Dashboard",
                isLoading: false,
                preferredFocus: .webView
            )
        )

        XCTAssertEqual(
            manager.addressBarSuggestions(for: "dashboard").map(\.urlString),
            [
                "http://localhost:3000/dashboard",
                "https://dashboard.example.com/projects"
            ]
        )
    }
}
