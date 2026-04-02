import AppKit
import SwiftUI

final class BrowserHostingView: NSView {
    private var currentTabId: String?
    private weak var currentWebView: NSView?

    override var isOpaque: Bool { false }

    func showWebView(_ webView: NSView, tabId: String) {
        if currentTabId == tabId, currentWebView === webView {
            return
        }

        currentWebView?.removeFromSuperview()

        webView.frame = bounds
        webView.autoresizingMask = [.width, .height]
        addSubview(webView)

        currentTabId = tabId
        currentWebView = webView
    }
}

final class BrowserSidebarHoverTrackingView: NSView {
    var onHoverChange: ((Bool) -> Void)?
    var hotspotWidth: CGFloat = 0
    var leadingEdgeInset: CGFloat = 0

    private var trackingArea: NSTrackingArea?
    private var eventMonitor: Any?
    private var isHovering = false

    override var isOpaque: Bool { false }

    deinit {
        removeEventMonitor()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window != nil {
            installEventMonitorIfNeeded()
            evaluateHoverState()
        } else {
            removeEventMonitor()
            setHovering(false)
        }
    }

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

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        evaluateHoverState(for: event)
    }

    override func mouseEntered(with event: NSEvent) {
        evaluateHoverState(for: event)
    }

    override func mouseExited(with event: NSEvent) {
        evaluateHoverState(for: event)
    }

    private func installEventMonitorIfNeeded() {
        guard eventMonitor == nil else { return }

        window?.acceptsMouseMovedEvents = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.evaluateHoverState(for: event)
            return event
        }
    }

    private func removeEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    private func evaluateHoverState(for event: NSEvent? = nil) {
        guard let window else {
            setHovering(false)
            return
        }

        let location = event?.window === window
            ? event?.locationInWindow
            : window.mouseLocationOutsideOfEventStream
        guard let location else {
            setHovering(false)
            return
        }

        let frameInWindow = convert(bounds, to: nil)
        let triggerMinX = frameInWindow.minX - leadingEdgeInset
        let triggerMaxX = frameInWindow.minX + hotspotWidth
        let isWithinVerticalBounds = location.y >= frameInWindow.minY && location.y <= frameInWindow.maxY
        let isWithinTriggerBand = location.x >= triggerMinX && location.x <= triggerMaxX

        setHovering(isWithinVerticalBounds && isWithinTriggerBand)
    }

    private func setHovering(_ hovering: Bool) {
        guard isHovering != hovering else { return }
        isHovering = hovering
        onHoverChange?(hovering)
    }
}

struct BrowserSidebarHoverRegion: NSViewRepresentable {
    let onHoverChange: (Bool) -> Void
    let hotspotWidth: CGFloat
    let leadingEdgeInset: CGFloat

    func makeNSView(context: Context) -> BrowserSidebarHoverTrackingView {
        let view = BrowserSidebarHoverTrackingView()
        view.onHoverChange = onHoverChange
        view.hotspotWidth = hotspotWidth
        view.leadingEdgeInset = leadingEdgeInset
        return view
    }

    func updateNSView(_ nsView: BrowserSidebarHoverTrackingView, context: Context) {
        let didChangeGeometry = nsView.hotspotWidth != hotspotWidth || nsView.leadingEdgeInset != leadingEdgeInset
        nsView.onHoverChange = onHoverChange
        nsView.hotspotWidth = hotspotWidth
        nsView.leadingEdgeInset = leadingEdgeInset
        if didChangeGeometry {
            nsView.needsLayout = true
        }
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
