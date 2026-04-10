import SwiftUI
import AppKit
import CoreImage

enum ActiveView {
    case workspaces
    case settings
}

enum WorkspacePromptKind: Equatable {
    case rename
    case relink
}

struct WorkspacePromptState: Identifiable {
    let id = UUID()
    let workspaceId: String
    let kind: WorkspacePromptKind
    let initialValue: String
}

enum StorageKeys {
    static let profiles = "blink.profiles"
    static let theme = "blink.theme"
    static let backgroundImage = "blink.backgroundImage"
    static let backgroundOpacity = "blink.backgroundOpacity"
    static let backgroundBlur = "blink.backgroundBlur"
    static let hideTitleBar = "blink.hideTitleBar"
    static let sidebarVisible = "blink.sidebarVisible"
    static let workspaces = "blink.workspaces"
    static let lastSelectedWorkspaceId = "blink.lastSelectedWorkspaceId"
    static let lastActiveTabs = "blink.lastActiveTabs"
    static let workspaceViewportOffsets = "blink.workspaceViewportOffsets"
    static let columns = "blink.columns"
    static let workspaceSetups = "blink.workspaceSetups"
    static let legacyWorkspaces = "blink.projects"
    static let legacyLastSelectedWorkspaceId = "blink.lastSelectedProjectId"
    static let legacyWorkspaceSetups = "blink.projectSetups"
    static let fontFamily = "blink.fontFamily"
    static let uiFontFamily = "blink.uiFontFamily"
    static let fontSize = "blink.fontSize"
    static let cursorStyle = "blink.cursorStyle"
    static let cursorBlink = "blink.cursorBlink"
    static let shell = "blink.shell"
    static let focusCenteringMode = "blink.focusCenteringMode"
    static let spotifyEnabled = "blink.spotifyEnabled"
    static let fileEditorLauncher = "blink.fileEditorLauncher"
    static let fileEditorCustomCommand = "blink.fileEditorCustomCommand"
}

@MainActor @Observable
final class AppStore {
    var profiles: [Profile] {
        didSet { Self.saveProfiles(profiles) }
    }

    // Workspaces
    var workspaces: [Workspace] {
        didSet { Self.saveWorkspaces(workspaces) }
    }
    var workspaceSetups: [String: WorkspaceSetup] {
        didSet { Self.saveWorkspaceSetups(workspaceSetups) }
    }
    var activeWorkspaceId: String?
    var lastSelectedWorkspaceId: String? {
        didSet { UserDefaults.standard.set(lastSelectedWorkspaceId, forKey: StorageKeys.lastSelectedWorkspaceId) }
    }

