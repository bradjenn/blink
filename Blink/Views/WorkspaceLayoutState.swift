import SwiftUI

@MainActor @Observable
final class WorkspaceLayoutState {
    /// Stores column width as a fraction of the viewport (e.g. 0.5 = half width).
    /// Fractions adapt automatically when the viewport resizes or sidebar toggles.
    private var columnFractions: [String: [String: CGFloat]] = [:]
    private var preMaximizeFractions: [String: [String: CGFloat]] = [:]
    private var initializedProjects: Set<String> = []

    func sync(projectId: String, columnIds: [String], defaultFraction: CGFloat) {
        let existing = columnFractions[projectId] ?? [:]
        var next: [String: CGFloat] = [:]

        for columnId in columnIds {
            next[columnId] = existing[columnId] ?? defaultFraction
        }

        columnFractions[projectId] = next

        if columnIds.isEmpty {
            initializedProjects.remove(projectId)
        }
    }

    /// Returns the absolute pixel width for a column given the current viewport.
    func width(for columnId: String, projectId: String, viewportWidth: CGFloat) -> CGFloat {
        let fraction = columnFractions[projectId]?[columnId] ?? Layout.workspaceColumnDefaultFraction
        return viewportWidth * fraction
    }

    func setFraction(_ fraction: CGFloat, for columnId: String, projectId: String) {
        var fractions = columnFractions[projectId] ?? [:]
        fractions[columnId] = fraction
        columnFractions[projectId] = fractions
    }

    /// Increase to next larger preset. Caps at 1.0.
    func increasePreset(for columnId: String, projectId: String, viewportWidth: CGFloat) -> CGFloat {
        let presets = Layout.workspaceColumnPresets
        let current = columnFractions[projectId]?[columnId] ?? Layout.workspaceColumnDefaultFraction
        let tolerance: CGFloat = 0.02

        // Find next preset larger than current
        let next = presets.first { $0 > current + tolerance } ?? presets.last!
        setFraction(next, for: columnId, projectId: projectId)
        return viewportWidth * next
    }

    /// Decrease to next smaller preset. Caps at smallest preset.
    func decreasePreset(for columnId: String, projectId: String, viewportWidth: CGFloat) -> CGFloat {
        let presets = Layout.workspaceColumnPresets
        let current = columnFractions[projectId]?[columnId] ?? Layout.workspaceColumnDefaultFraction
        let tolerance: CGFloat = 0.02

        // Find next preset smaller than current
        let next = presets.last { $0 < current - tolerance } ?? presets.first!
        setFraction(next, for: columnId, projectId: projectId)
        return viewportWidth * next
    }

    /// Toggle maximize: fraction 1.0 ↔ restore previous fraction.
    func toggleMaximize(for columnId: String, projectId: String, viewportWidth: CGFloat) -> CGFloat {
        let currentFraction = columnFractions[projectId]?[columnId] ?? Layout.workspaceColumnDefaultFraction
        let tolerance: CGFloat = 0.02

        if abs(currentFraction - 1.0) < tolerance {
            // Currently maximized — restore previous fraction
            let restored = preMaximizeFractions[projectId]?[columnId] ?? Layout.workspaceColumnDefaultFraction
            setFraction(restored, for: columnId, projectId: projectId)
            preMaximizeFractions[projectId]?.removeValue(forKey: columnId)
            return viewportWidth * restored
        } else {
            // Save current fraction and maximize
            var saved = preMaximizeFractions[projectId] ?? [:]
            saved[columnId] = currentFraction
            preMaximizeFractions[projectId] = saved
            setFraction(1.0, for: columnId, projectId: projectId)
            return viewportWidth
        }
    }

    func isInitialized(projectId: String) -> Bool {
        initializedProjects.contains(projectId)
    }

    func markInitialized(projectId: String) {
        initializedProjects.insert(projectId)
    }
}
