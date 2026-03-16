import SwiftUI
import AppKit

enum ActiveView {
    case projects
    case settings
}

private enum StorageKeys {
    static let theme = "blink.theme"
    static let backgroundImage = "blink.backgroundImage"
    static let backgroundOpacity = "blink.backgroundOpacity"
    static let backgroundBlur = "blink.backgroundBlur"
    static let hideTitleBar = "blink.hideTitleBar"
    static let sidebarVisible = "blink.sidebarVisible"
    static let projects = "blink.projects"
    static let lastSelectedProjectId = "blink.lastSelectedProjectId"
}

@MainActor @Observable
final class AppStore {
    // Projects
    var projects: [Project] {
        didSet { Self.saveProjects(projects) }
    }
    var activeProjectId: String?
    var lastSelectedProjectId: String? {
        didSet { UserDefaults.standard.set(lastSelectedProjectId, forKey: StorageKeys.lastSelectedProjectId) }
    }

    // Tabs
    var tabs: [AppTab] = []
    var activeTabId: String?

    // Unread activity tracking
    var unreadTabs: Set<String> = []

    // Theme
    var theme: String {
        didSet { UserDefaults.standard.set(theme, forKey: StorageKeys.theme) }
    }

    // View
    var activeView: ActiveView = .projects
    var showThemePicker = false
    var showProjectSwitcher = false

    // Background
    var backgroundImage: String? {
        didSet { UserDefaults.standard.set(backgroundImage, forKey: StorageKeys.backgroundImage) }
    }
    var backgroundOpacity: Double {
        didSet { UserDefaults.standard.set(backgroundOpacity, forKey: StorageKeys.backgroundOpacity) }
    }
    var backgroundBlur: Double {
        didSet { UserDefaults.standard.set(backgroundBlur, forKey: StorageKeys.backgroundBlur) }
    }
    var hideTitleBar: Bool {
        didSet { UserDefaults.standard.set(hideTitleBar, forKey: StorageKeys.hideTitleBar) }
    }

    // Sidebar
    var sidebarVisible: Bool {
        didSet { UserDefaults.standard.set(sidebarVisible, forKey: StorageKeys.sidebarVisible) }
    }

    init() {
        let defaults = UserDefaults.standard
        let loadedProjects = Self.loadProjects()
        let storedLastProjectId = defaults.string(forKey: StorageKeys.lastSelectedProjectId)

        self.projects = loadedProjects
        self.theme = defaults.string(forKey: StorageKeys.theme) ?? "Josean"
        self.backgroundImage = defaults.string(forKey: StorageKeys.backgroundImage)
        self.hideTitleBar = defaults.object(forKey: StorageKeys.hideTitleBar) as? Bool ?? false
        self.sidebarVisible = defaults.object(forKey: StorageKeys.sidebarVisible) as? Bool ?? true
        if let storedLastProjectId,
           loadedProjects.contains(where: { $0.id == storedLastProjectId }) {
            self.lastSelectedProjectId = storedLastProjectId
        } else {
            self.lastSelectedProjectId = nil
        }

        // Double defaults to 0.0 if unset, so check for existence
        if defaults.object(forKey: StorageKeys.backgroundOpacity) != nil {
            self.backgroundOpacity = defaults.double(forKey: StorageKeys.backgroundOpacity)
        } else {
            self.backgroundOpacity = 0.75
        }

        if defaults.object(forKey: StorageKeys.backgroundBlur) != nil {
            self.backgroundBlur = defaults.double(forKey: StorageKeys.backgroundBlur)
        } else {
            self.backgroundBlur = 0
        }
    }

    // MARK: - View Actions

    func setActiveView(_ view: ActiveView) {
        activeView = view
    }

    func toggleSidebar() {
        sidebarVisible.toggle()
    }

    func presentProjectSwitcher() {
        guard !projects.isEmpty else { return }
        showProjectSwitcher = true
    }

    func dismissProjectSwitcher() {
        showProjectSwitcher = false
    }

    // MARK: - Background Actions

    func setBackgroundImage(_ image: String?) {
        backgroundImage = image
    }

    func setBackgroundOpacity(_ opacity: Double) {
        backgroundOpacity = max(0.1, min(1.0, opacity))
    }

    func setBackgroundBlur(_ blur: Double) {
        backgroundBlur = max(0, min(32, blur))
    }

    func setHideTitleBar(_ hidden: Bool) {
        hideTitleBar = hidden
    }

