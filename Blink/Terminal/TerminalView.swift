import SwiftUI
import GhosttyKit

/// SwiftUI wrapper around TerminalSurfaceView.
struct TerminalView: NSViewRepresentable {
    let app: GhosttyApp

    func makeNSView(context: Context) -> TerminalSurfaceView {
        TerminalSurfaceView(app: app)
    }

    func updateNSView(_ nsView: TerminalSurfaceView, context: Context) {
        // No dynamic updates needed for PoC
    }
}
