import SwiftUI
import AppKit
import CoreImage

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
    static let columns = "blink.columns"
    static let fontFamily = "blink.fontFamily"
    static let uiFontFamily = "blink.uiFontFamily"
    static let fontSize = "blink.fontSize"
    static let cursorStyle = "blink.cursorStyle"
    static let shell = "blink.shell"
    static let focusCenteringMode = "blink.focusCenteringMode"
    static let spotifyEnabled = "blink.spotifyEnabled"
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
    var pendingMaximizedTabId: String?

    /// O(1) tab lookup by ID. Rebuilt on access when tabs change.
    var tabsById: [String: AppTab] {
        Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
    }

    // Unread activity tracking
    var unreadTabs: Set<String> = []

    // Overview
    var isOverviewMode = false
    var overviewHighlightedColumnId: String?
    var overviewHighlightedTabId: String?

    // Columns — source of truth for spatial layout (left-to-right order)
    var columns: [String: [Column]] = [:] {
        didSet { Self.saveColumns(columns) }
    }
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
    var showCommandPalette = false
    var themePickerFocusRequest = 0
    var projectSwitcherFocusRequest = 0

    // Background
    var backgroundImage: String? {
        didSet {
            UserDefaults.standard.set(backgroundImage, forKey: StorageKeys.backgroundImage)
            updateBlurredWallpaper()
        }
    }
    var backgroundOpacity: Double {
        didSet { UserDefaults.standard.set(backgroundOpacity, forKey: StorageKeys.backgroundOpacity) }
    }
    var backgroundBlur: Double {
        didSet {
            UserDefaults.standard.set(backgroundBlur, forKey: StorageKeys.backgroundBlur)
            updateBlurredWallpaper()
        }
    }
    var hideTitleBar: Bool {
        didSet { UserDefaults.standard.set(hideTitleBar, forKey: StorageKeys.hideTitleBar) }
    }

    // Terminal
    var fontFamily: String {
        didSet { UserDefaults.standard.set(fontFamily, forKey: StorageKeys.fontFamily) }
    }
    // UI
    var uiFontFamily: String {
        didSet { UserDefaults.standard.set(uiFontFamily, forKey: StorageKeys.uiFontFamily) }
    }
    var fontSize: Double {
        didSet { UserDefaults.standard.set(fontSize, forKey: StorageKeys.fontSize) }
    }
    var cursorStyle: CursorStyle {
        didSet { UserDefaults.standard.set(cursorStyle.rawValue, forKey: StorageKeys.cursorStyle) }
    }
    var shell: String {
        didSet { UserDefaults.standard.set(shell, forKey: StorageKeys.shell) }
    }
    var spotifyEnabled: Bool {
        didSet { UserDefaults.standard.set(spotifyEnabled, forKey: StorageKeys.spotifyEnabled) }
    }
    // Focus centering
    var focusCenteringMode: FocusCenteringMode {
        didSet { UserDefaults.standard.set(focusCenteringMode.rawValue, forKey: StorageKeys.focusCenteringMode) }
    }

    static var defaultShell: String {
        ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }


    // Sidebar
    var sidebarVisible: Bool {
        didSet { UserDefaults.standard.set(sidebarVisible, forKey: StorageKeys.sidebarVisible) }
    }
    var sidebarFocused: Bool = false
    var surfaceManager: SurfaceManager?
    private var sidebarFocusProtectionDeadline: Date?
    private var pendingSidebarFocusOnReveal = false

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

    private func activateTerminalFocusSoon() {
        sidebarFocused = false
        DispatchQueue.main.async { [weak self] in
            self?.focusTerminal()
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
        self.fontFamily = defaults.string(forKey: StorageKeys.fontFamily) ?? "MesloLGS Nerd Font Mono"
        self.uiFontFamily = defaults.string(forKey: StorageKeys.uiFontFamily) ?? "MesloLGS Nerd Font Mono"
        self.fontSize = defaults.object(forKey: StorageKeys.fontSize) != nil
            ? defaults.double(forKey: StorageKeys.fontSize) : 19
        self.cursorStyle = CursorStyle(rawValue: defaults.string(forKey: StorageKeys.cursorStyle) ?? "") ?? .block
        self.shell = defaults.string(forKey: StorageKeys.shell) ?? Self.defaultShell
        self.spotifyEnabled = defaults.object(forKey: StorageKeys.spotifyEnabled) as? Bool ?? false
        self.focusCenteringMode = FocusCenteringMode(rawValue: defaults.string(forKey: StorageKeys.focusCenteringMode) ?? "") ?? .never
        self.lastActiveTab = Self.loadDictionary(forKey: StorageKeys.lastActiveTabs)
        self.workspaceViewportOffsets = Self.loadDictionary(forKey: StorageKeys.workspaceViewportOffsets)
        self.columns = Self.loadColumns()
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

        // Pre-render blurred wallpaper from persisted settings
        updateBlurredWallpaper()
    }

    // MARK: - View Actions

    func setActiveView(_ view: ActiveView) {
        activeView = view
    }

    func toggleSettings() {
        showCommandPalette = false
        activeView = activeView == .settings ? .projects : .settings
    }

    func toggleSidebar() {
        withAnimation(.snappy(duration: 0.18, extraBounce: 0)) {
            sidebarVisible.toggle()
            if sidebarVisible && activeTabId == nil {
                sidebarFocused = true
            } else if !sidebarVisible {
                sidebarFocused = false
            }
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

    func focusSidebar() {
        let wasHidden = !sidebarVisible
        if wasHidden {
            pendingSidebarFocusOnReveal = true
            withAnimation(.snappy(duration: 0.18, extraBounce: 0)) {
                sidebarVisible = true
            }
        } else {
            pendingSidebarFocusOnReveal = false
        }
        // The command palette dismissal can briefly hand first responder back to
        // the terminal, which would otherwise clear the sidebar outline.
        sidebarFocusProtectionDeadline = Date().addingTimeInterval(0.2)
        sidebarFocused = true
    }

    func completePendingSidebarRevealFocus() {
        guard pendingSidebarFocusOnReveal, sidebarVisible else { return }
        pendingSidebarFocusOnReveal = false
        sidebarFocusProtectionDeadline = Date().addingTimeInterval(0.35)
        sidebarFocused = true
    }

    func shouldClearSidebarFocusForTerminalInteraction() -> Bool {
        if let deadline = sidebarFocusProtectionDeadline, deadline > Date() {
            return false
        }
        sidebarFocusProtectionDeadline = nil
        return true
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

    func presentProjectSwitcher(focusSearch: Bool = false) {
        guard !projects.isEmpty else { return }
        showCommandPalette = false
        showProjectSwitcher = true
        if focusSearch {
            projectSwitcherFocusRequest += 1
        }
    }

    func dismissProjectSwitcher() {
        showProjectSwitcher = false
    }

    func presentThemePicker(focusSearch: Bool = false) {
        showCommandPalette = false
        showThemePicker = true
        if focusSearch {
            themePickerFocusRequest += 1
        }
    }

    func dismissThemePicker() {
        showThemePicker = false
    }

    func presentCommandPalette() {
        sidebarFocused = false
        showProjectSwitcher = false
        showThemePicker = false
        showCommandPalette = true
    }

    func dismissCommandPalette() {
        showCommandPalette = false
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

    /// Pre-rendered blurred wallpaper image. Avoids real-time GPU blur every frame.
    var cachedBlurredWallpaper: NSImage?

    func updateBlurredWallpaper() {
        guard let wallpaperId = backgroundImage else {
            cachedBlurredWallpaper = nil
            return
        }

        guard let source = loadWallpaperNSImage(for: wallpaperId) else {
            cachedBlurredWallpaper = nil
            return
        }

        if backgroundBlur > 0 {
            cachedBlurredWallpaper = source.blurredCopy(radius: backgroundBlur)
        } else {
            cachedBlurredWallpaper = source
        }
    }

    private func loadWallpaperNSImage(for id: String) -> NSImage? {
        if let preset = WallpaperPreset.find(id) {
            let parts = preset.filename.split(separator: ".")
            if parts.count == 2,
               let url = Bundle.main.url(forResource: String(parts[0]), withExtension: String(parts[1])) {
                return NSImage(contentsOf: url)
            }
        } else if !id.hasPrefix("preset:") {
            return NSImage(contentsOfFile: id)
        }
        return nil
    }

    // MARK: - Column Helpers

    func projectColumns(for projectId: String) -> [Column] {
        columns[projectId] ?? []
    }

    func columnFor(tabId: String) -> Column? {
        guard let tab = tabsById[tabId] else { return nil }
        return projectColumns(for: tab.projectId).first { $0.tabIds.contains(tabId) }
    }

    var activeColumn: Column? {
        guard let tabId = activeTabId else { return nil }
        return columnFor(tabId: tabId)
    }

    /// Returns tabs in column-major order: left-to-right columns, top-to-bottom within each.
    func orderedTabs(for projectId: String) -> [AppTab] {
        let cols = projectColumns(for: projectId)
        let lookup = tabsById
        return cols.flatMap { col in
            col.tabIds.compactMap { lookup[$0] }
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

        // Sync columns with actual tabs — remove stale IDs, add uncolumned tabs
        if let id {
            let existingTabIds = Set(projectTabs(for: id).map(\.id))

            // Remove stale tab IDs from persisted columns, drop empty columns
            var cols = projectColumns(for: id)
            cols = cols.compactMap { col in
                var cleaned = col
                cleaned.tabIds = col.tabIds.filter { existingTabIds.contains($0) }
                return cleaned.tabIds.isEmpty ? nil : cleaned
            }

            // Add any tabs not in a column
            let columnedTabIds = Set(cols.flatMap(\.tabIds))
            let uncolumnedTabs = projectTabs(for: id).filter { !columnedTabIds.contains($0.id) }
            for tab in uncolumnedTabs {
                cols.append(Column(id: UUID().uuidString, tabIds: [tab.id]))
            }

            columns[id] = cols
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
        sidebarFocused = false
        DispatchQueue.main.async { [weak self] in
            self?.focusTerminal()
        }
    }

    func resumeLastProjectSession() {
        guard let project = lastSelectedProject else { return }
        openProjectSession(project.id)
    }

    func setActiveTab(_ id: String) {
        activeTabId = id
        if let tab = tabsById[id] {
            lastActiveTab[tab.projectId] = id
        }
        clearUnread(id)
    }

    func selectNextTab() {
        guard let projectId = activeProjectId else { return }
        let ordered = orderedTabs(for: projectId)
        guard !ordered.isEmpty else { return }

        guard let activeTabId,
              let currentIndex = ordered.firstIndex(where: { $0.id == activeTabId }) else {
            setActiveTab(ordered[0].id)
            return
        }

        let nextIndex = ordered.index(after: currentIndex)
        guard nextIndex < ordered.endIndex else { return }
        setActiveTab(ordered[nextIndex].id)
    }

    func selectPreviousTab() {
        guard let projectId = activeProjectId else { return }
        let ordered = orderedTabs(for: projectId)
        guard !ordered.isEmpty else { return }

        guard let activeTabId,
              let currentIndex = ordered.firstIndex(where: { $0.id == activeTabId }) else {
            setActiveTab(ordered[ordered.index(before: ordered.endIndex)].id)
            return
        }

        guard currentIndex > ordered.startIndex else { return }
        setActiveTab(ordered[ordered.index(before: currentIndex)].id)
    }

    func focusLeft() {
        guard let projectId = activeProjectId else { return }
        let cols = projectColumns(for: projectId)

        if sidebarFocused { return }

        guard let currentCol = activeColumn,
              let colIdx = cols.firstIndex(where: { $0.id == currentCol.id }) else { return }

        // Save focus memory for current column
        if let tabId = activeTabId {
            columnFocusedTab[currentCol.id] = tabId
        }

        if colIdx > cols.startIndex {
            let targetCol = cols[cols.index(before: colIdx)]
            let targetTab = columnFocusedTab[targetCol.id] ?? targetCol.tabIds.first
            if let targetTab { setActiveTab(targetTab) }
        } else if sidebarVisible {
            sidebarFocused = true
        }
    }

    func focusRight() {
        guard let projectId = activeProjectId else { return }
        let cols = projectColumns(for: projectId)

        if sidebarFocused {
            sidebarFocused = false
            if let tabId = activeTabId {
                surfaceManager?.surface(for: tabId)?.focus()
            }
            return
        }

        guard let currentCol = activeColumn,
              let colIdx = cols.firstIndex(where: { $0.id == currentCol.id }) else { return }

        // Save focus memory for current column
        if let tabId = activeTabId {
            columnFocusedTab[currentCol.id] = tabId
        }

        let nextIdx = cols.index(after: colIdx)
        if nextIdx < cols.endIndex {
            let targetCol = cols[nextIdx]
            let targetTab = columnFocusedTab[targetCol.id] ?? targetCol.tabIds.first
            if let targetTab { setActiveTab(targetTab) }
        }
    }

    func focusDown() {
        guard let currentCol = activeColumn,
              let activeTabId,
              let paneIdx = currentCol.tabIds.firstIndex(of: activeTabId) else { return }

        let nextIdx = currentCol.tabIds.index(after: paneIdx)
        if nextIdx < currentCol.tabIds.endIndex {
            setActiveTab(currentCol.tabIds[nextIdx])
        }
    }

    func focusUp() {
        guard let currentCol = activeColumn,
              let activeTabId,
              let paneIdx = currentCol.tabIds.firstIndex(of: activeTabId) else { return }

        if paneIdx > currentCol.tabIds.startIndex {
            setActiveTab(currentCol.tabIds[currentCol.tabIds.index(before: paneIdx)])
        }
    }

    func moveColumnLeft() {
        guard let projectId = activeProjectId,
              let currentCol = activeColumn else { return }
        var cols = projectColumns(for: projectId)
        guard let idx = cols.firstIndex(where: { $0.id == currentCol.id }),
              idx > cols.startIndex else { return }
        cols.swapAt(idx, cols.index(before: idx))
        columns[projectId] = cols
    }

    func moveColumnRight() {
        guard let projectId = activeProjectId,
              let currentCol = activeColumn else { return }
        var cols = projectColumns(for: projectId)
        guard let idx = cols.firstIndex(where: { $0.id == currentCol.id }) else { return }
        let nextIdx = cols.index(after: idx)
        guard nextIdx < cols.endIndex else { return }
        cols.swapAt(idx, nextIdx)
        columns[projectId] = cols
    }

    func absorbFromLeft() {
        guard let projectId = activeProjectId,
              let currentCol = activeColumn else { return }
        var cols = projectColumns(for: projectId)
        guard let colIdx = cols.firstIndex(where: { $0.id == currentCol.id }),
              colIdx > cols.startIndex else { return }

        let sourceIdx = cols.index(before: colIdx)
        guard let absorbedTabId = cols[sourceIdx].tabIds.last else { return }

        // Move tab from source column to current column
        cols[sourceIdx].tabIds.removeLast()
        cols[colIdx].tabIds.append(absorbedTabId)

        // Clear stale focus memory if it pointed to the moved tab
        if columnFocusedTab[cols[sourceIdx].id] == absorbedTabId {
            columnFocusedTab.removeValue(forKey: cols[sourceIdx].id)
        }

        // Remove source column if empty
        if cols[sourceIdx].tabIds.isEmpty {
            columnFocusedTab[cols[sourceIdx].id] = nil
            cols.remove(at: sourceIdx)
        }

        columns[projectId] = cols
    }

    func absorbFromRight() {
        guard let projectId = activeProjectId,
              let currentCol = activeColumn else { return }
        var cols = projectColumns(for: projectId)
        guard let colIdx = cols.firstIndex(where: { $0.id == currentCol.id }) else { return }

        let sourceIdx = cols.index(after: colIdx)
        guard sourceIdx < cols.endIndex,
              let absorbedTabId = cols[sourceIdx].tabIds.last else { return }

        // Move tab from source column to current column
        cols[sourceIdx].tabIds.removeLast()
        cols[colIdx].tabIds.append(absorbedTabId)

        // Clear stale focus memory if it pointed to the moved tab
        if columnFocusedTab[cols[sourceIdx].id] == absorbedTabId {
            columnFocusedTab.removeValue(forKey: cols[sourceIdx].id)
        }

        // Remove source column if empty
        if cols[sourceIdx].tabIds.isEmpty {
            columnFocusedTab[cols[sourceIdx].id] = nil
            cols.remove(at: sourceIdx)
        }

        columns[projectId] = cols
    }

    func expelActiveTab() {
        guard let projectId = activeProjectId,
              let activeTabId,
              let currentCol = activeColumn else { return }
        guard currentCol.tabIds.count > 1 else { return }

        var cols = projectColumns(for: projectId)
        guard let colIdx = cols.firstIndex(where: { $0.id == currentCol.id }) else { return }

        // Remove tab from current column
        cols[colIdx].tabIds.removeAll { $0 == activeTabId }

        // Clear stale focus memory — the expelled tab no longer lives in this column
        columnFocusedTab.removeValue(forKey: currentCol.id)

        // Create new column to the right
        let newCol = Column(id: UUID().uuidString, tabIds: [activeTabId])
        cols.insert(newCol, at: cols.index(after: colIdx))

        columns[projectId] = cols
        // Focus follows expelled tab (activeTabId unchanged)
    }

    // MARK: - Overview Actions

    func toggleOverview() {
        guard let projectId = activeProjectId else { return }
        let cols = projectColumns(for: projectId)
        guard !cols.isEmpty else { return }

        if isOverviewMode {
            exitOverview(selecting: overviewHighlightedTabId)
        } else {
            isOverviewMode = true
            overviewHighlightedColumnId = activeColumn?.id
            overviewHighlightedTabId = activeTabId
        }
    }

    func exitOverview(selecting tabId: String?) {
        if let tabId {
            setActiveTab(tabId)
        }
        isOverviewMode = false
        overviewHighlightedColumnId = nil
        overviewHighlightedTabId = nil
    }

    func overviewHighlightLeft() {
        guard let projectId = activeProjectId else { return }
        let cols = projectColumns(for: projectId)
        guard let highlightId = overviewHighlightedColumnId,
              let idx = cols.firstIndex(where: { $0.id == highlightId }),
              idx > cols.startIndex else { return }
        let newCol = cols[cols.index(before: idx)]
        overviewHighlightedColumnId = newCol.id
        overviewHighlightedTabId = newCol.tabIds.first
    }

    func overviewHighlightRight() {
        guard let projectId = activeProjectId else { return }
        let cols = projectColumns(for: projectId)
        guard let highlightId = overviewHighlightedColumnId,
              let idx = cols.firstIndex(where: { $0.id == highlightId }) else { return }
        let next = cols.index(after: idx)
        guard next < cols.endIndex else { return }
        let newCol = cols[next]
        overviewHighlightedColumnId = newCol.id
        overviewHighlightedTabId = newCol.tabIds.first
    }

    func overviewHighlightUp() {
        guard let highlightedColId = overviewHighlightedColumnId,
              let projectId = activeProjectId,
              let col = projectColumns(for: projectId).first(where: { $0.id == highlightedColId }),
              let currentTab = overviewHighlightedTabId,
              let idx = col.tabIds.firstIndex(of: currentTab),
              idx > col.tabIds.startIndex else { return }
        overviewHighlightedTabId = col.tabIds[col.tabIds.index(before: idx)]
    }

    func overviewHighlightDown() {
        guard let highlightedColId = overviewHighlightedColumnId,
              let projectId = activeProjectId,
              let col = projectColumns(for: projectId).first(where: { $0.id == highlightedColId }),
              let currentTab = overviewHighlightedTabId,
              let idx = col.tabIds.firstIndex(of: currentTab) else { return }
        let next = col.tabIds.index(after: idx)
        guard next < col.tabIds.endIndex else { return }
        overviewHighlightedTabId = col.tabIds[next]
    }

    // MARK: - Tab Actions

    /// Create a new shell tab for a project.
    @discardableResult
    func openTab(projectId: String, command: String? = nil, label: String? = nil) -> AppTab {
        let tab = makeShellTab(projectId: projectId, command: command, label: label)
        insertTab(tab, for: projectId, after: nil)

        // Create a new single-tab column
        let column = Column(id: UUID().uuidString, tabIds: [tab.id])
        var projectCols = columns[projectId] ?? []
        projectCols.append(column)
        columns[projectId] = projectCols

        reindexTabs(for: projectId)
        setActiveTab(tab.id)
        activateTerminalFocusSoon()
        return tab
    }

    func splitActivePaneWithNewTab() {
        guard let projectId = activeProjectId else { return }

        guard let currentCol = activeColumn,
              let activeTabId else {
            _ = openTab(projectId: projectId)
            return
        }

        var cols = projectColumns(for: projectId)
        guard let colIdx = cols.firstIndex(where: { $0.id == currentCol.id }),
              let tabIdx = cols[colIdx].tabIds.firstIndex(of: activeTabId) else {
            _ = openTab(projectId: projectId)
            return
        }

        let tab = makeShellTab(projectId: projectId, command: nil, label: nil)
        insertTab(tab, for: projectId, after: activeTabId)
        cols[colIdx].tabIds.insert(tab.id, at: cols[colIdx].tabIds.index(after: tabIdx))
        columns[projectId] = cols

        reindexTabs(for: projectId)
        setActiveTab(tab.id)
        activateTerminalFocusSoon()
    }

    func splitActiveColumnWithNewTab() {
        guard let projectId = activeProjectId else { return }

        guard let currentCol = activeColumn,
              let anchorTabId = currentCol.tabIds.last else {
            _ = openTab(projectId: projectId)
            return
        }

        var cols = projectColumns(for: projectId)
        guard let colIdx = cols.firstIndex(where: { $0.id == currentCol.id }) else {
            _ = openTab(projectId: projectId)
            return
        }

        let tab = makeShellTab(projectId: projectId, command: nil, label: nil)
        insertTab(tab, for: projectId, after: anchorTabId)
        cols.insert(
            Column(id: UUID().uuidString, tabIds: [tab.id]),
            at: cols.index(after: colIdx)
        )
        columns[projectId] = cols

        reindexTabs(for: projectId)
        setActiveTab(tab.id)
        activateTerminalFocusSoon()
    }

    func openOrFocusCommandTab(
        projectId: String,
        command: String,
        label: String,
        fullWidth: Bool = false,
        maximizeColumn: Bool = false
    ) {
        if let existing = projectTabs(for: projectId).first(where: { $0.command == command }) {
            if fullWidth, !fullWidthTabIds.contains(existing.id) {
                // Existing tab found but not in full-width mode — make it full-width
                savedColumns[projectId] = columns[projectId] ?? []
                let column = Column(id: UUID().uuidString, tabIds: [existing.id])
                columns[projectId] = [column]
                fullWidthTabIds.insert(existing.id)
            }
            setActiveTab(existing.id)
            if maximizeColumn {
                requestColumnMaximize(existing.id)
            }
            activateTerminalFocusSoon()
        } else if fullWidth {
            openFullWidthTab(projectId: projectId, command: command, label: label)
        } else {
            let tab = openTab(projectId: projectId, command: command, label: label)
            if maximizeColumn {
                requestColumnMaximize(tab.id)
            }
        }
    }

    func openOrFocusCommandTabForActiveProject(
        command: String,
        label: String,
        fullWidth: Bool = false,
        maximizeColumn: Bool = false
    ) {
        guard let projectId = activeProjectId else { return }
        openOrFocusCommandTab(
            projectId: projectId,
            command: command,
            label: label,
            fullWidth: fullWidth,
            maximizeColumn: maximizeColumn
        )
    }

    func requestColumnMaximize(_ tabId: String) {
        pendingMaximizedTabId = tabId
    }

    func consumePendingColumnMaximize(for tabId: String) -> Bool {
        guard pendingMaximizedTabId == tabId else { return false }
        pendingMaximizedTabId = nil
        return true
    }

    func isFullWidthTab(_ tabId: String) -> Bool {
        fullWidthTabIds.contains(tabId)
    }

    // MARK: - Full Width Tabs

    /// Columns saved before a full-width tab replaced them, keyed by project ID.
    private var savedColumns: [String: [Column]] = [:]
    /// Tracks which tab triggered full-width mode per project, so we can restore on close.
    private var fullWidthTabIds: Set<String> = []

    /// Open a tab that replaces all columns, taking the full workspace width.
    /// The previous layout is saved and restored when the tab closes.
    private func openFullWidthTab(projectId: String, command: String, label: String) {
        let tab = AppTab(
            id: UUID().uuidString,
            type: "shell",
            label: label,
            defaultLabel: label,
            projectId: projectId,
            command: command
        )
        tabs.append(tab)

        // Save current columns and replace with just this tab
        savedColumns[projectId] = columns[projectId] ?? []
        let column = Column(id: UUID().uuidString, tabIds: [tab.id])
        columns[projectId] = [column]
        fullWidthTabIds.insert(tab.id)

        setActiveTab(tab.id)
    }

    /// Restore columns after a full-width tab closes. Called from closeTab.
    private func restoreColumnsIfNeeded(tabId: String, projectId: String) {
        guard fullWidthTabIds.remove(tabId) != nil,
              let saved = savedColumns.removeValue(forKey: projectId) else { return }
        columns[projectId] = saved
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
        guard let tab = tabsById[id] else { return }
        let projectId = tab.projectId

        // If this was a full-width tab, restore the saved layout and clean up
        if fullWidthTabIds.contains(id) {
            restoreColumnsIfNeeded(tabId: id, projectId: projectId)
            tabs.removeAll { $0.id == id }
            unreadTabs.remove(id)
            if lastActiveTab[projectId] == id { lastActiveTab[projectId] = nil }
            // Focus the previously active tab in the restored layout
            if activeTabId == id {
                let restoredCols = projectColumns(for: projectId)
                if let firstCol = restoredCols.first,
                   let fallback = columnFocusedTab[firstCol.id] ?? firstCol.tabIds.first {
                    setActiveTab(fallback)
                } else {
                    activeTabId = nil
                }
            }
            return
        }

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
                    if sidebarVisible { sidebarFocused = true }
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

    private func makeShellTab(projectId: String, command: String?, label: String?) -> AppTab {
        let count = projectTabs(for: projectId).count + 1
        let defaultLabel = label ?? "Terminal \(count)"
        return AppTab(
            id: UUID().uuidString,
            type: "shell",
            label: defaultLabel,
            defaultLabel: defaultLabel,
            projectId: projectId,
            command: command
        )
    }

    private func insertTab(_ tab: AppTab, for projectId: String, after anchorTabId: String?) {
        guard let anchorTabId,
              let anchorIndex = tabs.firstIndex(where: { $0.id == anchorTabId }) else {
            if let projectLastIndex = tabs.lastIndex(where: { $0.projectId == projectId }) {
                tabs.insert(tab, at: tabs.index(after: projectLastIndex))
            } else {
                tabs.append(tab)
            }
            return
        }

        tabs.insert(tab, at: tabs.index(after: anchorIndex))
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

    private static func loadColumns() -> [String: [Column]] {
        guard let data = UserDefaults.standard.data(forKey: StorageKeys.columns),
              let columns = try? JSONDecoder().decode([String: [Column]].self, from: data) else {
            return [:]
        }
        return columns
    }

    private static func saveColumns(_ columns: [String: [Column]]) {
        if let data = try? JSONEncoder().encode(columns) {
            UserDefaults.standard.set(data, forKey: StorageKeys.columns)
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

// MARK: - NSImage Gaussian Blur

extension NSImage {
    /// Returns a new NSImage with a Gaussian blur applied via CoreImage.
    func blurredCopy(radius: Double) -> NSImage? {
        guard radius > 0 else { return self }
        guard let tiffData = tiffRepresentation,
              let ciImage = CIImage(data: tiffData) else {
            return nil
        }

        let filter = CIFilter(name: "CIGaussianBlur")!
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)

        guard let output = filter.outputImage else { return nil }

        // CIGaussianBlur expands the image extent — crop back to original
        let cropped = output.cropped(to: ciImage.extent)

        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(cropped, from: ciImage.extent) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: size)
    }
}
