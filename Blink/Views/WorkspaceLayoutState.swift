import SwiftUI

@MainActor @Observable
final class WorkspaceLayoutState {
    private var columnWidths: [String: [String: CGFloat]] = [:]
    private var preMaximizeWidths: [String: [String: CGFloat]] = [:]
    private var initializedProjects: Set<String> = []

    func sync(projectId: String, tabIds: [String], defaultWidth: CGFloat) {
        let existingWidths = columnWidths[projectId] ?? [:]
        var nextWidths: [String: CGFloat] = [:]

        for tabId in tabIds {
            nextWidths[tabId] = existingWidths[tabId] ?? defaultWidth
        }

        columnWidths[projectId] = nextWidths

        if tabIds.isEmpty {
            initializedProjects.remove(projectId)
        }
    }

    func width(for tabId: String, projectId: String, default defaultWidth: CGFloat) -> CGFloat {
        columnWidths[projectId]?[tabId] ?? defaultWidth
    }

    func setWidth(_ width: CGFloat, for tabId: String, projectId: String) {
        var widths = columnWidths[projectId] ?? [:]
        widths[tabId] = width
        columnWidths[projectId] = widths
    }

    /// Cycle through preset fractions. Returns the new absolute width.
    func cyclePreset(for tabId: String, projectId: String, viewportWidth: CGFloat) -> CGFloat {
        let presets = Layout.workspaceColumnPresets
        let currentWidth = width(for: tabId, projectId: projectId, default: viewportWidth * Layout.workspaceColumnDefaultFraction)
        let tolerance: CGFloat = 8

        // Find which preset we're closest to, then advance to the next
        var nextPreset = presets[0]
        for (i, fraction) in presets.enumerated() {
            let presetWidth = viewportWidth * fraction
            if abs(currentWidth - presetWidth) < tolerance {
                nextPreset = presets[(i + 1) % presets.count]
                break
            }
            // If we didn't match any preset, default to first preset
            if i == presets.count - 1 {
                nextPreset = presets[0]
            }
        }

        let newWidth = viewportWidth * nextPreset
        setWidth(newWidth, for: tabId, projectId: projectId)
        // Clear maximize state since we're now on a preset
        preMaximizeWidths[projectId]?.removeValue(forKey: tabId)
        return newWidth
    }

    /// Toggle maximize: full viewport width ↔ restore previous size.
    func toggleMaximize(for tabId: String, projectId: String, viewportWidth: CGFloat) -> CGFloat {
        let currentWidth = width(for: tabId, projectId: projectId, default: viewportWidth * Layout.workspaceColumnDefaultFraction)
        let tolerance: CGFloat = 8

        if abs(currentWidth - viewportWidth) < tolerance {
            // Currently maximized — restore previous width
            let restored = preMaximizeWidths[projectId]?[tabId] ?? (viewportWidth * Layout.workspaceColumnDefaultFraction)
            setWidth(restored, for: tabId, projectId: projectId)
            preMaximizeWidths[projectId]?.removeValue(forKey: tabId)
            return restored
        } else {
            // Save current width and maximize
            var saved = preMaximizeWidths[projectId] ?? [:]
            saved[tabId] = currentWidth
            preMaximizeWidths[projectId] = saved
            setWidth(viewportWidth, for: tabId, projectId: projectId)
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
