import SwiftUI
import AppKit
import GhosttyKit

/// Container NSView that holds a TerminalSurfaceView as a subview.
/// Swapping the child avoids destroying/recreating the NSViewRepresentable.
class TerminalContainerView: NSView {
    private var currentTabId: String?
    private weak var currentSurface: TerminalSurfaceView?

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }

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
            surfaceView.frame = bounds
            currentSurface = surfaceView
            if shouldFocus {
                surfaceView.focus()
            }
            return
        }

        // Remove old surface from this container (doesn't destroy it —
        // SurfaceManager still holds a reference)
        currentSurface?.removeFromSuperview()

        // Add new surface as subview
        surfaceView.frame = bounds
        surfaceView.autoresizingMask = [.width, .height]
        addSubview(surfaceView)

        currentTabId = tabId
        currentSurface = surfaceView

        if shouldFocus {
            surfaceView.focus()
        }
    }

    private func syncCurrentSurfaceFrame() {
        // SwiftUI and AppKit can reach subview geometry through slightly
        // different paths during animated pane resizing. Keep forcing the
        // hosted terminal to match the container bounds so Ghostty always
        // receives a fresh size update.
        currentSurface?.frame = bounds
    }
}

/// SwiftUI wrapper that manages terminal surfaces via a container view.
struct TerminalView: NSViewRepresentable {
    @Environment(AppStore.self) private var store

    let tabId: String
    let ghosttyApp: GhosttyApp
    let surfaceManager: SurfaceManager
    let workingDirectory: String
    let isFocused: Bool
    var command: String? = nil

    final class Coordinator {
        var store: AppStore?
        var tabId: String = ""
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> TerminalContainerView {
        TerminalContainerView()
    }

    func updateNSView(_ container: TerminalContainerView, context: Context) {
        let coordinator = context.coordinator
        coordinator.store = store
        coordinator.tabId = tabId

        let surfaceView: TerminalSurfaceView
        if let existing = surfaceManager.surface(for: tabId) {
            surfaceView = existing
        } else {
            surfaceView = surfaceManager.createSurface(
                tabId: tabId,
                app: ghosttyApp,
                workingDirectory: workingDirectory,
                command: command
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

        container.showSurface(surfaceView, tabId: tabId, shouldFocus: isFocused)
    }
}
