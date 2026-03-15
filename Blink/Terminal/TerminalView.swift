import SwiftUI
import GhosttyKit

/// SwiftUI wrapper that looks up or creates a terminal surface for a tab.
struct TerminalView: NSViewRepresentable {
    let tabId: String
    let ghosttyApp: GhosttyApp
    let surfaceManager: SurfaceManager
    let workingDirectory: String

    func makeNSView(context: Context) -> TerminalSurfaceView {
        if let existing = surfaceManager.surface(for: tabId) {
            return existing
        }
        return surfaceManager.createSurface(
            tabId: tabId,
            app: ghosttyApp,
            workingDirectory: workingDirectory
        )
    }

    func updateNSView(_ nsView: TerminalSurfaceView, context: Context) {
        nsView.focus()
    }
}
