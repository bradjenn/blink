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
    static let projectSetups = "blink.projectSetups"
    static let fontFamily = "blink.fontFamily"
    static let uiFontFamily = "blink.uiFontFamily"
    static let fontSize = "blink.fontSize"
    static let cursorStyle = "blink.cursorStyle"
    static let shell = "blink.shell"
    static let focusCenteringMode = "blink.focusCenteringMode"
    static let spotifyEnabled = "blink.spotifyEnabled"
    static let fileEditorLauncher = "blink.fileEditorLauncher"
    static let fileEditorCustomCommand = "blink.fileEditorCustomCommand"
}

@MainActor @Observable
final class AppStore {
    // Projects
    var projects: [Project] {
        didSet { Self.saveProjects(projects) }
    }
    var projectSetups: [String: ProjectSetup] {
        didSet { Self.saveProjectSetups(projectSetups) }
    }
    var activeProjectId: String?
    var lastSelectedProjectId: String? {
        didSet { UserDefaults.standard.set(lastSelectedProjectId, forKey: StorageKeys.lastSelectedProjectId) }
    }

    // Tabs
    var tabs: [AppTab] = [] {
        didSet { autosaveProjectSessionsIfNeeded() }
    }
    var activeTabId: String?
    var pendingMaximizedTabId: String?
    var managedCommandStates: [String: ManagedCommandState] = [:]
    var claudeTabActivities: [String: ClaudeTabActivity] = [:]
    var shellDetectedAIPaneKinds: [String: ShellDetectedAIPaneKind] = [:]
    private var pendingTmuxShellCommands: [String: String] = [:]
    private var aiTabsAwaitingInitialPromptTitle: [String: ShellDetectedAIPaneKind] = [:]
    private var tmuxForegroundCommandPollTask: Task<Void, Never>?

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
        didSet {
            Self.saveColumns(columns)
            autosaveProjectSessionsIfNeeded()
        }
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
    var fileEditorLauncher: FileEditorLauncher {
        didSet { UserDefaults.standard.set(fileEditorLauncher.rawValue, forKey: StorageKeys.fileEditorLauncher) }
    }
    var fileEditorCustomCommand: String {
        didSet { UserDefaults.standard.set(fileEditorCustomCommand, forKey: StorageKeys.fileEditorCustomCommand) }
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
    var expandedProjectIds: Set<String> = []
    var sidebarFocused: Bool = false
    var surfaceManager: SurfaceManager?
    var browserManager: BrowserManager?
    private var sidebarFocusProtectionDeadline: Date?
    private var pendingSidebarFocusOnReveal = false

    private var lastActiveTab: [String: String] {
        didSet { Self.saveDictionary(lastActiveTab, forKey: StorageKeys.lastActiveTabs) }
    }
    private var workspaceViewportOffsets: [String: Double] {
        didSet { Self.saveDictionary(workspaceViewportOffsets, forKey: StorageKeys.workspaceViewportOffsets) }
    }
    @ObservationIgnored
    private let tmuxIntegrationEnabled: Bool
    @ObservationIgnored
    private let tmuxSocketName: String
    @ObservationIgnored
    private var claudeHookReceiver: ClaudeHookReceiver?
    @ObservationIgnored
    private var claudeHookScriptDirectoryPath: String?
    @ObservationIgnored
    private var claudeHookShellIntegrationDirectoryPath: String?
    @ObservationIgnored
    var detachedShellCommandHandler: ((String) -> Void)?
    private var suppressProjectSessionAutosave = true

    func focusTerminal() {
        sidebarFocused = false
        guard let tabId = activeTabId,
              let tab = tabsById[tabId] else { return }

        switch tab.kind {
        case .terminal:
            surfaceManager?.surface(for: tabId)?.focus()
        case .browser:
            browserManager?.focusWebView(tabId: tabId)
        case .chat:
            break
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
        self.tmuxIntegrationEnabled = Self.detectTmuxAvailability()
        self.tmuxSocketName = Self.tmuxSocketName()

        self.projects = loadedProjects
        self.projectSetups = Self.loadProjectSetups()
        self.theme = defaults.string(forKey: StorageKeys.theme) ?? "Josean"
        self.backgroundImage = defaults.string(forKey: StorageKeys.backgroundImage)
        self.hideTitleBar = defaults.object(forKey: StorageKeys.hideTitleBar) as? Bool ?? false
        self.sidebarVisible = defaults.object(forKey: StorageKeys.sidebarVisible) as? Bool ?? true
        self.expandedProjectIds = Set(loadedProjects.map(\.id))
        self.fontFamily = defaults.string(forKey: StorageKeys.fontFamily) ?? "MesloLGS Nerd Font Mono"
        self.uiFontFamily = defaults.string(forKey: StorageKeys.uiFontFamily) ?? "MesloLGS Nerd Font Mono"
        self.fontSize = defaults.object(forKey: StorageKeys.fontSize) != nil
            ? defaults.double(forKey: StorageKeys.fontSize) : 19
        self.cursorStyle = CursorStyle(rawValue: defaults.string(forKey: StorageKeys.cursorStyle) ?? "") ?? .block
        self.shell = defaults.string(forKey: StorageKeys.shell) ?? Self.defaultShell
        self.spotifyEnabled = defaults.object(forKey: StorageKeys.spotifyEnabled) as? Bool ?? false
        self.fileEditorLauncher = FileEditorLauncher(
            rawValue: defaults.string(forKey: StorageKeys.fileEditorLauncher) ?? ""
        ) ?? .blinkNeovim
        self.fileEditorCustomCommand = defaults.string(forKey: StorageKeys.fileEditorCustomCommand) ?? "open {path}"
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
        claudeHookReceiver = ClaudeHookReceiver(
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "com.blink.app"
        ) { [weak self] event in
            self?.handleClaudeHookEvent(event)
        }
        claudeHookScriptDirectoryPath = ClaudeHookScriptInstaller.install(
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "com.blink.app"
        )?.path
        claudeHookShellIntegrationDirectoryPath = ClaudeHookScriptInstaller.installShellIntegration(
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "com.blink.app"
        )?.path
        suppressProjectSessionAutosave = false
        startTmuxForegroundCommandPolling()
    }

    var claudeHookEventDirectoryPath: String? {
        claudeHookReceiver?.eventDirectoryURL.path
    }

    var claudeHookScriptPath: String? {
        claudeHookScriptDirectoryPath
    }

    var claudeHookShellIntegrationPath: String? {
        claudeHookShellIntegrationDirectoryPath
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

    func isProjectExpanded(_ id: String) -> Bool {
        expandedProjectIds.contains(id)
    }

    func expandProject(_ id: String) {
        expandedProjectIds.insert(id)
    }

    func collapseProject(_ id: String) {
        expandedProjectIds.remove(id)
    }

    func toggleProjectExpansion(_ id: String) {
        if isProjectExpanded(id) {
            collapseProject(id)
        } else {
            expandProject(id)
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
        guard let projectId = activeProjectId,
              let tabId = resolvedSelectableTabId(for: projectId, preferred: [activeTabId].compactMap { $0 }) else {
            return nil
        }
        return projectColumns(for: projectId).first { $0.tabIds.contains(tabId) }
    }

    /// Returns tabs in column-major order: left-to-right columns, top-to-bottom within each.
    func orderedTabs(for projectId: String) -> [AppTab] {
        let cols = projectColumns(for: projectId)
        let lookup = tabsById
        return cols.flatMap { col in
            col.tabIds.compactMap { lookup[$0] }
        }
    }

    func projectSetup(for projectId: String) -> ProjectSetup? {
        projectSetups[projectId]
    }

    func hasProjectSetup(for projectId: String) -> Bool {
        projectSetups[projectId] != nil
    }

    func projectSetupDisplayPath(for tab: AppTab, project: Project) -> String {
        let path = tab.workingDirectory ?? project.path
        return path.replacing("/Users/\(NSUserName())", with: "~")
    }

    func managedCommandState(for tabId: String) -> ManagedCommandState? {
        managedCommandStates[tabId]
    }

    func managedCommandStatus(for tabId: String) -> ManagedCommandStatus? {
        managedCommandStates[tabId]?.status
    }

    func isManagedCommandStopped(_ tabId: String) -> Bool {
        managedCommandStates[tabId]?.status == .stopped
    }

    @discardableResult
    func handleProcessExit(for tabId: String) -> Bool {
        guard let tab = tabsById[tabId], tab.isManagedCommand else {
            return false
        }

        managedCommandStates[tabId] = ManagedCommandState(status: .stopped)
        return true
    }

    func restartManagedCommandTab(_ tabId: String, focusAfterLaunch: Bool = false) {
        guard let tab = tabsById[tabId], tab.isManagedCommand else { return }

        surfaceManager?.destroySurface(tabId: tabId)
        managedCommandStates[tabId] = ManagedCommandState(status: .running)

        if focusAfterLaunch {
            setActiveTab(tabId)
            activateTerminalFocusSoon()
        }
    }

    func handleTerminalTitleUpdate(_ title: String, for tabId: String) {
        guard let tab = tabsById[tabId] else { return }

        defer { markUnread(tabId) }

        guard !tab.isManagedCommand else { return }

        if let displayName = TabTitleFilter.displayName(for: title) {
            if let aiKind = shellDetectedAIKind(forDisplayName: displayName) {
                shellDetectedAIPaneKinds[tabId] = aiKind
            }
            if displayName == ShellDetectedAIPaneKind.claude.displayName,
               claudeTabActivities[tabId]?.kind != .needsInput {
                claudeTabActivities[tabId] = ClaudeTabActivity(
                    kind: .running,
                    summary: nil,
                    updatedAt: .now
                )
            }
            if !shouldPreserveCustomAITitle(for: tab, displayName: displayName) {
                setTabTitle(tabId, title: displayName)
            }
        } else if TabTitleFilter.isShellPrompt(title) {
            if sendPendingTmuxShellCommandIfNeeded(for: tabId) {
                return
            }
            if shouldPreserveShellDetectedAIState(for: tabId, tab: tab) {
                return
            }
            aiTabsAwaitingInitialPromptTitle[tabId] = nil
            shellDetectedAIPaneKinds[tabId] = nil
            if claudeTabActivities[tabId] != nil {
                claudeTabActivities[tabId] = nil
            }
            revertTabTitle(tabId)
        }
    }

    func handleTerminalLineSubmission(_ line: String, for tabId: String) {
        guard let tab = tabsById[tabId], tab.isShell, !tab.isManagedCommand else { return }
        if let aiKind = ShellDetectedAIPaneKind(submittedLine: line) {
            shellDetectedAIPaneKinds[tabId] = aiKind
            aiTabsAwaitingInitialPromptTitle[tabId] = aiKind

            if aiKind == .claude, claudeTabActivities[tabId]?.kind != .needsInput {
                claudeTabActivities[tabId] = ClaudeTabActivity(
                    kind: .running,
                    summary: nil,
                    updatedAt: .now
                )
            }
            if !shouldPreserveCustomAITitle(for: tab, displayName: aiKind.displayName) {
                setTabTitle(tabId, title: aiKind.displayName)
            }
            return
        }

        guard let aiKind = aiTabsAwaitingInitialPromptTitle[tabId],
              tabsById[tabId] != nil else {
            aiTabsAwaitingInitialPromptTitle[tabId] = nil
            return
        }

        let trimmedPrompt = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }

        setTabTitle(tabId, title: aiPromptTitle(from: trimmedPrompt, fallback: aiKind.displayName))
        aiTabsAwaitingInitialPromptTitle[tabId] = nil
    }

    func terminalLaunchCommand(for tab: AppTab, project: Project) -> String? {
        if tab.isShell, tab.command == nil, tab.projectSetupPaneId != nil, tmuxIntegrationEnabled {
            return tmuxAttachCommand(
                project: project,
                tab: tab,
                workingDirectory: tab.workingDirectory ?? project.path
            )
        }

        return tab.command
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
            activeTabId = resolvedSelectableTabId(
                for: id,
                preferred: [lastActiveTab[id]].compactMap { $0 }
            )
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
            if hasProjectSetup(for: id) {
                restoreProjectSetup(for: id)
            } else {
                _ = openTab(projectId: id)
            }
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
        guard let tab = tabsById[id] else { return }
        if activeProjectId != tab.projectId {
            setActiveProject(tab.projectId)
        }

        expandProject(tab.projectId)
        let resolvedTabId = resolvedSelectableTabId(for: tab.projectId, preferred: [id]) ?? id
        activeTabId = resolvedTabId
        lastActiveTab[tab.projectId] = resolvedTabId
        clearUnread(resolvedTabId)
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
        if nextIndex < ordered.endIndex {
            setActiveTab(ordered[nextIndex].id)
        } else {
            setActiveTab(ordered[ordered.startIndex].id)
        }
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

        if currentIndex > ordered.startIndex {
            setActiveTab(ordered[ordered.index(before: currentIndex)].id)
        } else {
            setActiveTab(ordered[ordered.index(before: ordered.endIndex)].id)
        }
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
            focusTerminal()
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
            if tabsById[tabId] != nil {
                setActiveTab(tabId)
            } else if let projectId = activeProjectId,
                      let column = projectColumns(for: projectId).first(where: { $0.id == tabId }),
                      let fallback = column.tabIds.first {
                setActiveTab(fallback)
            }
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
    func openTab(
        projectId: String,
        command: String? = nil,
        label: String? = nil,
        workingDirectory: String? = nil,
        role: String? = nil,
        projectSetupPaneId: String? = nil
    ) -> AppTab {
        let tab = makeShellTab(
            projectId: projectId,
            command: command,
            label: label,
            workingDirectory: workingDirectory,
            role: role,
            projectSetupPaneId: projectSetupPaneId
        )
        registerManagedCommandStateIfNeeded(for: tab)
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

    @discardableResult
    func openBrowserTab(
        projectId: String,
        url: String? = nil,
        maximizeColumn: Bool = false,
        projectSetupPaneId: String? = nil,
        browserState: BrowserTabState? = nil
    ) -> AppTab {
        let tab = makeBrowserTab(
            projectId: projectId,
            url: url,
            projectSetupPaneId: projectSetupPaneId,
            browserState: browserState
        )
        insertTab(tab, for: projectId, after: nil)

        let column = Column(id: UUID().uuidString, tabIds: [tab.id])
        var projectCols = columns[projectId] ?? []
        projectCols.append(column)
        columns[projectId] = projectCols

        reindexTabs(for: projectId)
        setActiveTab(tab.id)
        if maximizeColumn {
            requestColumnMaximize(tab.id)
        }
        sidebarFocused = false
        return tab
    }

    @discardableResult
    func openBrowserTabForActiveProject(
        url: String? = nil,
        maximizeColumn: Bool = false
    ) -> AppTab? {
        guard let projectId = activeProjectId else { return nil }
        return openBrowserTab(projectId: projectId, url: url, maximizeColumn: maximizeColumn)
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

    @discardableResult
    func openOrFocusCommandTab(
        projectId: String,
        command: String,
        label: String,
        workingDirectory: String? = nil,
        role: String? = nil,
        projectSetupPaneId: String? = nil,
        fullWidth: Bool = false,
        maximizeColumn: Bool = false
    ) -> AppTab {
        if let existing = projectTabs(for: projectId).first(where: {
            $0.command == command
                && effectiveWorkingDirectory($0.workingDirectory, projectId: projectId)
                    == effectiveWorkingDirectory(workingDirectory, projectId: projectId)
        }) {
            if existing.isManagedCommand && isManagedCommandStopped(existing.id) {
                restartManagedCommandTab(existing.id)
            } else if existing.isManagedCommand {
                registerManagedCommandStateIfNeeded(for: existing)
            }
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
            return tabsById[existing.id] ?? existing
        } else if fullWidth {
            return openFullWidthTab(
                projectId: projectId,
                command: command,
                label: label,
                workingDirectory: workingDirectory,
                role: role,
                projectSetupPaneId: projectSetupPaneId
            )
        } else {
            let tab = openTab(
                projectId: projectId,
                command: command,
                label: label,
                workingDirectory: workingDirectory,
                role: role,
                projectSetupPaneId: projectSetupPaneId
            )
            if maximizeColumn {
                requestColumnMaximize(tab.id)
            }
            return tab
        }
    }

    @discardableResult
    func openOrFocusBrowserTab(projectId: String, url: String) -> AppTab {
        let resolvedURLString = BrowserURLResolver.resolve(url)?.absoluteString ?? url

        if let existing = projectTabs(for: projectId).first(where: {
            $0.isBrowser && $0.browserState?.urlString == resolvedURLString
        }) {
            setActiveTab(existing.id)
            focusTerminal()
            return tabsById[existing.id] ?? existing
        }

        return openBrowserTab(projectId: projectId, url: resolvedURLString)
    }

    @discardableResult
    func openOrFocusBrowserTabForActiveProject(url: String) -> AppTab? {
        guard let projectId = activeProjectId else { return nil }
        return openOrFocusBrowserTab(projectId: projectId, url: url)
    }

    @discardableResult
    func openOrFocusCommandTabForActiveProject(
        command: String,
        label: String,
        workingDirectory: String? = nil,
        role: String? = nil,
        projectSetupPaneId: String? = nil,
        fullWidth: Bool = false,
        maximizeColumn: Bool = false
    ) -> AppTab? {
        guard let projectId = activeProjectId else { return nil }
        return openOrFocusCommandTab(
            projectId: projectId,
            command: command,
            label: label,
            workingDirectory: workingDirectory,
            role: role,
            projectSetupPaneId: projectSetupPaneId,
            fullWidth: fullWidth,
            maximizeColumn: maximizeColumn
        )
    }

    func openFileInEditor(
        projectId: String,
        path: String,
        line: Int? = nil,
        column: Int? = nil
    ) {
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let resolvedPath = resolveExistingProjectFilePath(
            normalizedPath,
            projectId: projectId
        ) ?? normalizedPath

        guard fileEditorLauncher.opensInsideBlink else {
            runDetachedShellCommand(
                fileEditorLauncher.command(
                    path: resolvedPath,
                    line: line,
                    column: column,
                    customTemplate: fileEditorCustomCommand
                )
            )
            return
        }

        if focusExistingTmuxEditorTab(
            projectId: projectId,
            path: resolvedPath,
            line: line,
            column: column
        ) {
            return
        }

        if tmuxIntegrationEnabled {
            openFileInNewTmuxEditorTab(
                projectId: projectId,
                path: resolvedPath,
                line: line,
                column: column
            )
            return
        }

        let label = URL(fileURLWithPath: resolvedPath).lastPathComponent
        let command = fileEditorLauncher.command(
            path: resolvedPath,
            line: line,
            column: column,
            customTemplate: fileEditorCustomCommand
        )
        _ = openTab(projectId: projectId, command: command, label: label)
    }

    func openFileInEditorForActiveProject(
        path: String,
        line: Int? = nil,
        column: Int? = nil
    ) {
        guard let projectId = activeProjectId else { return }
        openFileInEditor(projectId: projectId, path: path, line: line, column: column)
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
    @discardableResult
    private func openFullWidthTab(
        projectId: String,
        command: String,
        label: String,
        workingDirectory: String? = nil,
        role: String? = nil,
        projectSetupPaneId: String? = nil
    ) -> AppTab {
        let tab = AppTab(
            id: UUID().uuidString,
            kind: .terminal,
            label: label,
            defaultLabel: label,
            projectId: projectId,
            command: command,
            role: role,
            workingDirectory: workingDirectory,
            projectSetupPaneId: projectSetupPaneId
        )
        tabs.append(tab)
        registerManagedCommandStateIfNeeded(for: tab)

        // Save current columns and replace with just this tab
        savedColumns[projectId] = columns[projectId] ?? []
        let column = Column(id: UUID().uuidString, tabIds: [tab.id])
        columns[projectId] = [column]
        fullWidthTabIds.insert(tab.id)

        setActiveTab(tab.id)
        return tab
    }

    /// Restore columns after a full-width tab closes. Called from closeTab.
    private func restoreColumnsIfNeeded(tabId: String, projectId: String) {
        guard fullWidthTabIds.remove(tabId) != nil,
              let saved = savedColumns.removeValue(forKey: projectId) else { return }
        columns[projectId] = saved
    }

    /// Update a tab's title.
    func setTabTitle(_ tabId: String, title: String, updateDefaultLabel: Bool = false) {
        if let idx = tabs.firstIndex(where: { $0.id == tabId }) {
            tabs[idx].label = title
            if updateDefaultLabel {
                tabs[idx].defaultLabel = title
            }
        }
    }

    /// Revert a tab's title to its default name.
    func revertTabTitle(_ tabId: String) {
        if let idx = tabs.firstIndex(where: { $0.id == tabId }) {
            tabs[idx].label = tabs[idx].defaultLabel
        }
    }

    func updateBrowserState(_ state: BrowserTabState, for tabId: String) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        let nextLabel: String
        if let title = state.title, !title.isEmpty {
            nextLabel = title
        } else if let urlString = state.urlString,
                  let host = URL(string: urlString)?.host(percentEncoded: false),
                  !host.isEmpty {
            nextLabel = host
        } else {
            nextLabel = tabs[idx].defaultLabel
        }

        guard tabs[idx].browserState != state || tabs[idx].label != nextLabel else { return }

        tabs[idx].browserState = state
        tabs[idx].label = nextLabel
        markUnread(tabId)
    }

    func setBrowserFocusTarget(_ target: BrowserFocusTarget, for tabId: String) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabId }),
              var state = tabs[idx].browserState else { return }
        guard state.preferredFocus != target else { return }
        state.preferredFocus = target
        tabs[idx].browserState = state
    }

    func focusBrowserAddressBar() {
        guard let tabId = activeTabId,
              tabsById[tabId]?.isBrowser == true else { return }
        setBrowserFocusTarget(.addressBar, for: tabId)
        browserManager?.focusAddressBar(tabId: tabId)
    }

    func focusBrowserWebView() {
        guard let tabId = activeTabId,
              tabsById[tabId]?.isBrowser == true else { return }
        setBrowserFocusTarget(.webView, for: tabId)
        browserManager?.focusWebView(tabId: tabId)
    }

    func navigateActiveBrowserBack() {
        guard let tabId = activeTabId,
              tabsById[tabId]?.isBrowser == true else { return }
        browserManager?.goBack(tabId: tabId)
    }

    func navigateActiveBrowserForward() {
        guard let tabId = activeTabId,
              tabsById[tabId]?.isBrowser == true else { return }
        browserManager?.goForward(tabId: tabId)
    }

    func reloadActiveBrowser() {
        guard let tabId = activeTabId,
              tabsById[tabId]?.isBrowser == true else { return }
        browserManager?.reload(tabId: tabId)
    }

    func openActiveBrowserInDefaultBrowser() {
        guard let tabId = activeTabId,
              tabsById[tabId]?.isBrowser == true else { return }
        browserManager?.openInDefaultBrowser(tabId: tabId)
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

    func claudeActivity(for tabId: String) -> ClaudeTabActivity? {
        claudeTabActivities[tabId]
    }

    func claudeProjectActivity(for projectId: String) -> ClaudeTabActivity? {
        let activities = projectTabs(for: projectId)
            .compactMap { claudeTabActivities[$0.id] }

        if let needsInput = activities
            .filter({ $0.kind == .needsInput })
            .max(by: { $0.updatedAt < $1.updatedAt }) {
            return needsInput
        }

        if let running = activities
            .filter({ $0.kind == .running })
            .max(by: { $0.updatedAt < $1.updatedAt }) {
            return running
        }

        return activities
            .filter { $0.kind == .completed }
            .max(by: { $0.updatedAt < $1.updatedAt })
    }

    func projectTabs(for projectId: String) -> [AppTab] {
        tabs.filter { $0.projectId == projectId }
    }

    func terminalCount(for projectId: String) -> Int {
        tabs.filter { $0.projectId == projectId && $0.isShell }.count
    }

    private func handleClaudeHookEvent(_ event: ClaudeHookEvent) {
        let resolvedTabId: String? = {
            if let tab = tabsById[event.tabId], tab.projectId == event.projectId {
                return tab.id
            }
            if let paneId = event.paneId {
                return tabs.first {
                    $0.projectId == event.projectId && $0.projectSetupPaneId == paneId
                }?.id
            }
            return nil
        }()
        guard let resolvedTabId else { return }

        switch event.event.lowercased() {
        case "prompt-submit":
            shellDetectedAIPaneKinds[resolvedTabId] = .claude
            if let promptTitle = ClaudeHookSummary.promptTitle(rawInput: event.rawInput) {
                setTabTitle(resolvedTabId, title: promptTitle)
                aiTabsAwaitingInitialPromptTitle[resolvedTabId] = nil
            } else if let tab = tabsById[resolvedTabId],
                      !shouldPreserveCustomAITitle(for: tab, displayName: ShellDetectedAIPaneKind.claude.displayName) {
                setTabTitle(resolvedTabId, title: ShellDetectedAIPaneKind.claude.displayName)
            }
            claudeTabActivities[resolvedTabId] = ClaudeTabActivity(
                kind: .running,
                summary: nil,
                updatedAt: .now
            )
        case "pre-tool-use":
            shellDetectedAIPaneKinds[resolvedTabId] = .claude
            if let tab = tabsById[resolvedTabId],
               !shouldPreserveCustomAITitle(for: tab, displayName: ShellDetectedAIPaneKind.claude.displayName) {
                setTabTitle(resolvedTabId, title: ShellDetectedAIPaneKind.claude.displayName)
            }
            claudeTabActivities[resolvedTabId] = ClaudeTabActivity(
                kind: .running,
                summary: nil,
                updatedAt: .now
            )
        case "notification", "notify":
            let summary = ClaudeHookSummary.notificationSummary(rawInput: event.rawInput)
            shellDetectedAIPaneKinds[resolvedTabId] = .claude
            if let tab = tabsById[resolvedTabId],
               !shouldPreserveCustomAITitle(for: tab, displayName: ShellDetectedAIPaneKind.claude.displayName) {
                setTabTitle(resolvedTabId, title: ShellDetectedAIPaneKind.claude.displayName)
            }
            claudeTabActivities[resolvedTabId] = ClaudeTabActivity(
                kind: .needsInput,
                summary: summary.body,
                updatedAt: .now
            )
            markUnread(resolvedTabId)
        case "stop", "idle":
            let completionSummary = ClaudeHookSummary.completionSummary(
                from: ClaudeHookSummary.parse(rawInput: event.rawInput)
            )
            aiTabsAwaitingInitialPromptTitle[resolvedTabId] = nil
            shellDetectedAIPaneKinds[resolvedTabId] = nil
            claudeTabActivities[resolvedTabId] = ClaudeTabActivity(
                kind: .completed,
                summary: completionSummary?.body,
                updatedAt: .now
            )
            markUnread(resolvedTabId)
        case "session-end":
            let completionSummary = ClaudeHookSummary.completionSummary(
                from: ClaudeHookSummary.parse(rawInput: event.rawInput)
            )
            aiTabsAwaitingInitialPromptTitle[resolvedTabId] = nil
            shellDetectedAIPaneKinds[resolvedTabId] = nil
            claudeTabActivities[resolvedTabId] = ClaudeTabActivity(
                kind: .completed,
                summary: completionSummary?.body,
                updatedAt: .now
            )
            markUnread(resolvedTabId)
        default:
            break
        }
    }

#if DEBUG
    func handleClaudeHookEventForTesting(
        event: String,
        projectId: String,
        tabId: String,
        rawInput: String,
        paneId: String? = nil
    ) {
        handleClaudeHookEvent(ClaudeHookEvent(
            event: event,
            projectId: projectId,
            tabId: tabId,
            paneId: paneId,
            projectPath: nil,
            cwd: nil,
            pid: nil,
            rawInput: rawInput
        ))
    }
#endif

    func removeProject(_ id: String) {
        let tabIds = tabs.filter { $0.projectId == id }.map(\.id)
        let paneIds = tabs.filter { $0.projectId == id }.compactMap(\.projectSetupPaneId)
        projects.removeAll { $0.id == id }
        projectSetups[id] = nil
        tabs.removeAll { $0.projectId == id }
        clearManagedCommandStates(for: tabIds)
        clearClaudeTabActivities(for: tabIds)
        clearPendingTmuxShellCommands(for: tabIds)
        unreadTabs.subtract(tabIds)
        lastActiveTab[id] = nil
        if activeProjectId == id {
            activeProjectId = nil
            activeTabId = nil
        }
        if lastSelectedProjectId == id {
            lastSelectedProjectId = nil
        }
        expandedProjectIds.remove(id)
        workspaceViewportOffsets[id] = nil

        // Clean up column state
        if let projectCols = columns[id] {
            for col in projectCols {
                columnFocusedTab[col.id] = nil
            }
        }
        columns[id] = nil

        let surfaceManager = surfaceManager
        browserManager?.destroyControllers(tabIds: tabIds)
        DispatchQueue.main.async {
            surfaceManager?.destroySurfaces(tabIds: tabIds)
        }
        destroyTmuxProjectSession(projectId: id, paneIds: paneIds)
    }

    func closeTab(_ id: String) {
        guard let tab = tabsById[id] else { return }
        let projectId = tab.projectId
        let paneId = tab.projectSetupPaneId

        // If this was a full-width tab, restore the saved layout and clean up
        if fullWidthTabIds.contains(id) {
            restoreColumnsIfNeeded(tabId: id, projectId: projectId)
            tabs.removeAll { $0.id == id }
            managedCommandStates[id] = nil
            claudeTabActivities[id] = nil
            clearPendingTmuxShellCommands(for: [id])
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
            if let paneId, shouldUseTmux(for: tab) {
                destroyTmuxPane(projectId: projectId, paneId: paneId)
            }
            switch tab.kind {
            case .terminal:
                surfaceManager?.destroySurface(tabId: id)
            case .browser:
                browserManager?.destroyController(tabId: id)
            case .chat:
                break
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
        managedCommandStates[id] = nil
        claudeTabActivities[id] = nil
        clearPendingTmuxShellCommands(for: [id])
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
        if tab.isBrowser {
            browserManager?.destroyController(tabId: id)
        }
        DispatchQueue.main.async {
            switch tab.kind {
            case .terminal:
                surfaceManager?.destroySurface(tabId: id)
            case .browser:
                break
            case .chat:
                break
            }
        }
        if let paneId, shouldUseTmux(for: tab) {
            destroyTmuxPane(projectId: projectId, paneId: paneId)
        }
    }

    func closeActiveTab() {
        guard let activeTabId else { return }
        closeTab(activeTabId)
    }

    func restoreProjectSetup(for projectId: String? = nil) {
        let targetProjectId = projectId ?? activeProjectId
        guard let targetProjectId,
              let setup = projectSetups[targetProjectId] else { return }

        replaceProjectSession(for: targetProjectId, using: setup)
        if activeProjectId == targetProjectId {
            setActiveProject(targetProjectId)
        }
    }

    private func replaceProjectSession(for projectId: String, using setup: ProjectSetup) {
        suppressProjectSessionAutosave = true
        defer {
            suppressProjectSessionAutosave = false
            autosaveProjectSessionsIfNeeded()
        }

        let existingTabIds = tabs.filter { $0.projectId == projectId }.map(\.id)
        tabs.removeAll { $0.projectId == projectId }
        clearManagedCommandStates(for: existingTabIds)
        clearClaudeTabActivities(for: existingTabIds)
        unreadTabs.subtract(existingTabIds)
        lastActiveTab[projectId] = nil
        workspaceViewportOffsets[projectId] = nil

        let resolvedSetup = normalizedProjectSetup(from: setup)
        let paneLookup = Dictionary(uniqueKeysWithValues: resolvedSetup.panes.map { ($0.id, $0) })
        var paneToTabId: [String: String] = [:]
        var rebuiltTabs: [AppTab] = []

        for column in resolvedSetup.columns {
            for paneId in column.paneIds {
                guard let pane = paneLookup[paneId] else { continue }
                let workingDirectory = resolvedWorkingDirectory(for: pane, projectId: projectId)
                let tab: AppTab
                switch pane.kind {
                case .shell:
                    tab = makeShellTab(
                        projectId: projectId,
                        command: nil,
                        label: pane.label,
                        workingDirectory: workingDirectory,
                        role: pane.role,
                        projectSetupPaneId: pane.id
                    )
                case .command:
                    tab = makeShellTab(
                        projectId: projectId,
                        command: pane.command,
                        label: pane.label,
                        workingDirectory: workingDirectory,
                        role: pane.role,
                        projectSetupPaneId: pane.id
                    )
                case .browser:
                    tab = makeBrowserTab(
                        projectId: projectId,
                        url: pane.browserState?.urlString,
                        projectSetupPaneId: pane.id,
                        browserState: pane.browserState
                    )
                case .chat:
                    continue
                }
                rebuiltTabs.append(tab)
                registerManagedCommandStateIfNeeded(for: tab)
                paneToTabId[pane.id] = tab.id
            }
        }

        tabs.append(contentsOf: rebuiltTabs)
        columns[projectId] = resolvedSetup.columns.compactMap { column in
            let tabIds = column.paneIds.compactMap { paneToTabId[$0] }
            guard !tabIds.isEmpty else { return nil }
            return Column(id: column.id, tabIds: tabIds)
        }
        reindexTabs(for: projectId)

        if let firstTabId = columns[projectId]?.first?.tabIds.first ?? rebuiltTabs.first?.id {
            lastActiveTab[projectId] = firstTabId
            if activeProjectId == projectId {
                activeTabId = firstTabId
            }
        }

        let surfaceManager = surfaceManager
        browserManager?.destroyControllers(tabIds: existingTabIds)
        DispatchQueue.main.async {
            surfaceManager?.destroySurfaces(tabIds: existingTabIds)
        }
    }

    private func currentProjectSetupSnapshot(for projectId: String) -> ProjectSetup? {
        let cols = projectColumns(for: projectId)
        guard !cols.isEmpty else { return nil }

        let lookup = tabsById
        var panes: [ProjectSetupPane] = []
        var tabIdToPaneId: [String: String] = [:]
        var nextPaneIndex = 0

        for column in cols {
            for tabId in column.tabIds {
                guard let tab = lookup[tabId] else { continue }
                let paneId = tab.projectSetupPaneId ?? "pane-\(nextPaneIndex)"
                nextPaneIndex += 1
                panes.append(
                    ProjectSetupPane(
                        id: paneId,
                        kind: projectSetupPaneKind(for: tab),
                        label: tab.label,
                        role: tab.role,
                        command: tab.command,
                        workingDirectory: normalizedWorkingDirectory(tab.workingDirectory, projectId: projectId),
                        browserState: tab.browserState
                    )
                )
                tabIdToPaneId[tabId] = paneId
            }
        }

        let setupColumns: [ProjectSetupColumn] = cols.enumerated().compactMap { entry in
            let (index, column) = entry
            let paneIds = column.tabIds.compactMap { tabIdToPaneId[$0] }
            guard !paneIds.isEmpty else { return nil }
            return ProjectSetupColumn(id: "col-\(index)", paneIds: paneIds)
        }

        guard !setupColumns.isEmpty else { return nil }
        return ProjectSetup(projectId: projectId, updatedAt: .now, columns: setupColumns, panes: panes)
    }

    private func autosaveProjectSessionsIfNeeded() {
        guard !suppressProjectSessionAutosave else { return }

        var nextProjectSetups = projectSetups
        var changed = false

        for project in projects {
            let snapshot = currentProjectSetupSnapshot(for: project.id)
            let normalizedSnapshot = snapshot.map(normalizedProjectSetup(from:))
            let normalizedExisting = projectSetups[project.id].map(normalizedProjectSetup(from:))

            // Keep the last known session when runtime state is temporarily empty,
            // such as during launch before panes are restored.
            if snapshot == nil {
                continue
            }

            if normalizedExisting == normalizedSnapshot {
                continue
            }

            changed = true
            if let snapshot {
                nextProjectSetups[project.id] = snapshot
            }
        }

        if changed {
            projectSetups = nextProjectSetups
        }
    }

    private func normalizedProjectSetup(from setup: ProjectSetup) -> ProjectSetup {
        let setup = Self.sanitizeLegacyChatPanes(in: setup)
        let paneLookup = Dictionary(uniqueKeysWithValues: setup.panes.map { ($0.id, $0) })
        var normalizedPanes: [ProjectSetupPane] = []
        var oldToNewPaneIds: [String: String] = [:]
        var nextPaneIndex = 0

        for column in setup.columns {
            for paneId in column.paneIds {
                guard let pane = paneLookup[paneId] else { continue }
                let normalizedId = "pane-\(nextPaneIndex)"
                nextPaneIndex += 1
                oldToNewPaneIds[paneId] = normalizedId
                normalizedPanes.append(
                    ProjectSetupPane(
                        id: normalizedId,
                        kind: pane.kind,
                        label: pane.label,
                        role: pane.role,
                        command: pane.command,
                        workingDirectory: normalizedWorkingDirectory(pane.workingDirectory, projectId: setup.projectId),
                        browserState: pane.browserState
                    )
                )
            }
        }

        let normalizedColumns: [ProjectSetupColumn] = setup.columns.enumerated().compactMap { entry in
            let (index, column) = entry
            let paneIds = column.paneIds.compactMap { oldToNewPaneIds[$0] }
            guard !paneIds.isEmpty else { return nil }
            return ProjectSetupColumn(id: "col-\(index)", paneIds: paneIds)
        }

        return ProjectSetup(
            projectId: setup.projectId,
            updatedAt: .distantPast,
            columns: normalizedColumns,
            panes: normalizedPanes
        )
    }

    private func normalizedWorkingDirectory(_ path: String?, projectId: String) -> String? {
        guard let path else { return nil }
        if let projectPath = projectPath(for: projectId), path == projectPath {
            return nil
        }
        return path
    }

    private func resolvedWorkingDirectory(for pane: ProjectSetupPane, projectId: String) -> String? {
        pane.workingDirectory ?? projectPath(for: projectId)
    }

    private func projectSetupPaneKind(for tab: AppTab) -> ProjectSetupPaneKind {
        switch tab.kind {
        case .terminal:
            return tab.command == nil ? .shell : .command
        case .browser:
            return .browser
        case .chat:
            return .chat
        }
    }

    private func projectPath(for projectId: String) -> String? {
        projects.first(where: { $0.id == projectId })?.path
    }

    private func effectiveWorkingDirectory(_ path: String?, projectId: String) -> String {
        path ?? projectPath(for: projectId) ?? ""
    }

    private func makeShellTab(
        projectId: String,
        command: String?,
        label: String?,
        workingDirectory: String? = nil,
        role: String? = nil,
        projectSetupPaneId: String? = nil
    ) -> AppTab {
        let count = tabs.filter { $0.projectId == projectId && $0.isShell && $0.command == nil }.count + 1
        let defaultLabel = command == nil ? "Terminal \(count)" : (label ?? "Terminal \(count)")
        let resolvedLabel = label ?? defaultLabel
        return AppTab(
            id: UUID().uuidString,
            kind: .terminal,
            label: resolvedLabel,
            defaultLabel: defaultLabel,
            projectId: projectId,
            command: command,
            role: role,
            workingDirectory: workingDirectory,
            projectSetupPaneId: projectSetupPaneId ?? makeProjectSetupPaneId()
        )
    }

    private func makeBrowserTab(
        projectId: String,
        url: String?,
        projectSetupPaneId: String? = nil,
        browserState: BrowserTabState? = nil
    ) -> AppTab {
        let resolvedURLString = url.flatMap { BrowserURLResolver.resolve($0)?.absoluteString ?? $0 }
        let count = tabs.filter { $0.projectId == projectId && $0.isBrowser }.count + 1
        let defaultLabel = browserState?.title ?? "Browser \(count)"
        let resolvedState = browserState ?? BrowserTabState(
            urlString: resolvedURLString,
            title: nil,
            canGoBack: false,
            canGoForward: false,
            isLoading: false,
            preferredFocus: resolvedURLString == nil ? .addressBar : .webView
        )

        return AppTab(
            id: UUID().uuidString,
            kind: .browser,
            label: resolvedState.title ?? defaultLabel,
            defaultLabel: defaultLabel,
            projectId: projectId,
            projectSetupPaneId: projectSetupPaneId ?? makeProjectSetupPaneId(),
            browserState: resolvedState
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

    private func registerManagedCommandStateIfNeeded(for tab: AppTab) {
        guard tab.isManagedCommand else { return }
        managedCommandStates[tab.id] = ManagedCommandState(status: .running)
    }

    private func clearManagedCommandStates(for tabIds: [String]) {
        for tabId in tabIds {
            managedCommandStates[tabId] = nil
        }
    }

    private func clearClaudeTabActivities(for tabIds: [String]) {
        for tabId in tabIds {
            claudeTabActivities[tabId] = nil
            aiTabsAwaitingInitialPromptTitle[tabId] = nil
            shellDetectedAIPaneKinds[tabId] = nil
        }
    }

    private func clearPendingTmuxShellCommands(for tabIds: [String]) {
        for tabId in tabIds {
            pendingTmuxShellCommands.removeValue(forKey: tabId)
        }
    }

    private func shouldUseTmux(for tab: AppTab) -> Bool {
        tmuxIntegrationEnabled && tab.isShell && tab.command == nil && tab.projectSetupPaneId != nil
    }

    private func isReusableTmuxEditorTab(_ tab: AppTab) -> Bool {
        guard shouldUseTmux(for: tab) else { return false }
        return tab.label == "Neovim" || tab.label == "Vim"
    }

    private func preferredTmuxEditorTab(for projectId: String) -> AppTab? {
        if let activeTabId,
           let activeTab = tabsById[activeTabId],
           activeTab.projectId == projectId,
           isReusableTmuxEditorTab(activeTab) {
            return activeTab
        }

        return projectTabs(for: projectId).first(where: isReusableTmuxEditorTab)
    }

    private func makeProjectSetupPaneId() -> String {
        UUID().uuidString.lowercased()
    }

    private func tmuxAttachCommand(project: Project, tab: AppTab, workingDirectory: String) -> String {
        guard let paneId = tab.projectSetupPaneId else { return "exec false" }
        let baseSession = tmuxBaseSessionName(for: project.id)
        let clientSession = tmuxClientSessionName(projectId: project.id, paneId: paneId)
        let windowName = tmuxWindowName(for: paneId)
        let tmuxPrefix = "env -u TMUX tmux -L \(shellQuote(tmuxSocketName))"
        let baseTarget = shellQuote(baseSession)
        let clientTarget = shellQuote(clientSession)
        let windowTarget = shellQuote(windowName)
        let sessionWindowTarget = shellQuote("\(clientSession):\(windowName)")
        let workingDirectoryArg = shellQuote(workingDirectory)
        let shellCommand = tmuxShellLaunchCommand(project: project, tab: tab)

        let ensureBaseSession = "\(tmuxPrefix) has-session -t \(baseTarget) 2>/dev/null || \(tmuxPrefix) new-session -d -s \(baseTarget) -n \(windowTarget) -c \(workingDirectoryArg) \(shellCommand)"
        let ensureWindow = "\(tmuxPrefix) list-windows -t \(baseTarget) -F '#{window_name}' 2>/dev/null | grep -Fqx -- \(windowTarget) || \(tmuxPrefix) new-window -d -t \(baseTarget) -n \(windowTarget) -c \(workingDirectoryArg) \(shellCommand)"
        let ensureClientSession = "\(tmuxPrefix) has-session -t \(clientTarget) 2>/dev/null || \(tmuxPrefix) new-session -d -t \(baseTarget) -s \(clientTarget)"
        let configureClient = "\(tmuxPrefix) set-option -t \(clientTarget) status off >/dev/null 2>&1; \(tmuxPrefix) set-option -t \(clientTarget) allow-rename off >/dev/null 2>&1"
        let selectWindow = "\(tmuxPrefix) select-window -t \(sessionWindowTarget) >/dev/null 2>&1"
        let attachClient = "exec env -u TMUX tmux -L \(shellQuote(tmuxSocketName)) attach-session -t \(clientTarget)"

        return [ensureBaseSession, ensureWindow, ensureClientSession, configureClient, selectWindow, attachClient]
            .joined(separator: "; ")
    }

    private func destroyTmuxPane(projectId: String, paneId: String) {
        guard tmuxIntegrationEnabled else { return }
        let baseSession = tmuxBaseSessionName(for: projectId)
        let clientSession = tmuxClientSessionName(projectId: projectId, paneId: paneId)
        let windowName = tmuxWindowName(for: paneId)

        runDetachedShellCommand("""
        env -u TMUX tmux -L \(shellQuote(tmuxSocketName)) kill-session -t \(shellQuote(clientSession)) >/dev/null 2>&1 || true
        env -u TMUX tmux -L \(shellQuote(tmuxSocketName)) kill-window -t \(shellQuote("\(baseSession):\(windowName)")) >/dev/null 2>&1 || true
        """)
    }

    private func destroyTmuxProjectSession(projectId: String, paneIds: [String]) {
        guard tmuxIntegrationEnabled else { return }
        let baseSession = tmuxBaseSessionName(for: projectId)
        let clientKills = paneIds.map {
            "env -u TMUX tmux -L \(shellQuote(tmuxSocketName)) kill-session -t \(shellQuote(tmuxClientSessionName(projectId: projectId, paneId: $0))) >/dev/null 2>&1 || true"
        }

        runDetachedShellCommand((clientKills + [
            "env -u TMUX tmux -L \(shellQuote(tmuxSocketName)) kill-session -t \(shellQuote(baseSession)) >/dev/null 2>&1 || true",
        ]).joined(separator: "\n"))
    }

    private func focusExistingTmuxEditorTab(
        projectId: String,
        path: String,
        line: Int?,
        column: Int?
    ) -> Bool {
        guard let tab = preferredTmuxEditorTab(for: projectId),
              let paneId = tab.projectSetupPaneId else {
            return false
        }

        let foregroundCommand = tmuxPaneCurrentCommand(projectId: projectId, paneId: paneId)
        let normalizedForegroundCommand = foregroundCommand?.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let shouldSendVimCommand: Bool
        if let normalizedForegroundCommand {
            shouldSendVimCommand = normalizedForegroundCommand == "nvim" || normalizedForegroundCommand == "vim"
        } else {
            shouldSendVimCommand = isReusableTmuxEditorTab(tab)
        }

        if shouldSendVimCommand {
            runDetachedShellCommand(tmuxSendKeysCommand(
                projectId: projectId,
                paneId: paneId,
                text: vimOpenCommand(path: path, line: line, column: column)
            ))
        } else {
            guard let project = projects.first(where: { $0.id == projectId }) else { return false }
            runDetachedShellCommand(tmuxSendShellCommand(
                tab: tab,
                project: project,
                workingDirectory: effectiveWorkingDirectory(tab.workingDirectory, projectId: projectId),
                text: NvimLauncher.command(path: path, line: line, column: column)
            ))
        }

        setActiveTab(tab.id)
        activateTerminalFocusSoon()
        return true
    }

    private func openFileInNewTmuxEditorTab(
        projectId: String,
        path: String,
        line: Int?,
        column: Int?
    ) {
        let workingDirectory = URL(fileURLWithPath: path)
            .deletingLastPathComponent()
            .path
        let tab = openTab(
            projectId: projectId,
            command: nil,
            label: "Neovim",
            workingDirectory: workingDirectory
        )

        pendingTmuxShellCommands[tab.id] = NvimLauncher.command(path: path, line: line, column: column)
    }

    private func runDetachedShellCommand(_ command: String) {
        if let detachedShellCommandHandler {
            detachedShellCommandHandler(command)
            return
        }

        let shellPath = "/bin/zsh"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: shellPath)
        task.arguments = ["-lc", command]
        try? task.run()
    }

    private func tmuxBaseSessionName(for projectId: String) -> String {
        "blink-\(projectId)"
    }

    private func tmuxClientSessionName(projectId: String, paneId: String) -> String {
        "blink-\(projectId)-\(paneId)"
    }

    private func tmuxWindowName(for paneId: String) -> String {
        "pane-\(paneId)"
    }

    private func tmuxWindowTarget(projectId: String, paneId: String) -> String {
        "\(tmuxBaseSessionName(for: projectId)):\(tmuxWindowName(for: paneId))"
    }

    private func tmuxShellLaunchCommand(project: Project, tab: AppTab) -> String {
        let shell = UserDefaults.standard.string(forKey: "blink.shell")
            ?? ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shellName = URL(fileURLWithPath: shell).lastPathComponent
        var assignments: [(String, String)] = [
            ("BLINK_TAB_ID", tab.id),
            ("BLINK_PANE_ID", tab.projectSetupPaneId ?? tab.id),
            ("BLINK_PROJECT_ID", project.id),
            ("BLINK_PROJECT_NAME", project.name),
            ("BLINK_PROJECT_PATH", project.path),
        ]

        if let hookEventDirectoryPath = claudeHookEventDirectoryPath, !hookEventDirectoryPath.isEmpty {
            assignments.append(("BLINK_HOOK_EVENT_DIR", hookEventDirectoryPath))
        }
        if let hookScriptDirectoryPath = claudeHookScriptPath, !hookScriptDirectoryPath.isEmpty {
            let wrapperPath = (hookScriptDirectoryPath as NSString).appendingPathComponent("claude")
            assignments.append(("BLINK_CLAUDE_WRAPPER_PATH", wrapperPath))
            let inheritedPATH = ProcessInfo.processInfo.environment["PATH"] ?? ""
            let prefixedPath: String
            if inheritedPATH.split(separator: ":").contains(Substring(hookScriptDirectoryPath)) {
                prefixedPath = inheritedPATH
            } else if inheritedPATH.isEmpty {
                prefixedPath = hookScriptDirectoryPath
            } else {
                prefixedPath = "\(hookScriptDirectoryPath):\(inheritedPATH)"
            }
            assignments.append(("PATH", prefixedPath))
        }
        if let hookShellIntegrationPath = claudeHookShellIntegrationPath, !hookShellIntegrationPath.isEmpty {
            assignments.append(("BLINK_SHELL_INTEGRATION", "1"))
            assignments.append(("BLINK_SHELL_INTEGRATION_DIR", hookShellIntegrationPath))
            if shellName == "zsh" {
                if let currentZdotdir = ProcessInfo.processInfo.environment["ZDOTDIR"], !currentZdotdir.isEmpty {
                    assignments.append(("BLINK_ZSH_ZDOTDIR", currentZdotdir))
                }
                assignments.append(("ZDOTDIR", hookShellIntegrationPath))
            }
        }

        let envAssignments = assignments
            .map { "\($0.0)=\(shellQuote($0.1))" }
            .joined(separator: " ")
        let envPrefix = envAssignments.isEmpty ? "" : "\(envAssignments) "
        return "env -u TMUX \(envPrefix)\(shellQuote(shell)) -l"
    }

    private func tmuxEnsureWindowCommand(tab: AppTab, project: Project, workingDirectory: String) -> String {
        guard let paneId = tab.projectSetupPaneId else { return "true" }
        let tmuxPrefix = "env -u TMUX tmux -L \(shellQuote(tmuxSocketName))"
        let baseSession = tmuxBaseSessionName(for: project.id)
        let windowName = tmuxWindowName(for: paneId)
        let baseTarget = shellQuote(baseSession)
        let windowTarget = shellQuote(windowName)
        let workingDirectoryArg = shellQuote(workingDirectory)
        let shellCommand = tmuxShellLaunchCommand(project: project, tab: tab)

        let ensureBaseSession = "\(tmuxPrefix) has-session -t \(baseTarget) 2>/dev/null || \(tmuxPrefix) new-session -d -s \(baseTarget) -n \(windowTarget) -c \(workingDirectoryArg) \(shellCommand)"
        let ensureWindow = "\(tmuxPrefix) list-windows -t \(baseTarget) -F '#{window_name}' 2>/dev/null | grep -Fqx -- \(windowTarget) || \(tmuxPrefix) new-window -d -t \(baseTarget) -n \(windowTarget) -c \(workingDirectoryArg) \(shellCommand)"

        return [ensureBaseSession, ensureWindow].joined(separator: "; ")
    }

    private static func tmuxSocketName() -> String {
        let bundleId = Bundle.main.bundleIdentifier ?? "com.blink.app"
        return bundleId.replacingOccurrences(of: ".", with: "-")
    }

    private static func detectTmuxAvailability() -> Bool {
        let candidates = [
            "/opt/homebrew/bin/tmux",
            "/usr/local/bin/tmux",
            "/usr/bin/tmux",
        ]

        return candidates.contains { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    private func runSynchronousShellCommand(_ command: String) -> String? {
        let shellPath = "/bin/zsh"
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: shellPath)
        task.arguments = ["-lc", command]
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
        } catch {
            return nil
        }

        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !output.isEmpty else {
            return nil
        }

        return output
    }

    private func resolveExistingProjectFilePath(_ path: String, projectId: String) -> String? {
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        guard !FileManager.default.fileExists(atPath: normalizedPath),
              let projectPath = projects.first(where: { $0.id == projectId })?.path else {
            return FileManager.default.fileExists(atPath: normalizedPath) ? normalizedPath : nil
        }

        let normalizedProjectPath = URL(fileURLWithPath: projectPath, isDirectory: true)
            .standardizedFileURL
            .path
        let relativeCandidates = candidateProjectPathSuffixes(
            for: normalizedPath,
            projectPath: normalizedProjectPath
        )

        for suffix in relativeCandidates {
            let matches = matchingProjectFiles(
                under: normalizedProjectPath,
                suffix: suffix
            )
            if matches.count == 1 {
                return matches[0]
            }
        }

        return nil
    }

    private func candidateProjectPathSuffixes(for path: String, projectPath: String) -> [String] {
        var candidates: [String] = []
        let normalizedProjectPrefix = projectPath.hasSuffix("/") ? projectPath : "\(projectPath)/"

        if path.hasPrefix(normalizedProjectPrefix) {
            let relativePath = String(path.dropFirst(normalizedProjectPrefix.count))
            if !relativePath.isEmpty {
                candidates.append(relativePath)
            }
        }

        let components = path.split(separator: "/").map(String.init)
        for suffixLength in stride(from: min(components.count, 4), through: 2, by: -1) {
            let suffix = components.suffix(suffixLength).joined(separator: "/")
            if !suffix.isEmpty, !candidates.contains(suffix) {
                candidates.append(suffix)
            }
        }

        return candidates
    }

    private func matchingProjectFiles(under projectPath: String, suffix: String) -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: projectPath, isDirectory: true),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var matches: [String] = []
        let normalizedSuffix = suffix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else {
                continue
            }

            let fullPath = fileURL.standardizedFileURL.path
            if fullPath.hasSuffix("/\(normalizedSuffix)") {
                matches.append(fullPath)
            }
        }

        return matches
    }

    func handleTerminalSurfaceReady(for tabId: String) {
        _ = sendPendingTmuxShellCommandIfNeeded(for: tabId)
        syncTmuxForegroundCommandIfNeeded(for: tabId)
    }

    private func tmuxPaneCurrentCommand(projectId: String, paneId: String) -> String? {
        let tmuxPrefix = "env -u TMUX tmux -L \(shellQuote(tmuxSocketName))"
        let target = shellQuote(tmuxWindowTarget(projectId: projectId, paneId: paneId))
        return runSynchronousShellCommand(
            "\(tmuxPrefix) display-message -p -t \(target) '#{pane_current_command}'"
        )
    }

    private func startTmuxForegroundCommandPolling() {
        tmuxForegroundCommandPollTask?.cancel()
        tmuxForegroundCommandPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(700))
                guard let self else { return }
                await self.pollTmuxForegroundCommandForActiveTab()
            }
        }
    }

    private func pollTmuxForegroundCommandForActiveTab() async {
        guard let activeTabId,
              let tab = tabsById[activeTabId],
              shouldUseTmux(for: tab),
              let paneId = tab.projectSetupPaneId else {
            return
        }

        let projectId = tab.projectId
        let resolvedCommand = await Self.fetchTmuxPaneCurrentCommand(
            projectId: projectId,
            paneId: paneId,
            socketName: Self.tmuxSocketName()
        )

        guard !Task.isCancelled,
              activeTabId == tab.id,
              tabsById[tab.id] != nil else {
            return
        }

        applyForegroundCommandTitle(resolvedCommand, for: tab.id)
    }

    private func syncTmuxForegroundCommandIfNeeded(for tabId: String) {
        guard let tab = tabsById[tabId],
              shouldUseTmux(for: tab),
              let paneId = tab.projectSetupPaneId else {
            return
        }

        let projectId = tab.projectId
        Task { [weak self] in
            guard let self else { return }
            let resolvedCommand = await Self.fetchTmuxPaneCurrentCommand(
                projectId: projectId,
                paneId: paneId,
                socketName: Self.tmuxSocketName()
            )

            await MainActor.run {
                guard self.tabsById[tabId] != nil else { return }
                self.applyForegroundCommandTitle(resolvedCommand, for: tabId)
            }
        }
    }

    private func applyForegroundCommandTitle(_ command: String?, for tabId: String) {
        guard let tab = tabsById[tabId] else { return }

        let normalizedCommand = command?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard let normalizedCommand, !normalizedCommand.isEmpty else { return }

        if let displayName = TabTitleFilter.displayName(for: normalizedCommand) {
            if let aiKind = ShellDetectedAIPaneKind(submittedLine: normalizedCommand) {
                shellDetectedAIPaneKinds[tabId] = aiKind
            }
            if displayName == ShellDetectedAIPaneKind.claude.displayName,
               claudeTabActivities[tabId]?.kind != .needsInput {
                claudeTabActivities[tabId] = ClaudeTabActivity(
                    kind: .running,
                    summary: nil,
                    updatedAt: .now
                )
            }
            if !shouldPreserveCustomAITitle(for: tab, displayName: displayName) {
                setTabTitle(tabId, title: displayName)
            }
            return
        }

        guard TabTitleFilter.isShellPrompt(normalizedCommand) else { return }

        if shouldPreserveShellDetectedAIState(for: tabId, tab: tab) {
            return
        }

        aiTabsAwaitingInitialPromptTitle[tabId] = nil
        shellDetectedAIPaneKinds[tabId] = nil
        if claudeTabActivities[tabId] != nil {
            claudeTabActivities[tabId] = nil
            if activeTabId != tabId {
                markUnread(tabId)
            }
        }

        if tab.label != tab.defaultLabel {
            revertTabTitle(tabId)
        }
    }

    private func shouldPreserveCustomAITitle(for tab: AppTab, displayName: String) -> Bool {
        return tab.label != tab.defaultLabel && tab.label != displayName
    }

    private func shouldPreserveShellDetectedAIState(for tabId: String, tab: AppTab) -> Bool {
        guard let aiKind = shellDetectedAIPaneKinds[tabId] else { return false }
        if aiTabsAwaitingInitialPromptTitle[tabId] == aiKind {
            return true
        }
        return shouldPreserveCustomAITitle(for: tab, displayName: aiKind.displayName)
    }

    private func resolvedSelectableTabId(for projectId: String, preferred: [String]) -> String? {
        let projectTabIds = Set(projectTabs(for: projectId).map(\.id))
        let projectCols = projectColumns(for: projectId)

        func selectable(_ tabId: String?) -> String? {
            guard let tabId,
                  projectTabIds.contains(tabId),
                  projectCols.contains(where: { $0.tabIds.contains(tabId) }) else {
                return nil
            }
            return tabId
        }

        for tabId in preferred {
            if let selectable = selectable(tabId) {
                return selectable
            }
        }

        if let remembered = selectable(lastActiveTab[projectId]) {
            return remembered
        }

        for column in projectCols {
            if let focused = selectable(columnFocusedTab[column.id]) {
                return focused
            }
        }

        return projectCols.first?.tabIds.first ?? projectTabs(for: projectId).first?.id
    }

    private func shellDetectedAIKind(forDisplayName displayName: String) -> ShellDetectedAIPaneKind? {
        ShellDetectedAIPaneKind.allCases.first { $0.displayName == displayName }
    }

    private func aiPromptTitle(from prompt: String, fallback: String) -> String {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return fallback }

        let firstLine = trimmedPrompt
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? trimmedPrompt

        let condensed = firstLine
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !condensed.isEmpty else { return fallback }
        if condensed.count <= 48 {
            return condensed
        }

        let truncated = condensed.prefix(45).trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(truncated)..."
    }

