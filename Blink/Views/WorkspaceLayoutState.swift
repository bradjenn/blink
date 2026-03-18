import SwiftUI

@MainActor @Observable
final class WorkspaceLayoutState {
    /// Stores column width as a fraction of the viewport (e.g. 0.5 = half width).
    /// Fractions adapt automatically when the viewport resizes or sidebar toggles.
    private var columnFractions: [String: [String: CGFloat]] = [:]
    private var preMaximizeFractions: [String: [String: CGFloat]] = [:]
    private var initializedProjects: Set<String> = []

    func sync(projectId: String, tabIds: [String], defaultFraction: CGFloat) {
        let existing = columnFractions[projectId] ?? [:]
        var next: [String: CGFloat] = [:]

        for tabId in tabIds {
            next[tabId] = existing[tabId] ?? defaultFraction
        }

        columnFractions[projectId] = next

        if tabIds.isEmpty {
            initializedProjects.remove(projectId)
        }
    }

    /// Returns the absolute pixel width for a column given the current viewport.
    func width(for tabId: String, projectId: String, viewportWidth: CGFloat) -> CGFloat {
        let fraction = columnFractions[projectId]?[tabId] ?? Layout.workspaceColumnDefaultFraction
        return viewportWidth * fraction
    }

    func setFraction(_ fraction: CGFloat, for tabId: String, projectId: String) {
        var fractions = columnFractions[projectId] ?? [:]
        fractions[tabId] = fraction
        columnFractions[projectId] = fractions
    }

    /// Cycle through preset fractions. Returns the new absolute width.
    func cyclePreset(for tabId: String, projectId: String, viewportWidth: CGFloat) -> CGFloat {
        let presets = Layout.workspaceColumnPresets
        let currentFraction = columnFractions[projectId]?[tabId] ?? Layout.workspaceColumnDefaultFraction
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

        setFraction(nextPreset, for: tabId, projectId: projectId)
        preMaximizeFractions[projectId]?.removeValue(forKey: tabId)
        return viewportWidth * nextPreset
    }

    /// Toggle maximize: fraction 1.0 ↔ restore previous fraction.
    func toggleMaximize(for tabId: String, projectId: String, viewportWidth: CGFloat) -> CGFloat {
        let currentFraction = columnFractions[projectId]?[tabId] ?? Layout.workspaceColumnDefaultFraction
        let tolerance: CGFloat = 0.02

        if abs(currentFraction - 1.0) < tolerance {
            // Currently maximized — restore previous fraction
            let restored = preMaximizeFractions[projectId]?[tabId] ?? Layout.workspaceColumnDefaultFraction
            setFraction(restored, for: tabId, projectId: projectId)
            preMaximizeFractions[projectId]?.removeValue(forKey: tabId)
            return viewportWidth * restored
        } else {
            // Save current fraction and maximize
            var saved = preMaximizeFractions[projectId] ?? [:]
            saved[tabId] = currentFraction
            preMaximizeFractions[projectId] = saved
            setFraction(1.0, for: tabId, projectId: projectId)
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
