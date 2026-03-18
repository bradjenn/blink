import SwiftUI

@MainActor @Observable
final class WorkspaceLayoutState {
    private var columnWidths: [String: [String: CGFloat]] = [:]
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

    func isInitialized(projectId: String) -> Bool {
        initializedProjects.contains(projectId)
    }

    func markInitialized(projectId: String) {
        initializedProjects.insert(projectId)
    }
}
