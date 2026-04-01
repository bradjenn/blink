import XCTest
@testable import Blink

@MainActor
final class BrowserManagerTests: XCTestCase {
    func testExistingControllerRemainsSourceOfTruthForLiveBrowserState() {
        let manager = BrowserManager()
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
}
