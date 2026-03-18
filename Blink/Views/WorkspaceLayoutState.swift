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

    /// Cycle through preset fractions. Returns the new absolute width.
    func cyclePreset(for columnId: String, projectId: String, viewportWidth: CGFloat) -> CGFloat {
        let presets = Layout.workspaceColumnPresets
        let currentFraction = columnFractions[projectId]?[columnId] ?? Layout.workspaceColumnDefaultFraction
        let tolerance: CGFloat = 0.02

        // Find which preset we're closest to, then advance to the next
        var nextPreset = presets[0]
        for (i, preset) in presets.enumerated() {
            if abs(currentFraction - preset) < tolerance {
                nextPreset = presets[(i + 1) % presets.count]
                break
            }
            if i == presets.count - 1 {
                nextPreset = presets[0]
            }
        }

        setFraction(nextPreset, for: columnId, projectId: projectId)
        preMaximizeFractions[projectId]?.removeValue(forKey: columnId)
        return viewportWidth * nextPreset
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
