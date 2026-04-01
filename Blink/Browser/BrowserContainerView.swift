import AppKit
import SwiftUI

final class BrowserHostingView: NSView {
    private var currentTabId: String?
    private weak var currentWebView: NSView?

    override var isOpaque: Bool { false }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        syncCurrentWebViewFrame()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncCurrentWebViewFrame()
    }

    override func layout() {
        super.layout()
        syncCurrentWebViewFrame()
    }

    func showWebView(_ webView: NSView, tabId: String) {
        if currentTabId == tabId, currentWebView === webView {
            if webView.frame != bounds {
                webView.frame = bounds
            }
            return
        }

        currentWebView?.removeFromSuperview()

        webView.frame = bounds
        webView.autoresizingMask = [.width, .height]
        addSubview(webView)

        currentTabId = tabId
        currentWebView = webView
    }

    private func syncCurrentWebViewFrame() {
        guard let currentWebView, currentWebView.frame != bounds else { return }
        currentWebView.frame = bounds
    }
}

struct BrowserContainerView: NSViewRepresentable {
    @Environment(AppStore.self) private var store

    let tabId: String
    let projectId: String
    let controller: any BrowserHostController

    func makeNSView(context: Context) -> BrowserHostingView {
        BrowserHostingView()
    }

    func updateNSView(_ container: BrowserHostingView, context: Context) {
        controller.onInteraction = {
            DispatchQueue.main.async {
                if store.shouldClearSidebarFocusForTerminalInteraction() {
                    store.sidebarFocused = false
                }
                if store.activeTabId != tabId {
                    store.setActiveTab(tabId)
                }
                store.setBrowserFocusTarget(.webView, for: tabId)
            }
        }
        controller.onOpenNewTabRequest = { url in
            DispatchQueue.main.async {
                store.openBrowserTab(projectId: projectId, url: url.absoluteString, maximizeColumn: false)
            }
        }

        container.showWebView(controller.hostView, tabId: tabId)
    }
}
