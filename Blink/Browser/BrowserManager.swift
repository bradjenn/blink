import Foundation
import Observation

@MainActor
@Observable
final class BrowserManager {
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

        let controller = BrowserController(
            tabId: tabId,
            initialState: initialState,
            onStateChange: onStateChange
        )
        controllers[tabId] = controller
        return controller
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
