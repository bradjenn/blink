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

    func showSurface(_ surfaceView: TerminalSurfaceView, tabId: String) {
        guard tabId != currentTabId else {
            // Same tab — just focus
            surfaceView.focus()
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

        surfaceView.focus()
    }
}

/// SwiftUI wrapper that manages terminal surfaces via a container view.
struct TerminalView: NSViewRepresentable {
    let tabId: String
    let ghosttyApp: GhosttyApp
    let surfaceManager: SurfaceManager
    let workingDirectory: String
    @Environment(\.theme) private var theme

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
                workingDirectory: workingDirectory
            )
        }
        container.showSurface(surfaceView, tabId: tabId)
    }
}