    nonisolated private static func fetchTmuxPaneCurrentCommand(
        projectId: String,
        paneId: String,
        socketName: String
    ) async -> String? {
        await Task.detached(priority: .utility) {
            let tmuxPrefix = "env -u TMUX tmux -L \(shellQuote(socketName))"
            let target = shellQuote("blink-\(projectId):pane-\(paneId)")
            return runSynchronousShellCommand(
                "\(tmuxPrefix) display-message -p -t \(target) '#{pane_current_command}'"
            )
        }.value
    }

    nonisolated private static func runSynchronousShellCommand(_ command: String) -> String? {
        let shellPath = "/bin/zsh"
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: shellPath)
        task.arguments = ["-lc", command]
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
        } catch {
            return nil
        }

        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !output.isEmpty else {
            return nil
        }

        return output
    }

    nonisolated private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    private func vimSingleQuoteEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    private func vimOpenCommand(path: String, line: Int?, column: Int?) -> String {
        let escapedPath = vimSingleQuoteEscape(path)
        var command = ":execute 'tab drop ' . fnameescape('\(escapedPath)')"

        if let line {
            let safeColumn = max(column ?? 1, 1)
            command += " | call cursor(\(line), \(safeColumn))"
        }

        return command
    }

    private func tmuxSendKeysCommand(projectId: String, paneId: String, text: String) -> String {
        let tmuxPrefix = "env -u TMUX tmux -L \(shellQuote(tmuxSocketName))"
        let target = shellQuote(tmuxWindowTarget(projectId: projectId, paneId: paneId))
        let literalText = shellQuote(text)

        return [
            "\(tmuxPrefix) send-keys -t \(target) Escape",
            "\(tmuxPrefix) send-keys -t \(target) -l \(literalText)",
            "\(tmuxPrefix) send-keys -t \(target) Enter",
        ].joined(separator: "; ")
    }

    private func tmuxSendShellCommand(
        tab: AppTab,
        project: Project,
        workingDirectory: String,
        text: String
    ) -> String {
        guard let paneId = tab.projectSetupPaneId else { return "true" }
        let tmuxPrefix = "env -u TMUX tmux -L \(shellQuote(tmuxSocketName))"
        let target = shellQuote(tmuxWindowTarget(projectId: project.id, paneId: paneId))
        let literalText = shellQuote(text)

        return [
            tmuxEnsureWindowCommand(tab: tab, project: project, workingDirectory: workingDirectory),
            "\(tmuxPrefix) send-keys -t \(target) -l \(literalText)",
            "\(tmuxPrefix) send-keys -t \(target) Enter",
        ].joined(separator: "; ")
    }

    @discardableResult
    private func sendPendingTmuxShellCommandIfNeeded(for tabId: String) -> Bool {
        guard let text = pendingTmuxShellCommands.removeValue(forKey: tabId),
              let tab = tabsById[tabId],
              let project = projects.first(where: { $0.id == tab.projectId }) else {
            return false
        }

        runDetachedShellCommand(tmuxSendShellCommand(
            tab: tab,
            project: project,
            workingDirectory: effectiveWorkingDirectory(tab.workingDirectory, projectId: tab.projectId),
            text: text
        ))
        return true
    }

    /// Re-number default tab labels ("Terminal 1", "Terminal 2", ...) for a project.
    private func reindexTabs(for projectId: String) {
        var counter = 0
        for i in tabs.indices where tabs[i].projectId == projectId && tabs[i].isShell && tabs[i].command == nil {
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
        expandedProjectIds.insert(project.id)
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

    private static func loadProjectSetups() -> [String: ProjectSetup] {
        guard let data = UserDefaults.standard.data(forKey: StorageKeys.projectSetups),
              let setups = try? JSONDecoder().decode([String: ProjectSetup].self, from: data) else {
            return [:]
        }
        return setups.reduce(into: [:]) { result, entry in
            let sanitized = sanitizeLegacyChatPanes(in: entry.value)
            guard !sanitized.columns.isEmpty, !sanitized.panes.isEmpty else { return }
            result[entry.key] = sanitized
        }
    }

    private static func saveProjectSetups(_ setups: [String: ProjectSetup]) {
        if let data = try? JSONEncoder().encode(setups) {
            UserDefaults.standard.set(data, forKey: StorageKeys.projectSetups)
        }
    }

    private static func sanitizeLegacyChatPanes(in setup: ProjectSetup) -> ProjectSetup {
        let allowedPaneIds = Set(
            setup.panes
                .filter { $0.kind != .chat }
                .map(\.id)
        )
        let panes = setup.panes.filter { allowedPaneIds.contains($0.id) }
        let columns: [ProjectSetupColumn] = setup.columns.compactMap { column in
            let paneIds = column.paneIds.filter { allowedPaneIds.contains($0) }
            guard !paneIds.isEmpty else { return nil }
            return ProjectSetupColumn(id: column.id, paneIds: paneIds)
        }
        return ProjectSetup(
            projectId: setup.projectId,
            updatedAt: setup.updatedAt,
            columns: columns,
            panes: panes
        )
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
