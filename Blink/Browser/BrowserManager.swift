import Foundation
import Observation

@MainActor
@Observable
final class BrowserManager {
    let engine: BrowserEngine = BrowserEngineSelection.active
    private var controllers: [String: BrowserController] = [:]

    func controller(
        for tabId: String,
        initialState: BrowserTabState,
        onStateChange: @escaping (BrowserTabState) -> Void
    ) -> BrowserController {
        if let existing = controllers[tabId] {
            existing.update(initialState: initialState, onStateChange: onStateChange)
            return existing
        }

        let controller = makeController(
            tabId: tabId,
            initialState: initialState,
            onStateChange: onStateChange
        )
        controllers[tabId] = controller
        return controller
    }

    private func makeController(
        tabId: String,
        initialState: BrowserTabState,
        onStateChange: @escaping (BrowserTabState) -> Void
    ) -> BrowserController {
        switch engine {
        case .webKit:
            return BrowserController(
                tabId: tabId,
                initialState: initialState,
                onStateChange: onStateChange
            )
        case .chromium:
            assertionFailure("Chromium browser engine is not integrated yet. Falling back to WebKit.")
            return BrowserController(
                tabId: tabId,
                initialState: initialState,
                onStateChange: onStateChange
            )
        }
    }

    func destroyController(tabId: String) {
        controllers.removeValue(forKey: tabId)
    }

    func destroyControllers(tabIds: [String]) {
        for tabId in tabIds {
            destroyController(tabId: tabId)
        }
    }

    func focusWebView(tabId: String) {
        controllers[tabId]?.focusWebView()
    }

    func focusAddressBar(tabId: String) {
        controllers[tabId]?.focusAddressBar()
    }

    func goBack(tabId: String) {
        controllers[tabId]?.goBack()
    }

    func goForward(tabId: String) {
        controllers[tabId]?.goForward()
    }

    func reload(tabId: String) {
        controllers[tabId]?.reload()
    }

    func openInDefaultBrowser(tabId: String) {
        controllers[tabId]?.openInDefaultBrowser()
    }
}