    var hasWallpaper: Bool {
        backgroundImage != nil
    }

    // Last active tab per project — remembered when switching away
    private var lastActiveTab: [String: String] = [:]

    // MARK: - Actions

    func setActiveProject(_ id: String?) {
        // Remember current tab for the project we're leaving
        if let currentProject = activeProjectId, let currentTab = activeTabId {
            lastActiveTab[currentProject] = currentTab
        }

        activeProjectId = id
        if let id {
            lastSelectedProjectId = id
        }
        activeView = .projects
        if let id {
            // Restore last active tab, or fall back to first tab
            if let remembered = lastActiveTab[id],
               projectTabs(for: id).contains(where: { $0.id == remembered }) {
                activeTabId = remembered
            } else {
                activeTabId = projectTabs(for: id).first?.id
            }
            if let tabId = activeTabId {
                clearUnread(tabId)
            }
        } else {
            activeTabId = nil
        }
    }

    var lastSelectedProject: Project? {
        guard let id = lastSelectedProjectId else { return nil }
        return projects.first { $0.id == id }
    }

    func openProjectSession(_ id: String) {
        setActiveProject(id)
        if activeTabId == nil {
            _ = openTab(projectId: id)
        }
    }

    func resumeLastProjectSession() {
        guard let project = lastSelectedProject else { return }
        openProjectSession(project.id)
    }

    func setActiveTab(_ id: String) {
        activeTabId = id
        clearUnread(id)
    }

    // MARK: - Tab Actions

    /// Create a new shell tab for a project.
    @discardableResult
    func openTab(projectId: String) -> AppTab {
        let count = projectTabs(for: projectId).count + 1
        let defaultLabel = "Terminal \(count)"
        let tab = AppTab(
            id: UUID().uuidString,
            type: "shell",
            label: defaultLabel,
            defaultLabel: defaultLabel,
            projectId: projectId
        )
        tabs.append(tab)
        activeTabId = tab.id
        clearUnread(tab.id)
        return tab
    }

    /// Update a tab's title.
    func setTabTitle(_ tabId: String, title: String) {
        if let idx = tabs.firstIndex(where: { $0.id == tabId }) {
            tabs[idx].label = title
        }
    }

    /// Revert a tab's title to its default name.
    func revertTabTitle(_ tabId: String) {
        if let idx = tabs.firstIndex(where: { $0.id == tabId }) {
            tabs[idx].label = tabs[idx].defaultLabel
        }
    }

    /// Mark a tab as having unread activity.
    func markUnread(_ tabId: String) {
        if tabId != activeTabId {
            unreadTabs.insert(tabId)
        }
    }

    /// Clear unread status for a tab.
    func clearUnread(_ tabId: String) {
        unreadTabs.remove(tabId)
    }

    /// Check if a project has any unread tabs.
    func hasUnread(projectId: String) -> Bool {
        let projectTabIds = Set(projectTabs(for: projectId).map(\.id))
        return !unreadTabs.isDisjoint(with: projectTabIds)
    }

    func projectTabs(for projectId: String) -> [AppTab] {
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
        if lastSelectedProjectId == id {
            lastSelectedProjectId = nil
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

    // MARK: - Project Management

    /// Add a project from a directory path.
    @discardableResult
    func addProject(path: String, activating: Bool = false) -> Project {
        if let existing = projects.first(where: { $0.path == path }) {
            if activating {
                openProjectSession(existing.id)
            }
            return existing
        }

        let name = (path as NSString).lastPathComponent
        let project = Project(
            id: UUID().uuidString,
            name: name,
            path: path,
            color: "#7aa2f7",
            createdAt: .now
        )
        projects.append(project)
        if activating {
            openProjectSession(project.id)
        }
        return project
    }

    @discardableResult
    func pickProjectFolder(activating: Bool = false) -> Project? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a project folder"

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        return addProject(path: url.path, activating: activating)
    }

    // MARK: - Project Persistence

    private static func loadProjects() -> [Project] {
        guard let data = UserDefaults.standard.data(forKey: StorageKeys.projects),
              let projects = try? JSONDecoder().decode([Project].self, from: data) else {
            return []
        }
        return projects
    }

    private static func saveProjects(_ projects: [Project]) {
        if let data = try? JSONEncoder().encode(projects) {
            UserDefaults.standard.set(data, forKey: StorageKeys.projects)
        }
    }
}
