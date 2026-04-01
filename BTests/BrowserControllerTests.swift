import XCTest
@testable import Blink

@MainActor
final class BrowserControllerTests: XCTestCase {
    func testFocusWebViewDoesNotRepublishWhenAlreadyFocused() {
        var publishedStates: [BrowserTabState] = []
        let controller = BrowserController(
            tabId: "browser-tab",
            initialState: BrowserTabState(preferredFocus: .webView)
        ) { state in
            publishedStates.append(state)
        }

        controller.focusWebView()

        XCTAssertTrue(publishedStates.isEmpty)
    }

    func testFocusAddressBarDoesNotRepublishWhenAlreadyFocused() {
        var publishedStates: [BrowserTabState] = []
        let controller = BrowserController(
            tabId: "browser-tab",
            initialState: BrowserTabState(preferredFocus: .addressBar)
        ) { state in
            publishedStates.append(state)
        }

        controller.focusAddressBar()

        XCTAssertTrue(publishedStates.isEmpty)
    }

    func testFocusWebViewPublishesWhenFocusTargetChanges() {
        var publishedStates: [BrowserTabState] = []
        let controller = BrowserController(
            tabId: "browser-tab",
            initialState: BrowserTabState(preferredFocus: .addressBar)
        ) { state in
            publishedStates.append(state)
        }

        controller.focusWebView()

        XCTAssertEqual(publishedStates.count, 1)
        XCTAssertEqual(publishedStates.first?.preferredFocus, .webView)
    }
}
