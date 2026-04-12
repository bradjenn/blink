import SwiftUI
import AppKit
import GhosttyKit

/// Container NSView that holds a TerminalSurfaceView as a subview.
/// Swapping the child avoids destroying/recreating the NSViewRepresentable.
class TerminalContainerView: NSView {
    private var currentTabId: String?
    private weak var currentSurface: TerminalSurfaceView?
    var allowsPointerPassthrough = false

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if allowsPointerPassthrough {
            return nil
        }
        return super.hitTest(point)
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        syncCurrentSurfaceFrame()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncCurrentSurfaceFrame()
    }

    override func layout() {
        super.layout()
        syncCurrentSurfaceFrame()
    }

    func showSurface(_ surfaceView: TerminalSurfaceView, tabId: String, shouldFocus: Bool) {
        if tabId == currentTabId, currentSurface === surfaceView {
            surfaceView.setVisibleInUI(true)
            if surfaceView.frame != bounds {
                surfaceView.frame = bounds
            }
            currentSurface = surfaceView
            if shouldFocus {
                surfaceView.focus()
            }
            return
        }

        // Remove old surface from this container (doesn't destroy it —
        // SurfaceManager still holds a reference)
        currentSurface?.setVisibleInUI(false)
        currentSurface?.removeFromSuperview()

        // Add new surface as subview
        surfaceView.frame = bounds
        surfaceView.autoresizingMask = [.width, .height]
        addSubview(surfaceView)
        surfaceView.setVisibleInUI(true)

        currentTabId = tabId
        currentSurface = surfaceView

        if shouldFocus {
            surfaceView.focus()
        }
    }

    private func syncCurrentSurfaceFrame() {
        guard let currentSurface, currentSurface.frame != bounds else { return }
        // SwiftUI and AppKit can reach subview geometry through slightly
        // different paths during animated pane resizing. Keep the hosted
        // terminal aligned with the container bounds, but avoid writing the
        // same frame back repeatedly during layout churn.
        currentSurface.frame = bounds
    }
}

/// SwiftUI wrapper that manages terminal surfaces via a container view.
struct TerminalView: NSViewRepresentable {
    @Environment(AppStore.self) private var store

    let tabId: String
    let paneId: String
    let ghosttyApp: GhosttyApp
    let surfaceManager: SurfaceManager
    let workspaceId: String
    let workspaceName: String
    let workingDirectory: String
    let isFocused: Bool
    var command: String? = nil
    var autoFocusOnReady: Bool = true
    var shellPathOverride: String? = nil
    var usesLoginShell: Bool = true
    var shellIntegrationEnabled: Bool = true
    var allowsPointerPassthrough: Bool = false

    final class Coordinator {
        var store: AppStore?
        var tabId: String = ""
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> TerminalContainerView {
        TerminalContainerView()
    }

    func updateNSView(_ container: TerminalContainerView, context: Context) {
        container.allowsPointerPassthrough = allowsPointerPassthrough

        let coordinator = context.coordinator
        coordinator.store = store
        coordinator.tabId = tabId

        let surfaceView: TerminalSurfaceView
        if let existing = surfaceManager.surface(for: tabId) {
            surfaceView = existing
        } else {
            surfaceView = surfaceManager.createSurface(
                tabId: tabId,
                paneId: paneId,
                workspaceId: workspaceId,
                workspaceName: workspaceName,
                hookScriptDirectoryPath: store.claudeHookScriptPath,
                hookShellIntegrationDirectoryPath: store.claudeHookShellIntegrationPath,
                hookEventDirectoryPath: store.claudeHookEventDirectoryPath,
                app: ghosttyApp,
                workingDirectory: workingDirectory,
                command: command,
                autoFocusOnReady: autoFocusOnReady,
                shellPathOverride: shellPathOverride,
                usesLoginShell: usesLoginShell,
                shellIntegrationEnabled: shellIntegrationEnabled
            )

            // Set closures once per surface, reading current state via coordinator
            surfaceView.onSwipeNavigation = { [weak coordinator] direction in
                guard let store = coordinator?.store else { return }
                switch direction {
                case .previous:
                    store.selectPreviousTab()
                case .next:
                    store.selectNextTab()
                }
            }
            surfaceView.onInteraction = { [weak coordinator] in
                guard let coordinator, let store = coordinator.store else { return }
                if store.shouldClearSidebarFocusForTerminalInteraction() {
                    store.sidebarFocused = false
                }
                if store.activeTabId != coordinator.tabId {
                    store.setActiveTab(coordinator.tabId)
                }
            }
        }

        surfaceView.onSubmittedLine = { [weak coordinator] line in
            guard let coordinator, let store = coordinator.store else { return }
            store.handleTerminalLineSubmission(line, for: coordinator.tabId)
        }

        container.showSurface(surfaceView, tabId: tabId, shouldFocus: isFocused)
    }
}
