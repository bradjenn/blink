import AppKit
import SwiftUI

struct BrowserSwipeNavigationEvent {
    let scrollingDeltaX: CGFloat
    let scrollingDeltaY: CGFloat
    let hasPreciseScrollingDeltas: Bool
    let phase: NSEvent.Phase
    let momentumPhase: NSEvent.Phase
    let timestamp: TimeInterval

    init(
        scrollingDeltaX: CGFloat,
        scrollingDeltaY: CGFloat,
        hasPreciseScrollingDeltas: Bool,
        phase: NSEvent.Phase,
        momentumPhase: NSEvent.Phase,
        timestamp: TimeInterval
    ) {
        self.scrollingDeltaX = scrollingDeltaX
        self.scrollingDeltaY = scrollingDeltaY
        self.hasPreciseScrollingDeltas = hasPreciseScrollingDeltas
        self.phase = phase
        self.momentumPhase = momentumPhase
        self.timestamp = timestamp
    }

    init(event: NSEvent) {
        self.init(
            scrollingDeltaX: event.scrollingDeltaX,
            scrollingDeltaY: event.scrollingDeltaY,
            hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas,
            phase: event.phase,
            momentumPhase: event.momentumPhase,
            timestamp: event.timestamp
        )
    }
}

enum BrowserSwipeNavigationOutcome: Equatable {
    case ignored
    case consumed
    case navigate(SwipeNavigationDirection)
}

struct BrowserSwipeNavigationFeedback: Equatable {
    let direction: SwipeNavigationDirection
    let progress: CGFloat
    let isArmed: Bool
    let isCommitted: Bool
}

struct BrowserSwipeNavigationResult: Equatable {
    let outcome: BrowserSwipeNavigationOutcome
    let feedback: BrowserSwipeNavigationFeedback?
}

struct BrowserSwipeNavigationTracker {
    private static let threshold: CGFloat = 72
    private static let horizontalBias: CGFloat = 1.5

    private var signedPullDistance: CGFloat = 0
    private var isGestureActive = false
    private var isArmed = false

    mutating func handle(
        _ event: BrowserSwipeNavigationEvent,
        canNavigate: (SwipeNavigationDirection) -> Bool
    ) -> BrowserSwipeNavigationResult {
        if event.phase.contains(.began) {
            reset()
        }

        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            let activeDirection = direction(for: signedPullDistance)
            let shouldNavigate = isArmed && activeDirection != nil
            let wasActiveGesture = isGestureActive || activeDirection != nil || signedPullDistance != 0
            reset()

            guard let activeDirection else {
                return BrowserSwipeNavigationResult(
                    outcome: wasActiveGesture ? .consumed : .ignored,
                    feedback: nil
                )
            }

            if shouldNavigate {
                return BrowserSwipeNavigationResult(
                    outcome: .navigate(activeDirection),
                    feedback: BrowserSwipeNavigationFeedback(
                        direction: activeDirection,
                        progress: 1,
                        isArmed: true,
                        isCommitted: true
                    )
                )
            }

            return BrowserSwipeNavigationResult(
                outcome: .consumed,
                feedback: nil
            )
        }

        let isEligibleGestureStream = event.hasPreciseScrollingDeltas && event.momentumPhase.isEmpty
        guard isEligibleGestureStream else {
            reset()
            return BrowserSwipeNavigationResult(outcome: .ignored, feedback: nil)
        }

        let isHorizontalSwipe = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * Self.horizontalBias
        if !isGestureActive && !isHorizontalSwipe {
            return BrowserSwipeNavigationResult(outcome: .ignored, feedback: nil)
        }

        if !isGestureActive {
            guard let initialDirection = direction(for: event.scrollingDeltaX), canNavigate(initialDirection) else {
                return BrowserSwipeNavigationResult(outcome: .ignored, feedback: nil)
            }
            isGestureActive = true
        }

        var proposedPullDistance = signedPullDistance + event.scrollingDeltaX
        if let proposedDirection = direction(for: proposedPullDistance), !canNavigate(proposedDirection) {
            if let currentDirection = direction(for: signedPullDistance), currentDirection != proposedDirection {
                proposedPullDistance = 0
            } else {
                reset()
                return BrowserSwipeNavigationResult(outcome: .ignored, feedback: nil)
            }
        }

        signedPullDistance = proposedPullDistance

        guard let swipeDirection = direction(for: signedPullDistance) else {
            isArmed = false
            return BrowserSwipeNavigationResult(outcome: .consumed, feedback: nil)
        }

        isArmed = abs(signedPullDistance) >= Self.threshold
        let progress = min(abs(signedPullDistance) / Self.threshold, 1)
        let feedback = BrowserSwipeNavigationFeedback(
            direction: swipeDirection,
            progress: progress,
            isArmed: isArmed,
            isCommitted: false
        )

