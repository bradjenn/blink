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

    let paneTabId: String
    let browserTabId: String
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
                if store.activeTabId != paneTabId {
                    store.setActiveTab(paneTabId)
                }
                store.selectBrowserTab(browserTabId, in: paneTabId)
                store.setBrowserFocusTarget(.webView, for: browserTabId, in: paneTabId)
            }
        }
        controller.onOpenNewTabRequest = { url in
            DispatchQueue.main.async {
                store.openBrowserTabInPane(paneTabId, url: url.absoluteString)
            }
        }

        container.showWebView(controller.hostView, tabId: browserTabId)
    }
}