    // Tabs
    var tabs: [AppTab] = [] {
        didSet { autosaveWorkspaceSessionsIfNeeded() }
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
            autosaveWorkspaceSessionsIfNeeded()
        }
    }
    var columnFocusedTab: [String: String] = [:]

    // Theme
    var theme: String {
        didSet {
            UserDefaults.standard.set(theme, forKey: StorageKeys.theme)
            _ = syncOpenCodeThemeConfiguration()
        }
    }

    // View
    var activeView: ActiveView = .workspaces
    var showThemePicker = false
    var showWorkspaceSwitcher = false
    var showWorkspaceOnboarding = false
    var showAISessionPicker = false
    var showNewTabMenu = false
    var showCommandPalette = false
    var workspacePrompt: WorkspacePromptState?
    var themePickerFocusRequest = 0
    var workspaceSwitcherFocusRequest = 0

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
    var cachedBlurredWallpaper: NSImage?

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
    var cursorBlink: Bool {
        didSet { UserDefaults.standard.set(cursorBlink, forKey: StorageKeys.cursorBlink) }
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
    var expandedWorkspaceIds: Set<String> = []
    var sidebarFocused: Bool = false
    var workspaceLandingFocused = false
    var surfaceManager: SurfaceManager?
    var browserManager: BrowserManager?
    var sidebarFocusProtectionDeadline: Date?
    var pendingSidebarFocusOnReveal = false

    var lastActiveTab: [String: String] {
        didSet { Self.saveDictionary(lastActiveTab, forKey: StorageKeys.lastActiveTabs) }
    }
    var workspaceViewportOffsets: [String: Double] {
        didSet { Self.saveDictionary(workspaceViewportOffsets, forKey: StorageKeys.workspaceViewportOffsets) }
    }
    @ObservationIgnored
    private let tmuxIntegrationEnabled: Bool
    @ObservationIgnored
    private let tmuxSocketName: String
    @ObservationIgnored
    private let tmuxConfigPath: String?
    @ObservationIgnored
    private var claudeHookReceiver: ClaudeHookReceiver?
    @ObservationIgnored
    private var claudeHookScriptDirectoryPath: String?
    @ObservationIgnored
    private var claudeHookShellIntegrationDirectoryPath: String?
    @ObservationIgnored
    var detachedShellCommandHandler: ((String) -> Void)?
    @ObservationIgnored
    var openCodeConfigHomeOverride: URL?
    @ObservationIgnored
    var openCodeSourceConfigHomeOverride: URL?
    private var suppressWorkspaceSessionAutosave = true

    func focusTerminal() {
        sidebarFocused = false
        workspaceLandingFocused = false

        if let workspaceId = activeWorkspaceId,
           let tabId = resolvedSelectableTabId(
                for: workspaceId,
                preferred: [activeTabId, lastActiveTab[workspaceId]].compactMap { $0 }
           ),
           let tab = tabsById[tabId] {
            if activeTabId != tabId {
                setActiveTab(tabId)
            }

            switch tab.kind {
            case .terminal:
                surfaceManager?.surface(for: tabId)?.focus()
            case .browser:
                browserManager?.focusWebView(tabId: tabId)
            case .chat:
                break
            }
            return
        }

        if let workspaceId = activeWorkspaceId,
           workspaceColumns(for: workspaceId).isEmpty {
            workspaceLandingFocused = true
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
        let rawWorkspaces = Self.loadWorkspaces()
        let loadedProfiles = Self.normalizedProfiles(
            Self.loadProfiles(),
            for: rawWorkspaces
        )
        let loadedWorkspaces = Self.normalizedWorkspaces(
            rawWorkspaces,
            availableProfileIds: Set(loadedProfiles.map(\.id))
        )
        let storedLastWorkspaceId = defaults.string(forKey: StorageKeys.lastSelectedWorkspaceId)
            ?? defaults.string(forKey: StorageKeys.legacyLastSelectedWorkspaceId)
        self.tmuxIntegrationEnabled = Self.detectTmuxAvailability()
        self.tmuxSocketName = Self.tmuxSocketName()
        self.tmuxConfigPath = Self.installBlinkTmuxConfig(
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "com.blink.app"
        )?.path

        self.profiles = loadedProfiles
        self.workspaces = loadedWorkspaces
        self.workspaceSetups = Self.loadWorkspaceSetups()
        self.theme = defaults.string(forKey: StorageKeys.theme) ?? "Josean"
        self.backgroundImage = defaults.string(forKey: StorageKeys.backgroundImage)
        self.hideTitleBar = defaults.object(forKey: StorageKeys.hideTitleBar) as? Bool ?? false
        self.sidebarVisible = defaults.object(forKey: StorageKeys.sidebarVisible) as? Bool ?? true
        self.expandedWorkspaceIds = Set(loadedWorkspaces.map(\.id))
        self.fontFamily = defaults.string(forKey: StorageKeys.fontFamily) ?? "MesloLGS Nerd Font Mono"
        self.uiFontFamily = defaults.string(forKey: StorageKeys.uiFontFamily) ?? "MesloLGS Nerd Font Mono"
        self.fontSize = defaults.object(forKey: StorageKeys.fontSize) != nil
            ? defaults.double(forKey: StorageKeys.fontSize) : 19
        self.cursorStyle = CursorStyle(rawValue: defaults.string(forKey: StorageKeys.cursorStyle) ?? "") ?? .block
        self.cursorBlink = defaults.object(forKey: StorageKeys.cursorBlink) as? Bool ?? true
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
        if let storedLastWorkspaceId,
           loadedWorkspaces.contains(where: { $0.id == storedLastWorkspaceId }) {
            self.lastSelectedWorkspaceId = storedLastWorkspaceId
        } else {
            self.lastSelectedWorkspaceId = nil
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
        Self.saveProfiles(loadedProfiles)
        Self.saveWorkspaces(loadedWorkspaces)
        sanitizePersistedWorkspaceState()
        suppressWorkspaceSessionAutosave = false
        startTmuxForegroundCommandPolling()
        _ = syncOpenCodeThemeConfiguration()
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

    // MARK: - Column Helpers

    func workspaceColumns(for workspaceId: String) -> [Column] {
        columns[workspaceId] ?? []
    }

    func columnFor(tabId: String) -> Column? {
        guard let tab = tabsById[tabId] else { return nil }
        return workspaceColumns(for: tab.workspaceId).first { $0.tabIds.contains(tabId) }
    }

    var activeColumn: Column? {
        guard let workspaceId = activeWorkspaceId,
              let tabId = resolvedSelectableTabId(for: workspaceId, preferred: [activeTabId].compactMap { $0 }) else {
            return nil
        }
        return workspaceColumns(for: workspaceId).first { $0.tabIds.contains(tabId) }
    }

    /// Returns tabs in column-major order: left-to-right columns, top-to-bottom within each.
    func orderedTabs(for workspaceId: String) -> [AppTab] {
        let cols = workspaceColumns(for: workspaceId)
        let lookup = tabsById
        return cols.flatMap { col in
            col.tabIds.compactMap { lookup[$0] }
        }
    }

    func workspaceSetup(for workspaceId: String) -> WorkspaceSetup? {
        workspaceSetups[workspaceId]
    }

    func hasWorkspaceSetup(for workspaceId: String) -> Bool {
        workspaceSetups[workspaceId] != nil
    }

    func workspaceSetupDisplayPath(for tab: AppTab, workspace: Workspace) -> String {
        let path = validatedWorkingDirectory(tab.workingDirectory, workspaceId: workspace.id)
        return path.replacing("/Users/\(NSUserName())", with: "~")
    }

    func resolvedWorkingDirectory(for tab: AppTab, workspace: Workspace) -> String {
        validatedWorkingDirectory(tab.workingDirectory, workspaceId: workspace.id)
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
        armManagedAITrackingIfNeeded(for: tab)

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
            let shouldPreserveAIState = shouldPreserveShellDetectedAIState(for: tabId, tab: tab)
            if shouldResetTerminalSubmittedLineTracking(
                for: tabId,
                preservingAIState: shouldPreserveAIState
            ) {
                resetTerminalSubmittedLineTracking(for: tabId)
            }
            if shouldPreserveAIState {
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
        guard let tab = tabsById[tabId], tab.isShell else { return }
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

        let promptTitle = aiPromptTitle(from: trimmedPrompt, fallback: aiKind.displayName)
        setTabTitle(tabId, title: promptTitle)
        aiTabsAwaitingInitialPromptTitle[tabId] = nil
    }

    func terminalLaunchCommand(for tab: AppTab, workspace: Workspace) -> String? {
        if tab.isShell, tab.command == nil, tab.workspaceSetupPaneId != nil, tmuxIntegrationEnabled {
            return tmuxAttachCommand(
                workspace: workspace,
                tab: tab,
                workingDirectory: validatedWorkingDirectory(tab.workingDirectory, workspaceId: workspace.id)
            )
        }

        if let command = tab.command,
           ShellDetectedAIPaneKind(submittedLine: command) == .opencode {
            return openCodeLaunchCommand(command)
        }

        return tab.command
    }

    private static let openCodeThemeSchemaURL = "https://opencode.ai/theme.json"
    private static let openCodeTUISchemaURL = "https://opencode.ai/tui.json"
    private static let blinkOpenCodeThemeName = "blink-current"

    private func openCodeLaunchCommand(_ command: String) -> String {
        guard let configHome = syncOpenCodeThemeConfiguration() else { return command }
        return "env XDG_CONFIG_HOME=\(shellQuote(configHome.path)) \(command)"
    }

    @discardableResult
    func syncOpenCodeThemeConfiguration() -> URL? {
        guard let terminalTheme = TerminalTheme.load(name: theme) else { return nil }

        let fileManager = FileManager.default
        let sourceConfigHome = openCodeSourceConfigHomeURL()
        let scopedConfigHome = openCodeConfigHomeURL()
        let sourceConfigDirectory = sourceConfigHome.appendingPathComponent("opencode", isDirectory: true)
        let scopedConfigDirectory = scopedConfigHome.appendingPathComponent("opencode", isDirectory: true)
        let scopedThemesDirectory = scopedConfigDirectory.appendingPathComponent("themes", isDirectory: true)

        do {
            try? fileManager.removeItem(at: scopedConfigDirectory)
            try fileManager.createDirectory(at: scopedConfigDirectory, withIntermediateDirectories: true)

            if fileManager.fileExists(atPath: sourceConfigDirectory.path) {
                let sourceItems = try fileManager.contentsOfDirectory(
                    at: sourceConfigDirectory,
                    includingPropertiesForKeys: nil
                )
                for item in sourceItems {
                    let itemName = item.lastPathComponent
                    guard itemName != "tui.json", itemName != "themes" else { continue }
                    try fileManager.createSymbolicLink(
                        at: scopedConfigDirectory.appendingPathComponent(itemName),
                        withDestinationURL: item
                    )
                }
            }

            try fileManager.createDirectory(at: scopedThemesDirectory, withIntermediateDirectories: true)

            let sourceThemesDirectory = sourceConfigDirectory.appendingPathComponent("themes", isDirectory: true)
            if fileManager.fileExists(atPath: sourceThemesDirectory.path) {
                let sourceThemes = try fileManager.contentsOfDirectory(
                    at: sourceThemesDirectory,
                    includingPropertiesForKeys: nil
                )
                for themeFile in sourceThemes {
                    try fileManager.createSymbolicLink(
                        at: scopedThemesDirectory.appendingPathComponent(themeFile.lastPathComponent),
                        withDestinationURL: themeFile
                    )
                }
            }

            let generatedThemeURL = scopedThemesDirectory
                .appendingPathComponent(Self.blinkOpenCodeThemeName)
                .appendingPathExtension("json")
            let generatedThemeData = try JSONSerialization.data(
                withJSONObject: openCodeThemeDocument(for: terminalTheme),
                options: [.prettyPrinted, .sortedKeys]
            )
            try generatedThemeData.write(to: generatedThemeURL, options: .atomic)

            var tuiDocument: [String: Any] = ["$schema": Self.openCodeTUISchemaURL]
            let sourceTUIURL = sourceConfigDirectory.appendingPathComponent("tui.json")
            if let sourceTUIData = try? Data(contentsOf: sourceTUIURL),
               let parsed = try? JSONSerialization.jsonObject(with: sourceTUIData) as? [String: Any] {
                tuiDocument = parsed
            }

            tuiDocument["$schema"] = tuiDocument["$schema"] ?? Self.openCodeTUISchemaURL
            tuiDocument["theme"] = Self.blinkOpenCodeThemeName

            let scopedTUIURL = scopedConfigDirectory.appendingPathComponent("tui.json")
            let scopedTUIData = try JSONSerialization.data(
                withJSONObject: tuiDocument,
                options: [.prettyPrinted, .sortedKeys]
            )
            try scopedTUIData.write(to: scopedTUIURL, options: .atomic)

            return scopedConfigHome
        } catch {
            print("[AppStore] Failed to sync OpenCode theme config: \(error)")
            return nil
        }
    }

    private func openCodeThemeDocument(for terminalTheme: TerminalTheme) -> [String: Any] {
        func paletteColor(_ index: Int, fallback: String) -> String {
            guard terminalTheme.palette.indices.contains(index) else { return fallback }
            return terminalTheme.palette[index]
        }

        let defs: [String: String] = [
            "bg": "none",
            "bgPanel": "none",
            "bgElement": terminalTheme.selectionBackground,
            "fg": terminalTheme.foreground,
            "fgMuted": paletteColor(8, fallback: terminalTheme.foreground),
            "green": paletteColor(2, fallback: terminalTheme.foreground),
            "greenBright": paletteColor(10, fallback: paletteColor(2, fallback: terminalTheme.foreground)),
            "red": paletteColor(1, fallback: terminalTheme.foreground),
            "yellow": paletteColor(3, fallback: terminalTheme.foreground),
            "blue": paletteColor(4, fallback: terminalTheme.foreground),
            "purple": paletteColor(5, fallback: terminalTheme.foreground),
            "cyan": paletteColor(6, fallback: terminalTheme.foreground),
            "border": paletteColor(8, fallback: terminalTheme.selectionBackground),
            "borderActive": terminalTheme.foreground,
            "borderSubtle": terminalTheme.background,
        ]

        let theme: [String: String] = [
            "primary": "cyan",
            "secondary": "blue",
            "accent": "greenBright",
            "error": "red",
            "warning": "yellow",
            "success": "green",
            "info": "blue",
            "text": "fg",
            "textMuted": "fgMuted",
            "background": "bg",
            "backgroundPanel": "bgPanel",
            "backgroundElement": "bgElement",
            "border": "border",
            "borderActive": "borderActive",
            "borderSubtle": "borderSubtle",
            "diffAdded": "green",
            "diffRemoved": "red",
            "diffContext": "fgMuted",
            "diffHunkHeader": "fgMuted",
            "diffHighlightAdded": "green",
            "diffHighlightRemoved": "red",
            "diffAddedBg": "none",
            "diffRemovedBg": "none",
            "diffContextBg": "none",
            "diffLineNumber": "fgMuted",
            "diffAddedLineNumberBg": "none",
            "diffRemovedLineNumberBg": "none",
            "markdownText": "fg",
            "markdownHeading": "cyan",
            "markdownLink": "blue",
            "markdownLinkText": "greenBright",
            "markdownCode": "green",
            "markdownBlockQuote": "fgMuted",
            "markdownEmph": "yellow",
            "markdownStrong": "yellow",
            "markdownHorizontalRule": "fgMuted",
            "markdownListItem": "cyan",
            "markdownListEnumeration": "greenBright",
            "markdownImage": "blue",
            "markdownImageText": "greenBright",
            "markdownCodeBlock": "fg",
            "syntaxComment": "fgMuted",
            "syntaxKeyword": "purple",
            "syntaxFunction": "blue",
            "syntaxVariable": "cyan",
            "syntaxString": "green",
            "syntaxNumber": "yellow",
            "syntaxType": "greenBright",
            "syntaxOperator": "purple",
            "syntaxPunctuation": "fg",
        ]

        return [
            "$schema": Self.openCodeThemeSchemaURL,
            "defs": defs,
            "theme": theme,
        ]
    }

    private func openCodeSourceConfigHomeURL() -> URL {
        if let openCodeSourceConfigHomeOverride {
            return openCodeSourceConfigHomeOverride
        }

        if let xdgConfigHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"],
           !xdgConfigHome.isEmpty {
            return URL(fileURLWithPath: xdgConfigHome, isDirectory: true)
        }

        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
    }

    private func openCodeConfigHomeURL() -> URL {
        if let openCodeConfigHomeOverride {
            return openCodeConfigHomeOverride
        }

        let baseURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL.appendingPathComponent("blink-opencode", isDirectory: true)
    }

    // MARK: - Tab Actions

    /// Create a new shell tab for a workspace.
    @discardableResult
    func openTab(
        workspaceId: String,
        command: String? = nil,
        label: String? = nil,
        workingDirectory: String? = nil,
        role: String? = nil,
        workspaceSetupPaneId: String? = nil
    ) -> AppTab {
        let tab = makeShellTab(
            workspaceId: workspaceId,
            command: command,
            label: label,
            workingDirectory: workingDirectory,
            role: role,
            workspaceSetupPaneId: workspaceSetupPaneId
        )
        registerManagedCommandStateIfNeeded(for: tab)
        insertTab(tab, for: workspaceId, after: nil)

        // Create a new single-tab column
        let column = Column(id: UUID().uuidString, tabIds: [tab.id])
        var workspaceCols = columns[workspaceId] ?? []
        workspaceCols.append(column)
        columns[workspaceId] = workspaceCols

        reindexTabs(for: workspaceId)
        setActiveTab(tab.id)
        activateTerminalFocusSoon()
        return tab
    }

    @discardableResult
    func openBrowserTab(
        workspaceId: String,
        url: String? = nil,
        fullWidth: Bool = false,
        maximizeColumn: Bool = true,
        workspaceSetupPaneId: String? = nil,
        browserState: BrowserPaneState? = nil,
        preferredFocus: BrowserFocusTarget? = nil
    ) -> AppTab {
        if fullWidth {
            return openFullWidthBrowserTab(
                workspaceId: workspaceId,
                url: url,
                workspaceSetupPaneId: workspaceSetupPaneId,
                browserState: browserState,
                preferredFocus: preferredFocus
            )
        }

        let tab = makeBrowserTab(
            workspaceId: workspaceId,
            url: url,
            workspaceSetupPaneId: workspaceSetupPaneId,
            browserState: browserState,
            preferredFocus: preferredFocus
        )
        insertTab(tab, for: workspaceId, after: nil)

        let column = Column(id: UUID().uuidString, tabIds: [tab.id])
        var workspaceCols = columns[workspaceId] ?? []
        workspaceCols.append(column)
        columns[workspaceId] = workspaceCols

        reindexTabs(for: workspaceId)
        setActiveTab(tab.id)
        if maximizeColumn {
            requestColumnMaximize(tab.id)
        }
        sidebarFocused = false
        return tab
    }

    @discardableResult
    func openBrowserTabForActiveWorkspace(
        url: String? = nil,
        fullWidth: Bool = false,
        maximizeColumn: Bool = true
    ) -> AppTab? {
        guard let workspaceId = activeWorkspaceId,
              !isWorkspacePathMissing(workspaceId) else { return nil }
        let resolvedURL = url ?? BrowserDefaults.homePageURLString
        return openBrowserTab(
            workspaceId: workspaceId,
            url: resolvedURL,
            fullWidth: fullWidth,
            maximizeColumn: maximizeColumn,
            preferredFocus: .addressBar
        )
    }

    func openNewTabForActiveSurface() {
        guard let workspaceId = activeWorkspaceId,
              !isWorkspacePathMissing(workspaceId) else { return }

        if !sidebarFocused,
           let activeTabId,
           let activeTab = tabsById[activeTabId],
           activeTab.workspaceId == workspaceId,
           activeTab.isBrowser {
            _ = openBrowserTabInPane(
                activeTabId,
                url: BrowserDefaults.homePageURLString,
                preferredFocus: .addressBar
            )
            return
        }

        _ = openTab(workspaceId: workspaceId)
    }

    func splitActivePaneWithNewTab() {
        guard let workspaceId = activeWorkspaceId,
              !isWorkspacePathMissing(workspaceId) else { return }

        guard let currentCol = activeColumn,
              let activeTabId else {
            _ = openTab(workspaceId: workspaceId)
            return
        }

        var cols = workspaceColumns(for: workspaceId)
        guard let colIdx = cols.firstIndex(where: { $0.id == currentCol.id }),
              let tabIdx = cols[colIdx].tabIds.firstIndex(of: activeTabId) else {
            _ = openTab(workspaceId: workspaceId)
            return
        }

        let tab = makeShellTab(workspaceId: workspaceId, command: nil, label: nil)
        insertTab(tab, for: workspaceId, after: activeTabId)
        cols[colIdx].tabIds.insert(tab.id, at: cols[colIdx].tabIds.index(after: tabIdx))
        columns[workspaceId] = cols

        reindexTabs(for: workspaceId)
        setActiveTab(tab.id)
        activateTerminalFocusSoon()
    }

    func splitActiveColumnWithNewTab() {
        guard let workspaceId = activeWorkspaceId,
              !isWorkspacePathMissing(workspaceId) else { return }

        guard let currentCol = activeColumn,
              let anchorTabId = currentCol.tabIds.last else {
            _ = openTab(workspaceId: workspaceId)
            return
        }

        var cols = workspaceColumns(for: workspaceId)
        guard let colIdx = cols.firstIndex(where: { $0.id == currentCol.id }) else {
            _ = openTab(workspaceId: workspaceId)
            return
        }

        let tab = makeShellTab(workspaceId: workspaceId, command: nil, label: nil)
        insertTab(tab, for: workspaceId, after: anchorTabId)
        cols.insert(
            Column(id: UUID().uuidString, tabIds: [tab.id]),
            at: cols.index(after: colIdx)
        )
        columns[workspaceId] = cols

        reindexTabs(for: workspaceId)
        setActiveTab(tab.id)
        activateTerminalFocusSoon()
    }

    @discardableResult
    func openOrFocusCommandTab(
        workspaceId: String,
        command: String,
        label: String,
        workingDirectory: String? = nil,
        role: String? = nil,
        workspaceSetupPaneId: String? = nil,
        fullWidth: Bool = false,
        maximizeColumn: Bool = false
    ) -> AppTab {
        if let existing = workspaceTabs(for: workspaceId).first(where: {
            $0.command == command
                && effectiveWorkingDirectory($0.workingDirectory, workspaceId: workspaceId)
                    == effectiveWorkingDirectory(workingDirectory, workspaceId: workspaceId)
        }) {
            if existing.isManagedCommand && isManagedCommandStopped(existing.id) {
                restartManagedCommandTab(existing.id)
            } else if existing.isManagedCommand {
                registerManagedCommandStateIfNeeded(for: existing)
            }
            if fullWidth, !fullWidthTabIds.contains(existing.id) {
                // Existing tab found but not in full-width mode — make it full-width
                savedColumns[workspaceId] = columns[workspaceId] ?? []
                let column = Column(id: UUID().uuidString, tabIds: [existing.id])
                columns[workspaceId] = [column]
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
                workspaceId: workspaceId,
                command: command,
                label: label,
                workingDirectory: workingDirectory,
                role: role,
                workspaceSetupPaneId: workspaceSetupPaneId
            )
        } else {
            let tab = openTab(
                workspaceId: workspaceId,
                command: command,
                label: label,
                workingDirectory: workingDirectory,
                role: role,
                workspaceSetupPaneId: workspaceSetupPaneId
            )
            if maximizeColumn {
                requestColumnMaximize(tab.id)
            }
            return tab
        }
    }

    @discardableResult
    func openOrFocusBrowserTab(workspaceId: String, url: String) -> AppTab {
        let resolvedURLString = BrowserURLResolver.resolve(url)?.absoluteString ?? url

        if let existing = workspaceTabs(for: workspaceId).first(where: { tab in
            tab.isBrowser && (tab.browserState?.tabs.contains { $0.state.urlString == resolvedURLString } ?? false)
        }), let browserTabId = existing.browserState?.tabs.first(where: { $0.state.urlString == resolvedURLString })?.id {
            setActiveTab(existing.id)
            selectBrowserTab(browserTabId, in: existing.id)
            return tabsById[existing.id] ?? existing
        }

        if let activeBrowserTab = tabsById[activeTabId ?? ""],
           activeBrowserTab.workspaceId == workspaceId,
           activeBrowserTab.isBrowser {
            _ = openBrowserTabInPane(activeBrowserTab.id, url: resolvedURLString)
            return tabsById[activeBrowserTab.id] ?? activeBrowserTab
        }

        if let existingBrowserPane = workspaceTabs(for: workspaceId).first(where: \.isBrowser) {
            _ = openBrowserTabInPane(existingBrowserPane.id, url: resolvedURLString)
            return tabsById[existingBrowserPane.id] ?? existingBrowserPane
        }

        return openBrowserTab(workspaceId: workspaceId, url: resolvedURLString)
    }

    @discardableResult
    func openOrFocusBrowserTabForActiveWorkspace(url: String) -> AppTab? {
        guard let workspaceId = activeWorkspaceId else { return nil }
        return openOrFocusBrowserTab(workspaceId: workspaceId, url: url)
    }

    @discardableResult
    func openOrFocusCommandTabForActiveWorkspace(
        command: String,
        label: String,
        workingDirectory: String? = nil,
        role: String? = nil,
        workspaceSetupPaneId: String? = nil,
        fullWidth: Bool = false,
        maximizeColumn: Bool = false
    ) -> AppTab? {
        guard let workspaceId = activeWorkspaceId,
              !isWorkspacePathMissing(workspaceId) else { return nil }
        return openOrFocusCommandTab(
            workspaceId: workspaceId,
            command: command,
            label: label,
            workingDirectory: workingDirectory,
            role: role,
            workspaceSetupPaneId: workspaceSetupPaneId,
            fullWidth: fullWidth,
            maximizeColumn: maximizeColumn
        )
    }

    func openFileInEditor(
        workspaceId: String,
        path: String,
        line: Int? = nil,
        column: Int? = nil
    ) {
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let resolvedPath = resolveExistingWorkspaceFilePath(
            normalizedPath,
            workspaceId: workspaceId
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
            workspaceId: workspaceId,
            path: resolvedPath,
            line: line,
            column: column
        ) {
            return
        }

        if tmuxIntegrationEnabled {
            openFileInNewTmuxEditorTab(
                workspaceId: workspaceId,
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
        _ = openTab(workspaceId: workspaceId, command: command, label: label)
    }

    func openFileInEditorForActiveWorkspace(
        path: String,
        line: Int? = nil,
        column: Int? = nil
    ) {
        guard let workspaceId = activeWorkspaceId,
              !isWorkspacePathMissing(workspaceId) else { return }
        openFileInEditor(workspaceId: workspaceId, path: path, line: line, column: column)
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

    /// Columns saved before a full-width tab replaced them, keyed by workspace ID.
    private var savedColumns: [String: [Column]] = [:]
    /// Tracks which tab triggered full-width mode per workspace, so we can restore on close.
    private var fullWidthTabIds: Set<String> = []

    /// Open a tab that replaces all columns, taking the full workspace width.
    /// The previous layout is saved and restored when the tab closes.
    @discardableResult
    private func openFullWidthTab(
        workspaceId: String,
        command: String,
        label: String,
        workingDirectory: String? = nil,
        role: String? = nil,
        workspaceSetupPaneId: String? = nil
    ) -> AppTab {
        let tab = AppTab(
            id: UUID().uuidString,
            kind: .terminal,
            label: label,
            defaultLabel: label,
            workspaceId: workspaceId,
            command: command,
            role: role,
            workingDirectory: workingDirectory,
            workspaceSetupPaneId: workspaceSetupPaneId
        )
        tabs.append(tab)
        registerManagedCommandStateIfNeeded(for: tab)

        // Save current columns and replace with just this tab
        savedColumns[workspaceId] = columns[workspaceId] ?? []
        let column = Column(id: UUID().uuidString, tabIds: [tab.id])
        columns[workspaceId] = [column]
        fullWidthTabIds.insert(tab.id)

        setActiveTab(tab.id)
        return tab
    }

    @discardableResult
    private func openFullWidthBrowserTab(
        workspaceId: String,
        url: String? = nil,
        workspaceSetupPaneId: String? = nil,
        browserState: BrowserPaneState? = nil,
        preferredFocus: BrowserFocusTarget? = nil
    ) -> AppTab {
        let tab = makeBrowserTab(
            workspaceId: workspaceId,
            url: url,
            workspaceSetupPaneId: workspaceSetupPaneId,
            browserState: browserState,
            preferredFocus: preferredFocus
        )
        insertTab(tab, for: workspaceId, after: nil)

        savedColumns[workspaceId] = columns[workspaceId] ?? []
        let column = Column(id: UUID().uuidString, tabIds: [tab.id])
        columns[workspaceId] = [column]
        fullWidthTabIds.insert(tab.id)

        reindexTabs(for: workspaceId)
        setActiveTab(tab.id)
        sidebarFocused = false
        return tab
    }

    /// Restore columns after a full-width tab closes. Called from closeTab.
    private func restoreColumnsIfNeeded(tabId: String, workspaceId: String) {
        guard fullWidthTabIds.remove(tabId) != nil,
              let saved = savedColumns.removeValue(forKey: workspaceId) else { return }
        columns[workspaceId] = saved
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

    @discardableResult
    func openBrowserTabInPane(
        _ paneTabId: String,
        url: String? = nil,
        preferredFocus: BrowserFocusTarget? = nil
    ) -> BrowserPaneTab? {
        guard let idx = tabs.firstIndex(where: { $0.id == paneTabId && $0.isBrowser }) else { return nil }
        let rawURLString = url ?? BrowserDefaults.homePageURLString
        let resolvedURLString = BrowserURLResolver.resolve(rawURLString)?.absoluteString ?? rawURLString

        var paneState = tabs[idx].browserState ?? .empty
        let browserTab = BrowserPaneTab(
            state: BrowserTabState(
                urlString: resolvedURLString,
                title: nil,
                canGoBack: false,
                canGoForward: false,
                isLoading: false,
                preferredFocus: preferredFocus ?? .webView
            )
        )
        paneState.appendTab(browserTab)
        tabs[idx].browserState = paneState
        tabs[idx].label = browserPaneLabel(for: paneState, fallback: tabs[idx].defaultLabel)
        setActiveTab(paneTabId)
        sidebarFocused = false
        return browserTab
    }

    func selectBrowserTab(_ browserTabId: String, in paneTabId: String) {
        guard let idx = tabs.firstIndex(where: { $0.id == paneTabId && $0.isBrowser }),
              var paneState = tabs[idx].browserState else { return }
        guard paneState.selectedTabId != browserTabId else { return }
        paneState.selectTab(browserTabId)
        if let selectedTab = paneState.selectedTab,
           selectedTab.state.preferredFocus != .webView {
            var updatedState = selectedTab.state
            updatedState.preferredFocus = .webView
            paneState.updateState(updatedState, for: selectedTab.id)
        }
        tabs[idx].browserState = paneState
        tabs[idx].label = browserPaneLabel(for: paneState, fallback: tabs[idx].defaultLabel)
    }

    func closeBrowserTab(_ browserTabId: String, in paneTabId: String) {
        guard let idx = tabs.firstIndex(where: { $0.id == paneTabId && $0.isBrowser }),
              var paneState = tabs[idx].browserState else { return }

        if paneState.tabs.count <= 1 {
            closeTab(paneTabId)
            return
        }

        let removedTab = paneState.removeTab(browserTabId)
        guard removedTab != nil else { return }

        tabs[idx].browserState = paneState
        tabs[idx].label = browserPaneLabel(for: paneState, fallback: tabs[idx].defaultLabel)
        browserManager?.destroyController(tabId: browserTabId)
    }

    func toggleBrowserSidebarPinned(for paneTabId: String) {
        guard let idx = tabs.firstIndex(where: { $0.id == paneTabId && $0.isBrowser }),
              var paneState = tabs[idx].browserState else { return }
        paneState.isSidebarPinned.toggle()
        tabs[idx].browserState = paneState
    }

    func toggleBrowserTabPinned(_ browserTabId: String, in paneTabId: String) {
        guard let idx = tabs.firstIndex(where: { $0.id == paneTabId && $0.isBrowser }),
              var paneState = tabs[idx].browserState,
              let browserTab = paneState.tabs.first(where: { $0.id == browserTabId }) else { return }
        paneState.setPinned(!browserTab.isPinned, for: browserTabId)
        tabs[idx].browserState = paneState
        tabs[idx].label = browserPaneLabel(for: paneState, fallback: tabs[idx].defaultLabel)
    }

    func toggleActiveBrowserSidebarPinned() {
        guard let paneTabId = activeTabId,
              let paneTab = tabsById[paneTabId],
              paneTab.isBrowser else { return }

        toggleBrowserSidebarPinned(for: paneTabId)
    }

    func updateBrowserState(_ state: BrowserTabState, for browserTabId: String, in paneTabId: String) {
        guard let idx = tabs.firstIndex(where: { $0.id == paneTabId && $0.isBrowser }),
              var paneState = tabs[idx].browserState else { return }
        let previousState = paneState.tabs.first(where: { $0.id == browserTabId })?.state
        guard previousState != state else { return }

        paneState.updateState(state, for: browserTabId)
        tabs[idx].browserState = paneState
        tabs[idx].label = browserPaneLabel(for: paneState, fallback: tabs[idx].defaultLabel)
        markUnread(paneTabId)
    }

    func setBrowserFocusTarget(_ target: BrowserFocusTarget, for browserTabId: String, in paneTabId: String) {
        guard let idx = tabs.firstIndex(where: { $0.id == paneTabId && $0.isBrowser }),
              var paneState = tabs[idx].browserState,
              let browserTab = paneState.tabs.first(where: { $0.id == browserTabId }) else { return }
        guard browserTab.state.preferredFocus != target else { return }
        var updatedState = browserTab.state
        updatedState.preferredFocus = target
        paneState.updateState(updatedState, for: browserTabId)
        tabs[idx].browserState = paneState
    }

    private var activeBrowserSelection: (paneTabId: String, browserTabId: String)? {
        guard let paneTabId = activeTabId,
              let paneTab = tabsById[paneTabId],
              paneTab.isBrowser,
              let browserTabId = paneTab.browserState?.selectedTab?.id else {
            return nil
        }
        return (paneTabId, browserTabId)
    }

    var hasActiveBrowserSelection: Bool {
        activeBrowserSelection != nil
    }

    var hasBlockingModalPresentation: Bool {
        activeView == .settings
            || showWorkspaceSwitcher
            || showWorkspaceOnboarding
            || showThemePicker
            || showAISessionPicker
            || showCommandPalette
            || workspacePrompt != nil
    }

    func focusBrowserAddressBar() {
        guard !hasBlockingModalPresentation,
              let selection = activeBrowserSelection else { return }
        setBrowserFocusTarget(.addressBar, for: selection.browserTabId, in: selection.paneTabId)
        browserManager?.focusAddressBar(tabId: selection.browserTabId)
    }

    func focusBrowserWebView() {
        guard let selection = activeBrowserSelection else { return }
        setBrowserFocusTarget(.webView, for: selection.browserTabId, in: selection.paneTabId)
        browserManager?.focusWebView(tabId: selection.browserTabId)
    }

    func navigateActiveBrowserBack() {
        guard let selection = activeBrowserSelection else { return }
        browserManager?.goBack(tabId: selection.browserTabId)
    }

    func navigateActiveBrowserForward() {
        guard let selection = activeBrowserSelection else { return }
        browserManager?.goForward(tabId: selection.browserTabId)
    }

    func reloadActiveBrowser() {
        guard let selection = activeBrowserSelection else { return }
        browserManager?.reload(tabId: selection.browserTabId)
    }

    func toggleActiveBrowserDeveloperTools() {
        guard let selection = activeBrowserSelection else { return }
        browserManager?.toggleDeveloperTools(tabId: selection.browserTabId)
    }

    func openActiveBrowserInDefaultBrowser() {
        guard let selection = activeBrowserSelection else { return }
        browserManager?.openInDefaultBrowser(tabId: selection.browserTabId)
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

    /// Check if a workspace has any unread tabs.
    func hasUnread(workspaceId: String) -> Bool {
        let workspaceTabIds = Set(workspaceTabs(for: workspaceId).map(\.id))
        return !unreadTabs.isDisjoint(with: workspaceTabIds)
    }

    func claudeActivity(for tabId: String) -> ClaudeTabActivity? {
        claudeTabActivities[tabId]
    }

    func claudeWorkspaceActivity(for workspaceId: String) -> ClaudeTabActivity? {
        let activities = workspaceTabs(for: workspaceId)
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

    func workspaceTabs(for workspaceId: String) -> [AppTab] {
        tabs.filter { $0.workspaceId == workspaceId }
    }

    func terminalCount(for workspaceId: String) -> Int {
        tabs.filter { $0.workspaceId == workspaceId && $0.isShell }.count
    }

    private func handleClaudeHookEvent(_ event: ClaudeHookEvent) {
        let resolvedTabId: String? = {
            if let tab = tabsById[event.tabId], tab.workspaceId == event.workspaceId {
                return tab.id
            }
            if let paneId = event.paneId {
                return tabs.first {
                    $0.workspaceId == event.workspaceId && $0.workspaceSetupPaneId == paneId
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
        workspaceId: String,
        tabId: String,
        rawInput: String,
        paneId: String? = nil
    ) {
        handleClaudeHookEvent(ClaudeHookEvent(
            event: event,
            workspaceId: workspaceId,
            tabId: tabId,
            paneId: paneId,
            workspacePath: nil,
            cwd: nil,
            pid: nil,
            rawInput: rawInput
        ))
    }
#endif

    func removeWorkspace(_ id: String) {
        guard !workspaces.contains(where: { $0.id == id && $0.isScratchSpace }) else { return }

        let workspaceTabs = tabs.filter { $0.workspaceId == id }
        let tabIds = workspaceTabs.map(\.id)
        let browserControllerIds = workspaceTabs.flatMap(browserControllerIds(for:))
        let paneIds = workspaceTabs.compactMap(\.workspaceSetupPaneId)
        workspaces.removeAll { $0.id == id }
        workspaceSetups[id] = nil
        tabs.removeAll { $0.workspaceId == id }
        clearManagedCommandStates(for: tabIds)
        clearClaudeTabActivities(for: tabIds)
        clearPendingTmuxShellCommands(for: tabIds)
        unreadTabs.subtract(tabIds)
        lastActiveTab[id] = nil
        if activeWorkspaceId == id {
            activeWorkspaceId = nil
            activeTabId = nil
        }
        if lastSelectedWorkspaceId == id {
            lastSelectedWorkspaceId = nil
        }
        expandedWorkspaceIds.remove(id)
        workspaceViewportOffsets[id] = nil

        // Clean up column state
        if let workspaceCols = columns[id] {
            for col in workspaceCols {
                columnFocusedTab[col.id] = nil
            }
        }
        columns[id] = nil

        let surfaceManager = surfaceManager
        browserManager?.destroyControllers(tabIds: browserControllerIds)
        DispatchQueue.main.async {
            surfaceManager?.destroySurfaces(tabIds: tabIds)
        }
        destroyTmuxWorkspaceSession(workspaceId: id, paneIds: paneIds)
    }

    @discardableResult
    func renameWorkspace(_ id: String, to name: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              let workspaceIndex = workspaces.firstIndex(where: { $0.id == id }) else {
            return false
        }

        let workspace = workspaces[workspaceIndex]
        guard !workspace.isScratchSpace else { return false }

        workspaces[workspaceIndex] = Workspace(
            id: workspace.id,
            name: trimmedName,
            path: workspace.path,
            profileId: workspace.profileId,
            color: workspace.color,
            createdAt: workspace.createdAt
        )
        return true
    }

    func promptRenameWorkspace(_ id: String) {
        guard let workspace = workspaces.first(where: { $0.id == id }),
              !workspace.isScratchSpace else { return }
        workspacePrompt = WorkspacePromptState(
            workspaceId: id,
            kind: .rename,
            initialValue: workspace.name
        )
    }

    @discardableResult
    func relinkWorkspace(_ id: String, toPath path: String) -> Bool {
        let normalizedPath = normalizedWorkspacePath(path)
        guard Self.directoryExists(at: normalizedPath),
              let workspaceIndex = workspaces.firstIndex(where: { $0.id == id }) else {
            return false
        }

        let workspace = workspaces[workspaceIndex]
        guard !workspace.isScratchSpace else { return false }

        workspaces[workspaceIndex] = Workspace(
            id: workspace.id,
            name: workspace.name,
            path: normalizedPath,
            profileId: workspace.profileId,
            color: workspace.color,
            createdAt: workspace.createdAt
        )

        if activeWorkspaceId == id,
           workspaceTabs(for: id).isEmpty,
           hasWorkspaceSetup(for: id) {
            restoreWorkspaceSetup(for: id)
        }

        return true
    }

    func promptRelinkWorkspace(_ id: String) {
        guard let workspace = workspaces.first(where: { $0.id == id }),
              !workspace.isScratchSpace else { return }
        workspacePrompt = WorkspacePromptState(
            workspaceId: id,
            kind: .relink,
            initialValue: workspace.path
        )
    }

    func revealWorkspaceInFinder(_ id: String) {
        guard let workspace = workspaces.first(where: { $0.id == id }),
              !workspace.isScratchSpace,
              Self.directoryExists(at: workspace.path) else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: workspace.path)])
    }

    func closeTab(_ id: String) {
        guard let tab = tabsById[id] else { return }
        let workspaceId = tab.workspaceId
        let paneId = tab.workspaceSetupPaneId

        // If this was a full-width tab, restore the saved layout and clean up
        if fullWidthTabIds.contains(id) {
            restoreColumnsIfNeeded(tabId: id, workspaceId: workspaceId)
            tabs.removeAll { $0.id == id }
            managedCommandStates[id] = nil
            claudeTabActivities[id] = nil
            clearPendingTmuxShellCommands(for: [id])
            unreadTabs.remove(id)
            if lastActiveTab[workspaceId] == id { lastActiveTab[workspaceId] = nil }
            // Focus the previously active tab in the restored layout
            if activeTabId == id {
                let restoredCols = workspaceColumns(for: workspaceId)
                if let firstCol = restoredCols.first,
                   let fallback = columnFocusedTab[firstCol.id] ?? firstCol.tabIds.first {
                    setActiveTab(fallback)
                } else {
                    activeTabId = nil
                }
            }
            if let paneId, shouldUseTmux(for: tab) {
                destroyTmuxPane(workspaceId: workspaceId, paneId: paneId)
            }
            switch tab.kind {
            case .terminal:
                surfaceManager?.destroySurface(tabId: id)
            case .browser:
                browserManager?.destroyControllers(tabIds: browserControllerIds(for: tab))
            case .chat:
                break
            }
            return
        }

        // Find the column and position of this tab
        var workspaceCols = columns[workspaceId] ?? []
        guard let colIdx = workspaceCols.firstIndex(where: { $0.tabIds.contains(id) }) else { return }
        let paneIdx = workspaceCols[colIdx].tabIds.firstIndex(of: id)!

        // Remove tab from column
        workspaceCols[colIdx].tabIds.removeAll { $0 == id }

        // Determine next focus before removing empty column
        var nextFocusTabId: String? = nil
        if activeTabId == id {
            if !workspaceCols[colIdx].tabIds.isEmpty {
                // Prefer next pane down, then previous pane up
                let newPaneIdx = min(paneIdx, workspaceCols[colIdx].tabIds.count - 1)
                nextFocusTabId = workspaceCols[colIdx].tabIds[newPaneIdx]
            }
        }

        // Remove column if empty
        if workspaceCols[colIdx].tabIds.isEmpty {
            let removedColId = workspaceCols[colIdx].id
            columnFocusedTab[removedColId] = nil
            workspaceCols.remove(at: colIdx)
        }

        columns[workspaceId] = workspaceCols

        // Remove tab data
        tabs.removeAll { $0.id == id }
        managedCommandStates[id] = nil
        claudeTabActivities[id] = nil
        clearPendingTmuxShellCommands(for: [id])
        unreadTabs.remove(id)
        if lastActiveTab[workspaceId] == id {
            lastActiveTab[workspaceId] = nil
        }

        // Set next focus
        if activeTabId == id {
            if let next = nextFocusTabId {
                setActiveTab(next)
            } else {
                // Fall back to adjacent column (prefer right, then left)
                let updatedCols = workspaceColumns(for: workspaceId)
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
                    workspaceViewportOffsets[workspaceId] = nil
                    if sidebarVisible { sidebarFocused = true }
                }
            }
        }

        reindexTabs(for: workspaceId)

        let surfaceManager = surfaceManager
        if tab.isBrowser {
            browserManager?.destroyControllers(tabIds: browserControllerIds(for: tab))
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
            destroyTmuxPane(workspaceId: workspaceId, paneId: paneId)
        }
    }

    func closeActiveTab() {
        guard let activeTabId else { return }
        if let activeTab = tabsById[activeTabId],
           activeTab.isBrowser,
           let paneState = activeTab.browserState,
           let selectedBrowserTabId = paneState.selectedTab?.id {
            if paneState.tabs.count <= 1 {
                closeTab(activeTabId)
                return
            }
            closeBrowserTab(selectedBrowserTabId, in: activeTabId)
            return
        }
        closeTab(activeTabId)
    }

    func restoreWorkspaceSetup(for workspaceId: String? = nil) {
        let targetWorkspaceId = workspaceId ?? activeWorkspaceId
        guard let targetWorkspaceId,
              let setup = workspaceSetups[targetWorkspaceId] else { return }

        replaceWorkspaceSession(for: targetWorkspaceId, using: setup)
        if activeWorkspaceId == targetWorkspaceId {
            setActiveWorkspace(targetWorkspaceId)
        }
    }

    private func replaceWorkspaceSession(for workspaceId: String, using setup: WorkspaceSetup) {
        suppressWorkspaceSessionAutosave = true
        defer {
            suppressWorkspaceSessionAutosave = false
            autosaveWorkspaceSessionsIfNeeded()
        }

        let existingWorkspaceTabs = tabs.filter { $0.workspaceId == workspaceId }
        let existingTabIds = existingWorkspaceTabs.map(\.id)
        let existingBrowserControllerIds = existingWorkspaceTabs.flatMap(browserControllerIds(for:))
        tabs.removeAll { $0.workspaceId == workspaceId }
        clearManagedCommandStates(for: existingTabIds)
        clearClaudeTabActivities(for: existingTabIds)
        unreadTabs.subtract(existingTabIds)
        lastActiveTab[workspaceId] = nil
        workspaceViewportOffsets[workspaceId] = nil

        let resolvedSetup = normalizedWorkspaceSetup(from: setup)
        let paneLookup = Dictionary(uniqueKeysWithValues: resolvedSetup.panes.map { ($0.id, $0) })
        var paneToTabId: [String: String] = [:]
        var rebuiltTabs: [AppTab] = []

        for column in resolvedSetup.columns {
            for paneId in column.paneIds {
                guard let pane = paneLookup[paneId] else { continue }
                let workingDirectory = resolvedWorkingDirectory(for: pane, workspaceId: workspaceId)
                let tab: AppTab
                switch pane.kind {
                case .shell:
                    tab = makeShellTab(
                        workspaceId: workspaceId,
                        command: nil,
                        label: nil,
                        workingDirectory: workingDirectory,
                        role: pane.role,
                        workspaceSetupPaneId: pane.id
                    )
                case .command:
                    tab = makeShellTab(
                        workspaceId: workspaceId,
                        command: pane.command,
                        label: pane.label,
                        workingDirectory: workingDirectory,
                        role: pane.role,
                        workspaceSetupPaneId: pane.id
                    )
                case .browser:
                    tab = makeBrowserTab(
                        workspaceId: workspaceId,
                        url: pane.browserState?.selectedTab?.state.urlString,
                        workspaceSetupPaneId: pane.id,
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
        columns[workspaceId] = resolvedSetup.columns.compactMap { column in
            let tabIds = column.paneIds.compactMap { paneToTabId[$0] }
            guard !tabIds.isEmpty else { return nil }
            return Column(id: column.id, tabIds: tabIds)
        }
        reindexTabs(for: workspaceId)

        if let firstTabId = columns[workspaceId]?.first?.tabIds.first ?? rebuiltTabs.first?.id {
            lastActiveTab[workspaceId] = firstTabId
            if activeWorkspaceId == workspaceId {
                activeTabId = firstTabId
            }
        }

        let surfaceManager = surfaceManager
        browserManager?.destroyControllers(tabIds: existingBrowserControllerIds)
        DispatchQueue.main.async {
            surfaceManager?.destroySurfaces(tabIds: existingTabIds)
        }
    }

    private func currentWorkspaceSetupSnapshot(for workspaceId: String) -> WorkspaceSetup? {
        let cols = workspaceColumns(for: workspaceId)
        guard !cols.isEmpty else { return nil }

        let lookup = tabsById
        var panes: [WorkspaceSetupPane] = []
        var tabIdToPaneId: [String: String] = [:]
        var nextPaneIndex = 0

        for column in cols {
            for tabId in column.tabIds {
                guard let tab = lookup[tabId] else { continue }
                let paneId = tab.workspaceSetupPaneId ?? "pane-\(nextPaneIndex)"
                nextPaneIndex += 1
                panes.append(
                    WorkspaceSetupPane(
                        id: paneId,
                        kind: workspaceSetupPaneKind(for: tab),
                        label: persistedWorkspaceSetupLabel(for: tab),
                        role: tab.role,
                        command: tab.command,
                        workingDirectory: normalizedWorkingDirectory(tab.workingDirectory, workspaceId: workspaceId),
                        browserState: tab.browserState
                    )
                )
                tabIdToPaneId[tabId] = paneId
            }
        }

        let setupColumns: [WorkspaceSetupColumn] = cols.enumerated().compactMap { entry in
            let (index, column) = entry
            let paneIds = column.tabIds.compactMap { tabIdToPaneId[$0] }
            guard !paneIds.isEmpty else { return nil }
            return WorkspaceSetupColumn(id: "col-\(index)", paneIds: paneIds)
        }

        guard !setupColumns.isEmpty else { return nil }
        return WorkspaceSetup(workspaceId: workspaceId, updatedAt: .now, columns: setupColumns, panes: panes)
    }

    private func autosaveWorkspaceSessionsIfNeeded() {
        guard !suppressWorkspaceSessionAutosave else { return }

        var nextWorkspaceSetups = workspaceSetups
        var changed = false

        for workspace in workspaces {
            let snapshot = currentWorkspaceSetupSnapshot(for: workspace.id)
            let normalizedSnapshot = snapshot.map(normalizedWorkspaceSetup(from:))
            let normalizedExisting = workspaceSetups[workspace.id].map(normalizedWorkspaceSetup(from:))

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
                nextWorkspaceSetups[workspace.id] = snapshot
            }
        }

        if changed {
            workspaceSetups = nextWorkspaceSetups
        }
    }

    private func normalizedWorkspaceSetup(from setup: WorkspaceSetup) -> WorkspaceSetup {
        let setup = Self.sanitizeLegacyChatPanes(in: setup)
        let paneLookup = Dictionary(uniqueKeysWithValues: setup.panes.map { ($0.id, $0) })
        var normalizedPanes: [WorkspaceSetupPane] = []
        var oldToNewPaneIds: [String: String] = [:]
        var nextPaneIndex = 0

        for column in setup.columns {
            for paneId in column.paneIds {
                guard let pane = paneLookup[paneId] else { continue }
                let normalizedId = "pane-\(nextPaneIndex)"
                nextPaneIndex += 1
                oldToNewPaneIds[paneId] = normalizedId
                normalizedPanes.append(
                    WorkspaceSetupPane(
                        id: normalizedId,
                        kind: pane.kind,
                        label: pane.label,
                        role: pane.role,
                        command: pane.command,
                        workingDirectory: normalizedWorkingDirectory(pane.workingDirectory, workspaceId: setup.workspaceId),
                        browserState: pane.browserState
                    )
                )
            }
        }

        let normalizedColumns: [WorkspaceSetupColumn] = setup.columns.enumerated().compactMap { entry in
            let (index, column) = entry
            let paneIds = column.paneIds.compactMap { oldToNewPaneIds[$0] }
            guard !paneIds.isEmpty else { return nil }
            return WorkspaceSetupColumn(id: "col-\(index)", paneIds: paneIds)
        }

        return WorkspaceSetup(
            workspaceId: setup.workspaceId,
            updatedAt: .distantPast,
            columns: normalizedColumns,
            panes: normalizedPanes
        )
    }

    private func normalizedWorkingDirectory(_ path: String?, workspaceId: String) -> String? {
        guard let path else { return nil }
        if let workspacePath = workspacePath(for: workspaceId), path == workspacePath {
            return nil
        }
        return path
    }

    private func resolvedWorkingDirectory(for pane: WorkspaceSetupPane, workspaceId: String) -> String {
        validatedWorkingDirectory(pane.workingDirectory, workspaceId: workspaceId)
    }

    private func workspaceSetupPaneKind(for tab: AppTab) -> WorkspaceSetupPaneKind {
        switch tab.kind {
        case .terminal:
            return tab.command == nil ? .shell : .command
        case .browser:
            return .browser
        case .chat:
            return .chat
        }
    }

    private func persistedWorkspaceSetupLabel(for tab: AppTab) -> String {
        if tab.isShell && tab.command == nil {
            return tab.defaultLabel
        }

        return tab.label
    }

    private func workspacePath(for workspaceId: String) -> String? {
        workspaces.first(where: { $0.id == workspaceId })?.path
    }

    private func effectiveWorkingDirectory(_ path: String?, workspaceId: String) -> String {
        validatedWorkingDirectory(path, workspaceId: workspaceId)
    }

    private func validatedWorkingDirectory(_ path: String?, workspaceId: String) -> String {
        if let path, Self.directoryExists(at: path) {
            return path
        }

        if let workspacePath = workspacePath(for: workspaceId), Self.directoryExists(at: workspacePath) {
            return workspacePath
        }

        return NSHomeDirectory()
    }

    private func sanitizePersistedWorkspaceState() {
        let validWorkspaceIds = Set(workspaces.map(\.id))
        Self.saveWorkspaces(workspaces)

        let nextWorkspaceSetups = workspaceSetups.filter { validWorkspaceIds.contains($0.key) }
        if nextWorkspaceSetups != workspaceSetups {
            workspaceSetups = nextWorkspaceSetups
        }

        let nextColumns = columns.filter { validWorkspaceIds.contains($0.key) }
        if nextColumns != columns {
            columns = nextColumns
        }

        let nextLastActiveTab = lastActiveTab.filter { validWorkspaceIds.contains($0.key) }
        if nextLastActiveTab != lastActiveTab {
            lastActiveTab = nextLastActiveTab
        }

        let nextViewportOffsets = workspaceViewportOffsets.filter { validWorkspaceIds.contains($0.key) }
        if nextViewportOffsets != workspaceViewportOffsets {
            workspaceViewportOffsets = nextViewportOffsets
        }

        let nextExpandedWorkspaceIds = expandedWorkspaceIds.intersection(validWorkspaceIds)
        if nextExpandedWorkspaceIds != expandedWorkspaceIds {
            expandedWorkspaceIds = nextExpandedWorkspaceIds
        }

        if let activeWorkspaceId, !validWorkspaceIds.contains(activeWorkspaceId) {
            self.activeWorkspaceId = nil
            activeTabId = nil
        }

        if let lastSelectedWorkspaceId, !validWorkspaceIds.contains(lastSelectedWorkspaceId) {
            self.lastSelectedWorkspaceId = nil
        }
    }

    private func makeShellTab(
        workspaceId: String,
        command: String?,
        label: String?,
        workingDirectory: String? = nil,
        role: String? = nil,
        workspaceSetupPaneId: String? = nil
    ) -> AppTab {
        let count = tabs.filter { $0.workspaceId == workspaceId && $0.isShell && $0.command == nil }.count + 1
        let defaultLabel = command == nil ? "Terminal \(count)" : (label ?? "Terminal \(count)")
        let resolvedLabel = label ?? defaultLabel
        return AppTab(
            id: UUID().uuidString,
            kind: .terminal,
            label: resolvedLabel,
            defaultLabel: defaultLabel,
            workspaceId: workspaceId,
            command: command,
            role: role,
            workingDirectory: workingDirectory,
            workspaceSetupPaneId: workspaceSetupPaneId ?? makeWorkspaceSetupPaneId()
        )
    }

    private func makeBrowserTab(
        workspaceId: String,
        url: String?,
        workspaceSetupPaneId: String? = nil,
        browserState: BrowserPaneState? = nil,
        preferredFocus: BrowserFocusTarget? = nil
    ) -> AppTab {
        let resolvedURLString = url.flatMap { BrowserURLResolver.resolve($0)?.absoluteString ?? $0 }
        let count = tabs.filter { $0.workspaceId == workspaceId && $0.isBrowser }.count + 1
        let defaultLabel = "Workspace Browser \(count)"
        let resolvedState = browserState ?? BrowserPaneState.singleTab(
            urlString: resolvedURLString,
            preferredFocus: preferredFocus
        )

        return AppTab(
            id: UUID().uuidString,
            kind: .browser,
            label: browserPaneLabel(for: resolvedState, fallback: defaultLabel),
            defaultLabel: defaultLabel,
            workspaceId: workspaceId,
            workspaceSetupPaneId: workspaceSetupPaneId ?? makeWorkspaceSetupPaneId(),
            browserState: resolvedState
        )
    }

    func browserPaneLabel(for state: BrowserPaneState?, fallback: String) -> String {
        guard let browserTab = state?.selectedTab else { return fallback }
        return browserTab.displayTitle
    }

    func browserControllerIds(for tab: AppTab) -> [String] {
        guard tab.isBrowser else { return [] }
        return tab.browserState?.tabs.map(\.id) ?? []
    }

    private func insertTab(_ tab: AppTab, for workspaceId: String, after anchorTabId: String?) {
        guard let anchorTabId,
              let anchorIndex = tabs.firstIndex(where: { $0.id == anchorTabId }) else {
            if let workspaceLastIndex = tabs.lastIndex(where: { $0.workspaceId == workspaceId }) {
                tabs.insert(tab, at: tabs.index(after: workspaceLastIndex))
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
        armManagedAITrackingIfNeeded(for: tab)
    }

    private func armManagedAITrackingIfNeeded(for tab: AppTab) {
        guard tab.isManagedCommand,
              let command = tab.command,
              let aiKind = ShellDetectedAIPaneKind(submittedLine: command) else {
            return
        }

        shellDetectedAIPaneKinds[tab.id] = aiKind
        aiTabsAwaitingInitialPromptTitle[tab.id] = aiKind

        if aiKind == .claude, claudeTabActivities[tab.id]?.kind != .needsInput {
            claudeTabActivities[tab.id] = ClaudeTabActivity(
                kind: .running,
                summary: nil,
                updatedAt: .now
            )
        }
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
        tmuxIntegrationEnabled && tab.isShell && tab.command == nil && tab.workspaceSetupPaneId != nil
    }

    private func isReusableTmuxEditorTab(_ tab: AppTab) -> Bool {
        guard shouldUseTmux(for: tab) else { return false }
        return tab.label == "Neovim" || tab.label == "Vim"
    }

    private func preferredTmuxEditorTab(for workspaceId: String) -> AppTab? {
        if let activeTabId,
           let activeTab = tabsById[activeTabId],
           activeTab.workspaceId == workspaceId,
           isReusableTmuxEditorTab(activeTab) {
            return activeTab
        }

        return workspaceTabs(for: workspaceId).first(where: isReusableTmuxEditorTab)
    }

    func makeWorkspaceSetupPaneId() -> String {
        UUID().uuidString.lowercased()
    }

    private func tmuxAttachCommand(workspace: Workspace, tab: AppTab, workingDirectory: String) -> String {
        guard let paneId = tab.workspaceSetupPaneId else { return "exec false" }
        let baseSession = tmuxBaseSessionName(for: workspace.id)
        let clientSession = tmuxClientSessionName(workspaceId: workspace.id, paneId: paneId)
        let windowName = tmuxWindowName(for: paneId)
        let tmuxPrefix = tmuxCommandPrefix()
        let baseTarget = shellQuote(baseSession)
        let clientTarget = shellQuote(clientSession)
        let windowTarget = shellQuote(windowName)
        let sessionWindowTarget = shellQuote("\(clientSession):\(windowName)")
        let workingDirectoryArg = shellQuote(workingDirectory)
        let shellCommand = tmuxShellLaunchCommand(workspace: workspace, tab: tab)

        let ensureBaseSession = "\(tmuxPrefix) has-session -t \(baseTarget) 2>/dev/null || \(tmuxPrefix) new-session -d -s \(baseTarget) -n \(windowTarget) -c \(workingDirectoryArg) \(shellCommand)"
        let ensureWindow = "\(tmuxPrefix) list-windows -t \(baseTarget) -F '#{window_name}' 2>/dev/null | grep -Fqx -- \(windowTarget) || \(tmuxPrefix) new-window -d -t \(baseTarget) -n \(windowTarget) -c \(workingDirectoryArg) \(shellCommand)"
        let ensureClientSession = "\(tmuxPrefix) has-session -t \(clientTarget) 2>/dev/null || \(tmuxPrefix) new-session -d -t \(baseTarget) -s \(clientTarget)"
        let configureClient = "\(tmuxPrefix) set-option -t \(clientTarget) status off >/dev/null 2>&1; \(tmuxPrefix) set-option -t \(clientTarget) allow-rename off >/dev/null 2>&1"
        let selectWindow = "\(tmuxPrefix) select-window -t \(sessionWindowTarget) >/dev/null 2>&1"
        let attachClient = "exec \(tmuxPrefix) attach-session -t \(clientTarget)"

        return [ensureBaseSession, ensureWindow, ensureClientSession, configureClient, selectWindow, attachClient]
            .joined(separator: "; ")
    }

    private func destroyTmuxPane(workspaceId: String, paneId: String) {
        guard tmuxIntegrationEnabled else { return }
        let baseSession = tmuxBaseSessionName(for: workspaceId)
        let clientSession = tmuxClientSessionName(workspaceId: workspaceId, paneId: paneId)
        let windowName = tmuxWindowName(for: paneId)
        let tmuxPrefix = tmuxCommandPrefix()

        runDetachedShellCommand("""
        \(tmuxPrefix) kill-session -t \(shellQuote(clientSession)) >/dev/null 2>&1 || true
        \(tmuxPrefix) kill-window -t \(shellQuote("\(baseSession):\(windowName)")) >/dev/null 2>&1 || true
        """)
    }

    private func destroyTmuxWorkspaceSession(workspaceId: String, paneIds: [String]) {
        guard tmuxIntegrationEnabled else { return }
        let baseSession = tmuxBaseSessionName(for: workspaceId)
        let tmuxPrefix = tmuxCommandPrefix()
        let clientKills = paneIds.map {
            "\(tmuxPrefix) kill-session -t \(shellQuote(tmuxClientSessionName(workspaceId: workspaceId, paneId: $0))) >/dev/null 2>&1 || true"
        }

        runDetachedShellCommand((clientKills + [
            "\(tmuxPrefix) kill-session -t \(shellQuote(baseSession)) >/dev/null 2>&1 || true",
        ]).joined(separator: "\n"))
    }

    private func focusExistingTmuxEditorTab(
        workspaceId: String,
        path: String,
        line: Int?,
        column: Int?
    ) -> Bool {
        guard let tab = preferredTmuxEditorTab(for: workspaceId),
              let paneId = tab.workspaceSetupPaneId else {
            return false
        }

        let foregroundCommand = tmuxPaneCurrentCommand(workspaceId: workspaceId, paneId: paneId)
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
                workspaceId: workspaceId,
                paneId: paneId,
                text: vimOpenCommand(path: path, line: line, column: column)
            ))
        } else {
            guard let workspace = workspaces.first(where: { $0.id == workspaceId }) else { return false }
            runDetachedShellCommand(tmuxSendShellCommand(
                tab: tab,
                workspace: workspace,
                workingDirectory: effectiveWorkingDirectory(tab.workingDirectory, workspaceId: workspaceId),
                text: NvimLauncher.command(
                    theme: TerminalTheme.load(name: theme),
                    path: path,
                    line: line,
                    column: column
                )
            ))
        }

        setActiveTab(tab.id)
        activateTerminalFocusSoon()
        return true
    }

    private func openFileInNewTmuxEditorTab(
        workspaceId: String,
        path: String,
        line: Int?,
        column: Int?
    ) {
        let workingDirectory = URL(fileURLWithPath: path)
            .deletingLastPathComponent()
            .path
        let tab = openTab(
            workspaceId: workspaceId,
            command: nil,
            label: "Neovim",
            workingDirectory: workingDirectory
        )

        pendingTmuxShellCommands[tab.id] = NvimLauncher.command(
            theme: TerminalTheme.load(name: theme),
            path: path,
            line: line,
            column: column
        )
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

    private func tmuxBaseSessionName(for workspaceId: String) -> String {
        "blink-\(workspaceId)"
    }

    private func tmuxClientSessionName(workspaceId: String, paneId: String) -> String {
        "blink-\(workspaceId)-\(paneId)"
    }

    private func tmuxWindowName(for paneId: String) -> String {
        "pane-\(paneId)"
    }

    private func tmuxWindowTarget(workspaceId: String, paneId: String) -> String {
        "\(tmuxBaseSessionName(for: workspaceId)):\(tmuxWindowName(for: paneId))"
    }

    private func tmuxShellLaunchCommand(workspace: Workspace, tab: AppTab) -> String {
        let shell = UserDefaults.standard.string(forKey: "blink.shell")
            ?? ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shellName = URL(fileURLWithPath: shell).lastPathComponent
        var assignments: [(String, String)] = [
            ("BLINK_TAB_ID", tab.id),
            ("BLINK_PANE_ID", tab.workspaceSetupPaneId ?? tab.id),
            ("BLINK_PROJECT_ID", workspace.id),
            ("BLINK_PROJECT_NAME", workspace.name),
            ("BLINK_PROJECT_PATH", workspace.path),
        ]

        if let hookEventDirectoryPath = claudeHookEventDirectoryPath, !hookEventDirectoryPath.isEmpty {
            assignments.append(("BLINK_HOOK_EVENT_DIR", hookEventDirectoryPath))
        }
        var pathPrefixes: [String] = []
        if let wrapperBinPath = NvimLauncher.wrapperBinPath(), !wrapperBinPath.isEmpty {
            pathPrefixes.append(wrapperBinPath)
        }
        if let realNvimPath = NvimLauncher.resolvedNvimBinaryPath(), !realNvimPath.isEmpty {
            assignments.append(("BLINK_REAL_NVIM", realNvimPath))
        }
        if let nvimWrapperPath = NvimLauncher.wrapperCommandPath(), !nvimWrapperPath.isEmpty {
            assignments.append(("BLINK_NVIM_WRAPPER_PATH", nvimWrapperPath))
            assignments.append(("BLINK_VIM_WRAPPER_PATH", nvimWrapperPath))
        }
        if let hookScriptDirectoryPath = claudeHookScriptPath, !hookScriptDirectoryPath.isEmpty {
            let wrapperPath = (hookScriptDirectoryPath as NSString).appendingPathComponent("claude")
            assignments.append(("BLINK_CLAUDE_WRAPPER_PATH", wrapperPath))
            pathPrefixes.append(hookScriptDirectoryPath)
        }

        if !pathPrefixes.isEmpty {
            let inheritedPATH = ProcessInfo.processInfo.environment["PATH"] ?? ""
            let inheritedEntries = inheritedPATH.split(separator: ":").map(String.init)
            var seen = Set<String>()
            var mergedEntries: [String] = []

            for entry in pathPrefixes + inheritedEntries {
                guard !entry.isEmpty, seen.insert(entry).inserted else { continue }
                mergedEntries.append(entry)
            }

            assignments.append(("PATH", mergedEntries.joined(separator: ":")))
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

    private func tmuxEnsureWindowCommand(tab: AppTab, workspace: Workspace, workingDirectory: String) -> String {
        guard let paneId = tab.workspaceSetupPaneId else { return "true" }
        let tmuxPrefix = tmuxCommandPrefix()
        let baseSession = tmuxBaseSessionName(for: workspace.id)
        let windowName = tmuxWindowName(for: paneId)
        let baseTarget = shellQuote(baseSession)
        let windowTarget = shellQuote(windowName)
        let workingDirectoryArg = shellQuote(workingDirectory)
        let shellCommand = tmuxShellLaunchCommand(workspace: workspace, tab: tab)

        let ensureBaseSession = "\(tmuxPrefix) has-session -t \(baseTarget) 2>/dev/null || \(tmuxPrefix) new-session -d -s \(baseTarget) -n \(windowTarget) -c \(workingDirectoryArg) \(shellCommand)"
        let ensureWindow = "\(tmuxPrefix) list-windows -t \(baseTarget) -F '#{window_name}' 2>/dev/null | grep -Fqx -- \(windowTarget) || \(tmuxPrefix) new-window -d -t \(baseTarget) -n \(windowTarget) -c \(workingDirectoryArg) \(shellCommand)"

        return [ensureBaseSession, ensureWindow].joined(separator: "; ")
    }

    private static func tmuxSocketName() -> String {
        let bundleId = Bundle.main.bundleIdentifier ?? "com.blink.app"
        return bundleId.replacingOccurrences(of: ".", with: "-")
    }

    private static func installBlinkTmuxConfig(bundleIdentifier: String) -> URL? {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directoryURL = baseURL
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("tmux", isDirectory: true)
        let configURL = directoryURL.appendingPathComponent("blink.tmux.conf")

        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let contents = blinkTmuxConfigContents
            let existingContents = try? String(contentsOf: configURL, encoding: .utf8)
            if existingContents != contents {
                try contents.write(to: configURL, atomically: true, encoding: .utf8)
            }
            return configURL
        } catch {
            print("[AppStore] Failed to install Blink tmux config: \(error)")
            return nil
        }
    }

    private static func detectTmuxAvailability() -> Bool {
        let candidates = [
            "/opt/homebrew/bin/tmux",
            "/usr/local/bin/tmux",
            "/usr/bin/tmux",
        ]

        return candidates.contains { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func tmuxCommandPrefix() -> String {
        Self.tmuxCommandPrefix(socketName: tmuxSocketName, configPath: tmuxConfigPath)
    }

    nonisolated private static func tmuxCommandPrefix(socketName: String, configPath: String?) -> String {
        var prefix = "env -u TMUX tmux -L \(shellQuote(socketName))"
        if let configPath, !configPath.isEmpty {
            prefix += " -f \(shellQuote(configPath))"
        }
        return prefix
    }

    private static let blinkTmuxConfigContents = """
    # Blink uses tmux only for persistence and reattachment.
    # Keep this config intentionally minimal and separate from personal tmux setup.
    setw -g mode-keys vi
    set -g history-limit 10000
    set -g default-terminal "tmux-256color"
    set -g focus-events on
    set -s escape-time 0
    set -s extended-keys always
    set -as terminal-features 'xterm*:extkeys'
    set -as terminal-features ",*:RGB"
    set -ag terminal-overrides ",xterm-256color:RGB"
    set -g mouse on
    set -g status off
    set -g allow-rename off
    set -g set-titles off
    """

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

    private func resolveExistingWorkspaceFilePath(_ path: String, workspaceId: String) -> String? {
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        guard !FileManager.default.fileExists(atPath: normalizedPath),
              let workspacePath = workspaces.first(where: { $0.id == workspaceId })?.path else {
            return FileManager.default.fileExists(atPath: normalizedPath) ? normalizedPath : nil
        }

        let normalizedWorkspacePath = URL(fileURLWithPath: workspacePath, isDirectory: true)
            .standardizedFileURL
            .path
        let relativeCandidates = candidateWorkspacePathSuffixes(
            for: normalizedPath,
            workspacePath: normalizedWorkspacePath
        )

        for suffix in relativeCandidates {
            let matches = matchingWorkspaceFiles(
                under: normalizedWorkspacePath,
                suffix: suffix
            )
            if matches.count == 1 {
                return matches[0]
            }
        }

        return nil
    }

    private func candidateWorkspacePathSuffixes(for path: String, workspacePath: String) -> [String] {
        var candidates: [String] = []
        let normalizedWorkspacePrefix = workspacePath.hasSuffix("/") ? workspacePath : "\(workspacePath)/"

        if path.hasPrefix(normalizedWorkspacePrefix) {
            let relativePath = String(path.dropFirst(normalizedWorkspacePrefix.count))
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

    private func matchingWorkspaceFiles(under workspacePath: String, suffix: String) -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: workspacePath, isDirectory: true),
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

    private func tmuxPaneCurrentCommand(workspaceId: String, paneId: String) -> String? {
        let tmuxPrefix = tmuxCommandPrefix()
        let target = shellQuote(tmuxWindowTarget(workspaceId: workspaceId, paneId: paneId))
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
              let paneId = tab.workspaceSetupPaneId else {
            return
        }

        let workspaceId = tab.workspaceId
        let resolvedCommand = await Self.fetchTmuxPaneCurrentCommand(
            workspaceId: workspaceId,
            paneId: paneId,
            socketName: Self.tmuxSocketName(),
            configPath: tmuxConfigPath
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
              let paneId = tab.workspaceSetupPaneId else {
            return
        }

        let workspaceId = tab.workspaceId
        Task { [weak self] in
            guard let self else { return }
            let resolvedCommand = await Self.fetchTmuxPaneCurrentCommand(
                workspaceId: workspaceId,
                paneId: paneId,
                socketName: Self.tmuxSocketName(),
                configPath: self.tmuxConfigPath
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

        let shouldPreserveAIState = shouldPreserveShellDetectedAIState(for: tabId, tab: tab)
        if shouldResetTerminalSubmittedLineTracking(
            for: tabId,
            preservingAIState: shouldPreserveAIState
        ) {
            resetTerminalSubmittedLineTracking(for: tabId)
        }
        if shouldPreserveAIState {
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

    private func resetTerminalSubmittedLineTracking(for tabId: String) {
        surfaceManager?.surface(for: tabId)?.clearSubmittedLineTracking()
    }

    private func shouldResetTerminalSubmittedLineTracking(
        for tabId: String,
        preservingAIState: Bool
    ) -> Bool {
        guard surfaceManager?.surface(for: tabId)?.hasTrackedSubmittedLine == true else {
            return false
        }

        if !preservingAIState {
            return shellDetectedAIPaneKinds[tabId] != nil || claudeTabActivities[tabId] != nil
        }

        guard let aiKind = shellDetectedAIPaneKinds[tabId] else { return true }
        return aiTabsAwaitingInitialPromptTitle[tabId] != aiKind
    }

    private func shouldPreserveShellDetectedAIState(for tabId: String, tab: AppTab) -> Bool {
        guard let aiKind = shellDetectedAIPaneKinds[tabId] else { return false }
        if aiTabsAwaitingInitialPromptTitle[tabId] == aiKind {
            return true
        }
        return shouldPreserveCustomAITitle(for: tab, displayName: aiKind.displayName)
    }

    func resolvedSelectableTabId(for workspaceId: String, preferred: [String]) -> String? {
        let workspaceTabIds = Set(workspaceTabs(for: workspaceId).map(\.id))
        let workspaceCols = workspaceColumns(for: workspaceId)

        func selectable(_ tabId: String?) -> String? {
            guard let tabId,
                  workspaceTabIds.contains(tabId),
                  workspaceCols.contains(where: { $0.tabIds.contains(tabId) }) else {
                return nil
            }
            return tabId
        }

        for tabId in preferred {
            if let selectable = selectable(tabId) {
                return selectable
            }
        }

        if let remembered = selectable(lastActiveTab[workspaceId]) {
            return remembered
        }

        for column in workspaceCols {
            if let focused = selectable(columnFocusedTab[column.id]) {
                return focused
            }
        }

        return workspaceCols.first?.tabIds.first ?? workspaceTabs(for: workspaceId).first?.id
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
        workspaceId: String,
        paneId: String,
        socketName: String,
        configPath: String?
    ) async -> String? {
        await Task.detached(priority: .utility) {
            let tmuxPrefix = tmuxCommandPrefix(socketName: socketName, configPath: configPath)
            let target = shellQuote("blink-\(workspaceId):pane-\(paneId)")
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

    private func tmuxSendKeysCommand(workspaceId: String, paneId: String, text: String) -> String {
        let tmuxPrefix = tmuxCommandPrefix()
        let target = shellQuote(tmuxWindowTarget(workspaceId: workspaceId, paneId: paneId))
        let literalText = shellQuote(text)

        return [
            "\(tmuxPrefix) send-keys -t \(target) Escape",
            "\(tmuxPrefix) send-keys -t \(target) -l \(literalText)",
            "\(tmuxPrefix) send-keys -t \(target) Enter",
        ].joined(separator: "; ")
    }

    private func tmuxSendShellCommand(
        tab: AppTab,
        workspace: Workspace,
        workingDirectory: String,
        text: String
    ) -> String {
        guard let paneId = tab.workspaceSetupPaneId else { return "true" }
        let tmuxPrefix = tmuxCommandPrefix()
        let target = shellQuote(tmuxWindowTarget(workspaceId: workspace.id, paneId: paneId))
        let literalText = shellQuote(text)

        return [
            tmuxEnsureWindowCommand(tab: tab, workspace: workspace, workingDirectory: workingDirectory),
            "\(tmuxPrefix) send-keys -t \(target) -l \(literalText)",
            "\(tmuxPrefix) send-keys -t \(target) Enter",
        ].joined(separator: "; ")
    }

    @discardableResult
    private func sendPendingTmuxShellCommandIfNeeded(for tabId: String) -> Bool {
        guard let text = pendingTmuxShellCommands.removeValue(forKey: tabId),
              let tab = tabsById[tabId],
              let workspace = workspaces.first(where: { $0.id == tab.workspaceId }) else {
            return false
        }

        runDetachedShellCommand(tmuxSendShellCommand(
            tab: tab,
            workspace: workspace,
            workingDirectory: effectiveWorkingDirectory(tab.workingDirectory, workspaceId: tab.workspaceId),
            text: text
        ))
        return true
    }

    /// Re-number default tab labels ("Terminal 1", "Terminal 2", ...) for a workspace.
    private func reindexTabs(for workspaceId: String) {
        var counter = 0
        for i in tabs.indices where tabs[i].workspaceId == workspaceId && tabs[i].isShell && tabs[i].command == nil {
            counter += 1
            let newDefault = "Terminal \(counter)"
            if tabs[i].label == tabs[i].defaultLabel {
                tabs[i].label = newDefault
            }
            tabs[i].defaultLabel = newDefault
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
