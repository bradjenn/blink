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

final class BrowserSidebarHoverTrackingView: NSView {
    var onHoverChange: ((Bool) -> Void)?

    private var trackingArea: NSTrackingArea?

    override var isOpaque: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange?(false)
    }
}

struct BrowserSidebarHoverRegion: NSViewRepresentable {
    let onHoverChange: (Bool) -> Void

    func makeNSView(context: Context) -> BrowserSidebarHoverTrackingView {
        let view = BrowserSidebarHoverTrackingView()
        view.onHoverChange = onHoverChange
        return view
    }

    func updateNSView(_ nsView: BrowserSidebarHoverTrackingView, context: Context) {
        nsView.onHoverChange = onHoverChange
    }
}

struct BrowserContainerView: NSViewRepresentable {
    final class Coordinator {
        weak var controller: (any BrowserHostController)?
    }

    @Environment(AppStore.self) private var store

    let paneTabId: String
    let browserTabId: String
    let controller: any BrowserHostController

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> BrowserHostingView {
        BrowserHostingView()
    }

    func updateNSView(_ container: BrowserHostingView, context: Context) {
        if let previousController = context.coordinator.controller,
           previousController.tabId != controller.tabId {
            previousController.onInteraction = nil
            previousController.onOpenNewTabRequest = nil
        }
        context.coordinator.controller = controller

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

    static func dismantleNSView(_ container: BrowserHostingView, coordinator: Coordinator) {
        coordinator.controller?.onInteraction = nil
        coordinator.controller?.onOpenNewTabRequest = nil
    }
}
