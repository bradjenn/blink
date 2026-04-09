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
            workspaceId: "workspace-1",
            profileId: "personal",
            initialState: .blank
        ) { _ in }

        let secondController = manager.controller(
            for: "browser-tab",
            workspaceId: "workspace-1",
            profileId: "personal",
            initialState: BrowserTabState(urlString: "https://example.com")
        ) { _ in }

        XCTAssertTrue((firstController as AnyObject) === (secondController as AnyObject))
        XCTAssertNil(secondController.session.state.urlString)
    }

    func testChangingProfileRecreatesLiveController() {
        let manager = BrowserManager(userDefaults: testDefaults)
        let firstController = manager.controller(
            for: "browser-tab",
            workspaceId: "workspace-1",
            profileId: "personal",
            initialState: .blank
        ) { _ in }

        let secondController = manager.controller(
            for: "browser-tab",
            workspaceId: "workspace-1",
            profileId: "client-a",
            initialState: .blank
        ) { _ in }

        XCTAssertFalse((firstController as AnyObject) === (secondController as AnyObject))
    }

    func testRecentDownloadsAreScopedByWorkspaceAndSortedNewestFirst() {
        let manager = BrowserManager(userDefaults: testDefaults)
        let older = BrowserDownloadItem(
            id: "workspace-1:1",
            browserTabId: "tab-1",
            workspaceId: "workspace-1",
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
            id: "workspace-1:2",
            browserTabId: "tab-2",
            workspaceId: "workspace-1",
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
        let otherWorkspace = BrowserDownloadItem(
            id: "workspace-2:1",
            browserTabId: "tab-3",
            workspaceId: "workspace-2",
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

        manager.downloads = [older, newer, otherWorkspace]

        XCTAssertEqual(manager.recentDownloads(for: "workspace-1").map(\.id), [newer.id, older.id])
    }

    func testDownloadsPersistAcrossManagerRelaunch() {
        let persisted = BrowserDownloadItem(
            id: "workspace-1:1",
            browserTabId: "tab-1",
            workspaceId: "workspace-1",
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

    func testDownloadsLoadLegacyProjectIdField() throws {
        let legacyDownloadData = try JSONSerialization.data(
            withJSONObject: [[
                "id": "project-1:1",
                "browserTabId": "tab-1",
                "projectId": "project-1",
                "sourceURLString": "https://example.com/archive.zip",
                "suggestedFileName": "archive.zip",
                "destinationPath": "/Users/bradley/Downloads/archive.zip",
                "receivedBytes": 20,
                "totalBytes": 20,
                "percentComplete": 100,
                "currentSpeed": 0,
                "isInProgress": false,
                "isComplete": true,
                "isCanceled": false,
                "isInterrupted": false,
                "updatedAt": 20,
            ]],
            options: [.sortedKeys]
        )
        testDefaults.set(legacyDownloadData, forKey: "blink.browserDownloads")

        let manager = BrowserManager(userDefaults: testDefaults)

        XCTAssertEqual(manager.downloads.count, 1)
        XCTAssertEqual(manager.downloads.first?.workspaceId, "project-1")
    }

    func testClearDownloadsOnlyRemovesActiveWorkspaceHistory() {
        let workspaceOne = BrowserDownloadItem(
            id: "workspace-1:1",
            browserTabId: "tab-1",
            workspaceId: "workspace-1",
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
        let workspaceTwo = BrowserDownloadItem(
            id: "workspace-2:1",
            browserTabId: "tab-2",
            workspaceId: "workspace-2",
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
        manager.downloads = [workspaceOne, workspaceTwo]

        manager.clearDownloads(for: "workspace-1")

        XCTAssertEqual(manager.downloads, [workspaceTwo])
        let reloadedManager = BrowserManager(userDefaults: testDefaults)
        XCTAssertEqual(reloadedManager.downloads, [workspaceTwo])
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
                urlString: "https://dashboard.example.com/workspaces",
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
                "https://dashboard.example.com/workspaces"
            ]
        )
    }
}
