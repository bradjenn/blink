import SwiftUI
import GhosttyKit

@MainActor @Observable
final class SurfaceManager {
    /// Tab ID → live terminal view
    var surfaces: [String: TerminalSurfaceView] = [:]

    /// Called when a shell process exits.
    var onProcessExit: ((String) -> Void)?
    /// Called when a terminal surface is ready to accept input.
    var onSurfaceReady: ((String) -> Void)?

    /// Create a new terminal surface for a tab.
    func createSurface(
        tabId: String,
        paneId: String,
        projectId: String,
        projectName: String,
        hookScriptDirectoryPath: String?,
        hookShellIntegrationDirectoryPath: String?,
        hookEventDirectoryPath: String?,
        app: GhosttyApp,
        workingDirectory: String,
        command: String? = nil
    ) -> TerminalSurfaceView {
        let view = TerminalSurfaceView(
            app: app,
            tabId: tabId,
            paneId: paneId,
            projectId: projectId,
            projectName: projectName,
            hookScriptDirectoryPath: hookScriptDirectoryPath,
            hookShellIntegrationDirectoryPath: hookShellIntegrationDirectoryPath,
            hookEventDirectoryPath: hookEventDirectoryPath,
            workingDirectory: workingDirectory,
            command: command
        )
        view.onClose = { [weak self] tabId in
            self?.onProcessExit?(tabId)
        }
        view.onReady = { [weak self] tabId in
            self?.onSurfaceReady?(tabId)
        }
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
