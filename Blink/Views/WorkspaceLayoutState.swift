import SwiftUI

@MainActor @Observable
final class WorkspaceLayoutState {
    /// Stores column width as a fraction of the viewport (e.g. 0.5 = half width).
    /// Fractions adapt automatically when the viewport resizes or sidebar toggles.
    private var columnFractions: [String: [String: CGFloat]] = [:]
    private var preMaximizeFractions: [String: [String: CGFloat]] = [:]
    private var initializedWorkspaces: Set<String> = []

    func sync(workspaceId: String, columnIds: [String], defaultFraction: CGFloat) {
        let existing = columnFractions[workspaceId] ?? [:]
        var next: [String: CGFloat] = [:]

        for columnId in columnIds {
            next[columnId] = existing[columnId] ?? defaultFraction
        }

        columnFractions[workspaceId] = next

        if columnIds.isEmpty {
            initializedWorkspaces.remove(workspaceId)
        }
    }

    /// Returns the absolute pixel width for a column given the current viewport.
    func width(for columnId: String, workspaceId: String, viewportWidth: CGFloat) -> CGFloat {
        let fraction = columnFractions[workspaceId]?[columnId] ?? Layout.workspaceColumnDefaultFraction
        return viewportWidth * fraction
    }

    func setFraction(_ fraction: CGFloat, for columnId: String, workspaceId: String) {
        var fractions = columnFractions[workspaceId] ?? [:]
        fractions[columnId] = fraction
        columnFractions[workspaceId] = fractions
    }

    /// Increase to next larger preset. Caps at 1.0.
    func increasePreset(for columnId: String, workspaceId: String, viewportWidth: CGFloat) -> CGFloat {
        let presets = Layout.workspaceColumnPresets
        let current = columnFractions[workspaceId]?[columnId] ?? Layout.workspaceColumnDefaultFraction
        let tolerance: CGFloat = 0.02

        // Find next preset larger than current
        let next = presets.first { $0 > current + tolerance } ?? presets.last!
        setFraction(next, for: columnId, workspaceId: workspaceId)
        return viewportWidth * next
    }

    /// Decrease to next smaller preset. Caps at smallest preset.
    func decreasePreset(for columnId: String, workspaceId: String, viewportWidth: CGFloat) -> CGFloat {
        let presets = Layout.workspaceColumnPresets
        let current = columnFractions[workspaceId]?[columnId] ?? Layout.workspaceColumnDefaultFraction
        let tolerance: CGFloat = 0.02

        // Find next preset smaller than current
        let next = presets.last { $0 < current - tolerance } ?? presets.first!
        setFraction(next, for: columnId, workspaceId: workspaceId)
        return viewportWidth * next
    }

    /// Toggle maximize: fraction 1.0 ↔ restore previous fraction.
    func toggleMaximize(for columnId: String, workspaceId: String, viewportWidth: CGFloat) -> CGFloat {
        let currentFraction = columnFractions[workspaceId]?[columnId] ?? Layout.workspaceColumnDefaultFraction
        let tolerance: CGFloat = 0.02

        if abs(currentFraction - 1.0) < tolerance {
            // Currently maximized — restore previous fraction
            let restored = preMaximizeFractions[workspaceId]?[columnId] ?? Layout.workspaceColumnDefaultFraction
            setFraction(restored, for: columnId, workspaceId: workspaceId)
            preMaximizeFractions[workspaceId]?.removeValue(forKey: columnId)
            return viewportWidth * restored
        } else {
            // Save current fraction and maximize
            var saved = preMaximizeFractions[workspaceId] ?? [:]
            saved[columnId] = currentFraction
            preMaximizeFractions[workspaceId] = saved
            setFraction(1.0, for: columnId, workspaceId: workspaceId)
            return viewportWidth
        }
    }

    /// Maximize a column without removing other columns from the workspace.
    /// If the column is already maximized, this is a no-op.
    func maximize(for columnId: String, workspaceId: String, viewportWidth: CGFloat) -> CGFloat {
        let currentFraction = columnFractions[workspaceId]?[columnId] ?? Layout.workspaceColumnDefaultFraction
        let tolerance: CGFloat = 0.02

        guard abs(currentFraction - 1.0) >= tolerance else {
            return viewportWidth
        }

        var saved = preMaximizeFractions[workspaceId] ?? [:]
        saved[columnId] = currentFraction
        preMaximizeFractions[workspaceId] = saved
        setFraction(1.0, for: columnId, workspaceId: workspaceId)
        return viewportWidth
    }

    func isInitialized(workspaceId: String) -> Bool {
        initializedWorkspaces.contains(workspaceId)
    }

    func markInitialized(workspaceId: String) {
        initializedWorkspaces.insert(workspaceId)
    }
}
