import SwiftUI

@Observable
final class AppStore {
    // Projects
    var projects: [Project] = Project.dummy
    var activeProjectId: String?

    // Tabs
    var tabs: [Tab] = Tab.dummy
    var activeTabId: String?

    // Theme
    var theme: String = "ghostty"

    // Sidebar
    var sidebarVisible: Bool = true

    // MARK: - Actions

    func setActiveProject(_ id: String?) {
        activeProjectId = id
        if let id {
            let projectTabs = projectTabs(for: id)
            activeTabId = projectTabs.first?.id
        } else {
            activeTabId = nil
        }
    }

    func setActiveTab(_ id: String) {
        activeTabId = id
    }

    func projectTabs(for projectId: String) -> [Tab] {
        tabs.filter { $0.projectId == projectId }
    }

    func terminalCount(for projectId: String) -> Int {
        tabs.filter { $0.projectId == projectId && $0.type == "shell" }.count
    }

    func removeProject(_ id: String) {
        projects.removeAll { $0.id == id }
        tabs.removeAll { $0.projectId == id }
        if activeProjectId == id {
            activeProjectId = nil
            activeTabId = nil
        }
    }

    func closeTab(_ id: String) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        tabs.removeAll { $0.id == id }
        if activeTabId == id {
            let remaining = projectTabs(for: tab.projectId)
            activeTabId = remaining.last?.id
        }
    }
}
