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

    func showSurface(_ surfaceView: TerminalSurfaceView, tabId: String, shouldFocus: Bool) {
        guard tabId != currentTabId else {
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

    func makeNSView(context: Context) -> TerminalContainerView {
        TerminalContainerView()
    }

    func updateNSView(_ container: TerminalContainerView, context: Context) {
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
        }

        surfaceView.onSwipeNavigation = { [store] direction in
            switch direction {
            case .previous:
                store.selectPreviousTab()
            case .next:
                store.selectNextTab()
            }
        }
        surfaceView.onInteraction = { [store, tabId] in
            if store.activeTabId != tabId {
                store.setActiveTab(tabId)
            }
        }

        container.showSurface(surfaceView, tabId: tabId, shouldFocus: isFocused)
    }
}