        return BrowserSwipeNavigationResult(outcome: .consumed, feedback: feedback)
    }

    private mutating func reset() {
        signedPullDistance = 0
        isGestureActive = false
        isArmed = false
    }

    private func direction(for pullDistance: CGFloat) -> SwipeNavigationDirection? {
        if pullDistance > 0 {
            return .previous
        }
        if pullDistance < 0 {
            return .next
        }
        return nil
    }
}

final class BrowserHostingView: NSView {
    private var currentTabId: String?
    private weak var currentWebView: NSView?
    private var eventMonitor: Any?
    private var swipeNavigationTracker = BrowserSwipeNavigationTracker()

    var swipeNavigationEnabled = false
    var canNavigateBack = false
    var canNavigateForward = false
    var onSwipeNavigation: ((SwipeNavigationDirection) -> Void)?
    var onSwipeNavigationFeedback: ((BrowserSwipeNavigationFeedback?) -> Void)?

    override var isOpaque: Bool { false }

    deinit {
        removeEventMonitor()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window != nil {
            installEventMonitorIfNeeded()
        } else {
            removeEventMonitor()
        }
    }

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

    private func installEventMonitorIfNeeded() {
        guard eventMonitor == nil else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            guard let self else { return event }
            return self.handleLocalScrollEvent(event)
        }
    }

    private func removeEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    private func handleLocalScrollEvent(_ event: NSEvent) -> NSEvent? {
        guard swipeNavigationEnabled,
              currentWebView != nil,
              shouldHandleScrollEvent(event) else {
            return event
        }

        let outcome = swipeNavigationTracker.handle(BrowserSwipeNavigationEvent(event: event)) { [weak self] direction in
            guard let self else { return false }
            switch direction {
            case .previous:
                return canNavigateBack
            case .next:
                return canNavigateForward
            }
        }
        onSwipeNavigationFeedback?(outcome.feedback)

        switch outcome.outcome {
        case .ignored:
            return event
        case .consumed:
            return nil
        case .navigate(let direction):
            onSwipeNavigation?(direction)
            return nil
        }
    }

    private func shouldHandleScrollEvent(_ event: NSEvent) -> Bool {
        guard let window,
              event.window === window else {
            return false
        }

        let frameInWindow = convert(bounds, to: nil)
        return frameInWindow.contains(event.locationInWindow)
    }
}

final class BrowserSidebarHoverTrackingView: NSView {
    var onHoverChange: ((Bool) -> Void)?
    var isEnabled: Bool = true {
        didSet {
            guard isEnabled != oldValue else { return }
            if isEnabled {
                installEventMonitorIfNeeded()
                evaluateHoverState()
            } else {
                removeEventMonitor()
                setHovering(false)
            }
        }
    }
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

        if window != nil, isEnabled {
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
        guard isEnabled, eventMonitor == nil else { return }

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
        guard isEnabled else {
            setHovering(false)
            return
        }
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
    let isEnabled: Bool
    let hotspotWidth: CGFloat
    let leadingEdgeInset: CGFloat

    func makeNSView(context: Context) -> BrowserSidebarHoverTrackingView {
        let view = BrowserSidebarHoverTrackingView()
        view.onHoverChange = onHoverChange
        view.isEnabled = isEnabled
        view.hotspotWidth = hotspotWidth
        view.leadingEdgeInset = leadingEdgeInset
        return view
    }

    func updateNSView(_ nsView: BrowserSidebarHoverTrackingView, context: Context) {
        let didChangeGeometry = nsView.hotspotWidth != hotspotWidth || nsView.leadingEdgeInset != leadingEdgeInset
        nsView.onHoverChange = onHoverChange
        nsView.isEnabled = isEnabled
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
    var onSwipeNavigationFeedback: ((BrowserSwipeNavigationFeedback?) -> Void)?

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

        container.swipeNavigationEnabled = controller is ChromiumBrowserController
        container.canNavigateBack = controller.session.state.canGoBack
        container.canNavigateForward = controller.session.state.canGoForward
        container.onSwipeNavigationFeedback = onSwipeNavigationFeedback
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
        container.onSwipeNavigation = { direction in
            DispatchQueue.main.async {
                if store.shouldClearSidebarFocusForTerminalInteraction() {
                    store.sidebarFocused = false
                }
                if store.activeTabId != paneTabId {
                    store.setActiveTab(paneTabId)
                }
                store.selectBrowserTab(browserTabId, in: paneTabId)
                store.setBrowserFocusTarget(.webView, for: browserTabId, in: paneTabId)

                switch direction {
                case .previous:
                    controller.goBack()
                case .next:
                    controller.goForward()
                }
            }
        }

        container.showWebView(controller.hostView, tabId: browserTabId)
    }

    static func dismantleNSView(_ container: BrowserHostingView, coordinator: Coordinator) {
        coordinator.controller?.onInteraction = nil
        coordinator.controller?.onOpenNewTabRequest = nil
        container.onSwipeNavigation = nil
        container.onSwipeNavigationFeedback = nil
    }
}
