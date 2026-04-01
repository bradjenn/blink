import Foundation
import Observation

@MainActor
@Observable
final class BrowserManager {
    let engine: BrowserEngine
    private var controllers: [String: any BrowserHostController] = [:]

    init() {
        self.engine = Self.resolveEngine()
    }

    func controller(
        for tabId: String,
        projectId: String,
        initialState: BrowserTabState,
        onStateChange: @escaping (BrowserTabState) -> Void
    ) -> any BrowserHostController {
        if let existing = controllers[tabId] {
            return existing
        }

        let controller = makeController(
            tabId: tabId,
            projectId: projectId,
            initialState: initialState,
            onStateChange: onStateChange
        )
        controllers[tabId] = controller
        return controller
    }

    private func makeController(
        tabId: String,
        projectId: String,
        initialState: BrowserTabState,
        onStateChange: @escaping (BrowserTabState) -> Void
    ) -> any BrowserHostController {
        switch engine {
        case .webKit:
            return BrowserController(
                tabId: tabId,
                initialState: initialState,
                onStateChange: onStateChange
            )
        case .chromium:
            return ChromiumBrowserController(
                tabId: tabId,
                projectId: projectId,
                initialState: initialState,
                onStateChange: onStateChange
            )
        }
    }

    private static func resolveEngine() -> BrowserEngine {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return .webKit
        }

        guard BrowserEngineSelection.active == .chromium,
              BlinkChromiumRuntime.canStartInCurrentBundle() else {
            return .webKit
        }

        return .chromium
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
