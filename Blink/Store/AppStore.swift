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
    static let lastActiveTabs = "blink.lastActiveTabs"
    static let workspaceViewportOffsets = "blink.workspaceViewportOffsets"
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

    // Overview
    var isOverviewMode = false
    var overviewHighlightedColumnId: String?

    // Columns — source of truth for spatial layout (left-to-right order)
    var columns: [String: [Column]] = [:]
    var columnFocusedTab: [String: String] = [:]

    // Theme
    var theme: String {
        didSet { UserDefaults.standard.set(theme, forKey: StorageKeys.theme) }
    }

    // View
    var activeView: ActiveView = .projects
    var showThemePicker = false
    var showProjectSwitcher = false
    var showNewTabMenu = false

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
    var sidebarFocused: Bool = false
    var surfaceManager: SurfaceManager?

    private var lastActiveTab: [String: String] {
        didSet { Self.saveDictionary(lastActiveTab, forKey: StorageKeys.lastActiveTabs) }
    }
    private var workspaceViewportOffsets: [String: Double] {
        didSet { Self.saveDictionary(workspaceViewportOffsets, forKey: StorageKeys.workspaceViewportOffsets) }
    }

    func focusTerminal() {
        sidebarFocused = false
        if let tabId = activeTabId {
            surfaceManager?.surface(for: tabId)?.focus()
        }
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
        self.lastActiveTab = Self.loadDictionary(forKey: StorageKeys.lastActiveTabs)
        self.workspaceViewportOffsets = Self.loadDictionary(forKey: StorageKeys.workspaceViewportOffsets)
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
        withAnimation(.snappy(duration: 0.18, extraBounce: 0)) {
            sidebarVisible.toggle()
            if !sidebarVisible { sidebarFocused = false }
        }
    }

    func toggleSidebarFocus() {
        if sidebarFocused {
            focusTerminal()
        } else {
            if !sidebarVisible {
                withAnimation(.snappy(duration: 0.18, extraBounce: 0)) {
                    sidebarVisible = true
                }
            }
            sidebarFocused = true
        }
    }

    func selectNextProject() {
        guard !projects.isEmpty else { return }
        guard let currentId = activeProjectId,
              let idx = projects.firstIndex(where: { $0.id == currentId }) else {
            setActiveProject(projects.first?.id)
            return
        }
        let next = projects.index(after: idx)
        if next < projects.endIndex {
            setActiveProject(projects[next].id)
        }
    }

    func selectPreviousProject() {
        guard !projects.isEmpty else { return }
        guard let currentId = activeProjectId,
              let idx = projects.firstIndex(where: { $0.id == currentId }) else {
            setActiveProject(projects.last?.id)
            return
        }
        if idx > projects.startIndex {
            setActiveProject(projects[projects.index(before: idx)].id)
        }
    }

    func presentProjectSwitcher() {
        guard !projects.isEmpty else { return }
        showProjectSwitcher = true
    }

    func dismissProjectSwitcher() {
        showProjectSwitcher = false
    }

    func presentThemePicker() {
        showThemePicker = true
    }

    func dismissThemePicker() {
        showThemePicker = false
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

    // MARK: - Column Helpers

    func projectColumns(for projectId: String) -> [Column] {
        columns[projectId] ?? []
    }

    func columnFor(tabId: String) -> Column? {
        guard let tab = tabs.first(where: { $0.id == tabId }) else { return nil }
        return projectColumns(for: tab.projectId).first { $0.tabIds.contains(tabId) }
    }

    var activeColumn: Column? {
        guard let tabId = activeTabId else { return nil }
        return columnFor(tabId: tabId)
    }

    /// Returns tabs in column-major order: left-to-right columns, top-to-bottom within each.
    func orderedTabs(for projectId: String) -> [AppTab] {
        let cols = projectColumns(for: projectId)
        return cols.flatMap { col in
            col.tabIds.compactMap { tabId in
                tabs.first { $0.id == tabId }
            }
        }
    }

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

        // Ensure columns exist for all tabs (migration from pre-column model)
        if let id {
            let projectCols = projectColumns(for: id)
            let columnedTabIds = Set(projectCols.flatMap(\.tabIds))
            let uncolumnedTabs = projectTabs(for: id).filter { !columnedTabIds.contains($0.id) }
            if !uncolumnedTabs.isEmpty {
                var cols = projectCols
                for tab in uncolumnedTabs {
                    cols.append(Column(id: UUID().uuidString, tabIds: [tab.id]))
                }
                columns[id] = cols
            }
        }

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
        if let tab = tabs.first(where: { $0.id == id }) {
            lastActiveTab[tab.projectId] = id
        }
        clearUnread(id)
    }

    func selectNextTab() {
        guard let projectId = activeProjectId else { return }
        let tabs = projectTabs(for: projectId)
        guard !tabs.isEmpty else { return }

        guard let activeTabId,
              let currentIndex = tabs.firstIndex(where: { $0.id == activeTabId }) else {
            setActiveTab(tabs[0].id)
            return
        }

        let nextIndex = tabs.index(after: currentIndex)
        let tab = nextIndex < tabs.endIndex ? tabs[nextIndex] : tabs[0]
        setActiveTab(tab.id)
    }

    func selectPreviousTab() {
        guard let projectId = activeProjectId else { return }
        let tabs = projectTabs(for: projectId)
        guard !tabs.isEmpty else { return }

        guard let activeTabId,
              let currentIndex = tabs.firstIndex(where: { $0.id == activeTabId }) else {
            setActiveTab(tabs[tabs.index(before: tabs.endIndex)].id)
            return
        }

        let tab = currentIndex > tabs.startIndex
            ? tabs[tabs.index(before: currentIndex)]
            : tabs[tabs.index(before: tabs.endIndex)]
        setActiveTab(tab.id)
    }

    func focusLeft() {
        guard let projectId = activeProjectId else { return }
        let tabs = projectTabs(for: projectId)

        if sidebarFocused {
            return
        }

        guard let activeTabId,
              let currentIndex = tabs.firstIndex(where: { $0.id == activeTabId }) else { return }

        if currentIndex > tabs.startIndex {
            setActiveTab(tabs[tabs.index(before: currentIndex)].id)
        } else if sidebarVisible {
            sidebarFocused = true
        }
    }

    func focusRight() {
        guard let projectId = activeProjectId else { return }
        let tabs = projectTabs(for: projectId)

        if sidebarFocused {
            sidebarFocused = false
            if let tabId = activeTabId {
                surfaceManager?.surface(for: tabId)?.focus()
            }
            return
        }

        guard let activeTabId,
              let currentIndex = tabs.firstIndex(where: { $0.id == activeTabId }) else { return }

        let nextIndex = tabs.index(after: currentIndex)
        if nextIndex < tabs.endIndex {
            setActiveTab(tabs[nextIndex].id)
        }
    }

    func moveActiveTabLeft() {
        guard let projectId = activeProjectId,
              let activeTabId else { return }

        let projectTabIds = projectTabs(for: projectId).map(\.id)
        guard let localIndex = projectTabIds.firstIndex(of: activeTabId),
              localIndex > projectTabIds.startIndex else { return }

        let prevTabId = projectTabIds[projectTabIds.index(before: localIndex)]

        guard let globalCurrent = tabs.firstIndex(where: { $0.id == activeTabId }),
              let globalPrev = tabs.firstIndex(where: { $0.id == prevTabId }) else { return }

        tabs.swapAt(globalCurrent, globalPrev)
    }

    func moveActiveTabRight() {
        guard let projectId = activeProjectId,
              let activeTabId else { return }

        let projectTabIds = projectTabs(for: projectId).map(\.id)
        guard let localIndex = projectTabIds.firstIndex(of: activeTabId) else { return }

        let nextLocalIndex = projectTabIds.index(after: localIndex)
        guard nextLocalIndex < projectTabIds.endIndex else { return }

        let nextTabId = projectTabIds[nextLocalIndex]

        guard let globalCurrent = tabs.firstIndex(where: { $0.id == activeTabId }),
              let globalNext = tabs.firstIndex(where: { $0.id == nextTabId }) else { return }

        tabs.swapAt(globalCurrent, globalNext)
    }

    // MARK: - Overview Actions

    func toggleOverview() {
        guard let projectId = activeProjectId else { return }
        let tabs = projectTabs(for: projectId)
        guard !tabs.isEmpty else { return }

        if isOverviewMode {
            exitOverview(selecting: overviewHighlightedColumnId)
        } else {
            isOverviewMode = true
            overviewHighlightedColumnId = activeTabId
        }
    }

    func exitOverview(selecting tabId: String?) {
        if let tabId {
            setActiveTab(tabId)
        }
        isOverviewMode = false
        overviewHighlightedColumnId = nil
    }

    func overviewHighlightLeft() {
        guard let projectId = activeProjectId else { return }
        let tabs = projectTabs(for: projectId)
        guard let highlightId = overviewHighlightedColumnId,
              let idx = tabs.firstIndex(where: { $0.id == highlightId }),
              idx > tabs.startIndex else { return }
        overviewHighlightedColumnId = tabs[tabs.index(before: idx)].id
    }

    func overviewHighlightRight() {
        guard let projectId = activeProjectId else { return }
        let tabs = projectTabs(for: projectId)
        guard let highlightId = overviewHighlightedColumnId,
              let idx = tabs.firstIndex(where: { $0.id == highlightId }) else { return }
        let next = tabs.index(after: idx)
        guard next < tabs.endIndex else { return }
        overviewHighlightedColumnId = tabs[next].id
    }

    // MARK: - Tab Actions

    /// Create a new shell tab for a project.
    @discardableResult
    func openTab(projectId: String, command: String? = nil, label: String? = nil) -> AppTab {
        let count = projectTabs(for: projectId).count + 1
        let defaultLabel = label ?? "Terminal \(count)"
        let tab = AppTab(
            id: UUID().uuidString,
            type: "shell",
            label: defaultLabel,
            defaultLabel: defaultLabel,
            projectId: projectId,
            command: command
        )
        tabs.append(tab)

        // Create a new single-tab column
        let column = Column(id: UUID().uuidString, tabIds: [tab.id])
        var projectCols = columns[projectId] ?? []
        projectCols.append(column)
        columns[projectId] = projectCols

        setActiveTab(tab.id)
        return tab
    }

    func openOrFocusCommandTab(projectId: String, command: String, label: String) {
        if let existing = projectTabs(for: projectId).first(where: { $0.command == command }) {
            setActiveTab(existing.id)
        } else {
            openTab(projectId: projectId, command: command, label: label)
        }
    }

    func openOrFocusCommandTabForActiveProject(command: String, label: String) {
        guard let projectId = activeProjectId else { return }
        openOrFocusCommandTab(projectId: projectId, command: command, label: label)
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
        let tabIds = tabs.filter { $0.projectId == id }.map(\.id)
        projects.removeAll { $0.id == id }
        tabs.removeAll { $0.projectId == id }
        unreadTabs.subtract(tabIds)
        lastActiveTab[id] = nil
        if activeProjectId == id {
            activeProjectId = nil
            activeTabId = nil
        }
        if lastSelectedProjectId == id {
            lastSelectedProjectId = nil
        }
        workspaceViewportOffsets[id] = nil

        // Clean up column state
        if let projectCols = columns[id] {
            for col in projectCols {
                columnFocusedTab[col.id] = nil
            }
        }
        columns[id] = nil

        let surfaceManager = surfaceManager
        DispatchQueue.main.async {
            surfaceManager?.destroySurfaces(tabIds: tabIds)
        }
    }

    func closeTab(_ id: String) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        let projectId = tab.projectId

        // Find the column and position of this tab
        var projectCols = columns[projectId] ?? []
        guard let colIdx = projectCols.firstIndex(where: { $0.tabIds.contains(id) }) else { return }
        let paneIdx = projectCols[colIdx].tabIds.firstIndex(of: id)!

        // Remove tab from column
        projectCols[colIdx].tabIds.removeAll { $0 == id }

        // Determine next focus before removing empty column
        var nextFocusTabId: String? = nil
        if activeTabId == id {
            if !projectCols[colIdx].tabIds.isEmpty {
                // Prefer next pane down, then previous pane up
                let newPaneIdx = min(paneIdx, projectCols[colIdx].tabIds.count - 1)
                nextFocusTabId = projectCols[colIdx].tabIds[newPaneIdx]
            }
        }

        // Remove column if empty
        if projectCols[colIdx].tabIds.isEmpty {
            let removedColId = projectCols[colIdx].id
            columnFocusedTab[removedColId] = nil
            projectCols.remove(at: colIdx)
        }

        columns[projectId] = projectCols

        // Remove tab data
        tabs.removeAll { $0.id == id }
        unreadTabs.remove(id)
        if lastActiveTab[projectId] == id {
            lastActiveTab[projectId] = nil
        }

        // Set next focus
        if activeTabId == id {
            if let next = nextFocusTabId {
                setActiveTab(next)
            } else {
                // Fall back to adjacent column (prefer right, then left)
                let updatedCols = projectColumns(for: projectId)
                let adjacentCol: Column? = {
                    // colIdx now points to what was the right neighbor (since we removed the empty column)
                    if colIdx < updatedCols.count {
                        return updatedCols[colIdx]
                    } else if colIdx > 0 {
                        return updatedCols[colIdx - 1]
                    }
                    return nil
                }()
                if let adjCol = adjacentCol,
                   let fallback = columnFocusedTab[adjCol.id] ?? adjCol.tabIds.first {
                    setActiveTab(fallback)
                } else {
                    activeTabId = nil
                    workspaceViewportOffsets[projectId] = nil
                }
            }
        }

        reindexTabs(for: projectId)

        let surfaceManager = surfaceManager
        DispatchQueue.main.async {
            surfaceManager?.destroySurface(tabId: id)
        }
    }

    func closeActiveTab() {
        guard let activeTabId else { return }
        closeTab(activeTabId)
    }

    /// Re-number default tab labels ("Terminal 1", "Terminal 2", ...) for a project.
    private func reindexTabs(for projectId: String) {
        var counter = 0
        for i in tabs.indices where tabs[i].projectId == projectId && tabs[i].type == "shell" && tabs[i].command == nil {
            counter += 1
            let newDefault = "Terminal \(counter)"
            if tabs[i].label == tabs[i].defaultLabel {
                tabs[i].label = newDefault
            }
            tabs[i].defaultLabel = newDefault
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

    func workspaceViewportOffset(for projectId: String) -> CGFloat {
        CGFloat(workspaceViewportOffsets[projectId] ?? 0)
    }

    func hasWorkspaceViewportOffset(for projectId: String) -> Bool {
        workspaceViewportOffsets[projectId] != nil
    }

    func setWorkspaceViewportOffset(_ offset: CGFloat, for projectId: String) {
        workspaceViewportOffsets[projectId] = Double(offset)
    }

    private static func loadDictionary<Value: Decodable>(forKey key: String) -> [String: Value] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode([String: Value].self, from: data) else {
            return [:]
        }
        return value
    }

    private static func saveDictionary<Value: Encodable>(_ value: [String: Value], forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
