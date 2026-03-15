import SwiftUI
import GhosttyKit

@Observable
final class SurfaceManager {
    /// Tab ID → live terminal view
    var surfaces: [String: TerminalSurfaceView] = [:]

    /// Create a new terminal surface for a tab.
    func createSurface(tabId: String, app: GhosttyApp, workingDirectory: String, placeholderBg: String = "#000000") -> TerminalSurfaceView {
        let view = TerminalSurfaceView(app: app, tabId: tabId, workingDirectory: workingDirectory, placeholderBg: placeholderBg)
        surfaces[tabId] = view
        return view
    }

    /// Destroy a terminal surface — kills the shell process immediately.
    func destroySurface(tabId: String) {
        if let view = surfaces.removeValue(forKey: tabId) {
            view.teardown()
        }
    }

    /// Look up an existing surface by tab ID.
    func surface(for tabId: String) -> TerminalSurfaceView? {
        surfaces[tabId]
    }

    /// Destroy all surfaces for given tab IDs.
    func destroySurfaces(tabIds: [String]) {
        for tabId in tabIds {
            destroySurface(tabId: tabId)
        }
    }
}
