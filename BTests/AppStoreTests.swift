import XCTest
@testable import Blink

@MainActor
final class AppStoreTests: XCTestCase {
    private let fileManager = FileManager.default
    private let defaults = UserDefaults.standard
    private let storageKeys = [
        "blink.theme",
        "blink.backgroundImage",
        "blink.backgroundOpacity",
        "blink.backgroundBlur",
        "blink.hideTitleBar",
        "blink.sidebarVisible",
        "blink.projects",
        "blink.lastSelectedProjectId",
        "blink.lastActiveTabs",
        "blink.workspaceViewportOffsets",
        "blink.columns",
        "blink.projectSetups",
        "blink.fileEditorLauncher",
        "blink.fileEditorCustomCommand",
    ]

    private var savedDefaults: [String: Any?] = [:]

    override func setUpWithError() throws {
        savedDefaults = [:]
        for key in storageKeys {
            savedDefaults[key] = defaults.object(forKey: key)
            defaults.removeObject(forKey: key)
        }
    }

    override func tearDownWithError() throws {
        for key in storageKeys {
            if let value = savedDefaults[key] {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

    func testInitialState() {
        let store = AppStore()
        XCTAssertEqual(store.projects.count, 0)
        XCTAssertNil(store.activeProjectId)
        XCTAssertNil(store.activeTabId)
        XCTAssertTrue(store.sidebarVisible)
        XCTAssertTrue(store.expandedProjectIds.isEmpty)
    }

    func testSetActiveProjectActivatesFirstTab() {
        let store = makeStore()
        store.setActiveProject("1")
        XCTAssertEqual(store.activeProjectId, "1")
        XCTAssertEqual(store.activeTabId, "t1")
    }

    func testSetActiveProjectNoTabs() {
        let store = makeStore()
        store.setActiveProject("4")
        XCTAssertEqual(store.activeProjectId, "4")
        XCTAssertNil(store.activeTabId)
    }

    func testClearActiveProject() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveProject(nil)
        XCTAssertNil(store.activeProjectId)
        XCTAssertNil(store.activeTabId)
    }

    func testProjectTabs() {
        let store = makeStore()
        let tabs = store.projectTabs(for: "1")
        XCTAssertEqual(tabs.count, 2)
        XCTAssertEqual(tabs[0].label, "Terminal 1")
    }

    func testRemoveProject() {
        let store = makeStore()
        store.removeProject("1")
        XCTAssertEqual(store.projects.count, 3)
        XCTAssertFalse(store.projects.contains(where: { $0.id == "1" }))
    }

    func testRemoveActiveProjectClearsSelection() {
        let store = makeStore()
        store.setActiveProject("1")
        store.removeProject("1")
        XCTAssertNil(store.activeProjectId)
        XCTAssertNil(store.activeTabId)
    }

    func testTerminalCount() {
        let store = makeStore()
        XCTAssertEqual(store.terminalCount(for: "1"), 2)
        XCTAssertEqual(store.terminalCount(for: "2"), 1)
        XCTAssertEqual(store.terminalCount(for: "4"), 0)
    }

    func testSetActiveTab() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t2")
        XCTAssertEqual(store.activeTabId, "t2")
    }

    func testSelectNextTabWrapsWithinProject() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t2")

        store.selectNextTab()

        XCTAssertEqual(store.activeTabId, "t1")
    }

    func testSelectPreviousTabWrapsWithinProject() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t1")

        store.selectPreviousTab()

        XCTAssertEqual(store.activeTabId, "t2")
    }

    func testCloseTab() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t1")
        store.closeTab("t1")
        XCTAssertEqual(store.activeTabId, "t2")
        XCTAssertEqual(store.tabs.count, 2)
    }

    func testManagedCommandTabStartsRunning() {
        let store = makeStore()

        store.openOrFocusCommandTab(projectId: "1", command: "npm run dev", label: "Dev Server")

        let commandTabs = store.projectTabs(for: "1").filter { $0.command == "npm run dev" }
        XCTAssertEqual(commandTabs.count, 1)
        XCTAssertEqual(store.managedCommandStatus(for: commandTabs[0].id), .running)
    }

    func testManagedCommandExitStopsTabInsteadOfClosingIt() {
        let store = makeStore()
        store.openOrFocusCommandTab(projectId: "1", command: "npm run dev", label: "Dev Server")
        let tabId = try! XCTUnwrap(store.projectTabs(for: "1").first(where: { $0.command == "npm run dev" })?.id)

        let handled = store.handleProcessExit(for: tabId)

        XCTAssertTrue(handled)
        XCTAssertNotNil(store.tabsById[tabId])
        XCTAssertEqual(store.managedCommandStatus(for: tabId), .stopped)
    }

    func testOpenOrFocusCommandTabRestartsStoppedPaneWithoutDuplicatingIt() {
        let store = makeStore()
        store.openOrFocusCommandTab(projectId: "1", command: "npm run dev", label: "Dev Server")
        let tabId = try! XCTUnwrap(store.projectTabs(for: "1").first(where: { $0.command == "npm run dev" })?.id)
        _ = store.handleProcessExit(for: tabId)

        store.openOrFocusCommandTab(projectId: "1", command: "npm run dev", label: "Dev Server")

        let commandTabs = store.projectTabs(for: "1").filter { $0.command == "npm run dev" }
        XCTAssertEqual(commandTabs.count, 1)
        XCTAssertEqual(commandTabs[0].id, tabId)
        XCTAssertEqual(store.managedCommandStatus(for: tabId), .running)
    }

    func testOpenManagedAIPaneUsesProviderNameUntilFirstPromptIsSubmitted() {
        let store = makeStore()
        store.openManagedAIPane(.codex, projectId: "1")

        let tab = try! XCTUnwrap(store.projectTabs(for: "1").first(where: { $0.managedAIPaneKind == .codex }))
        XCTAssertEqual(tab.command, "codex --no-alt-screen")
        XCTAssertEqual(tab.label, "Codex")
        XCTAssertEqual(tab.defaultLabel, "Codex")

        let applied = store.applyManagedAIPromptTitleIfNeeded("Fix autosave restore", for: tab.id)

        XCTAssertTrue(applied)
        let updatedTab = try! XCTUnwrap(store.tabsById[tab.id])
        XCTAssertEqual(updatedTab.label, "Fix autosave restore")
        XCTAssertEqual(updatedTab.defaultLabel, "Fix autosave restore")
    }

    func testOpenManagedCodexPaneReusesExistingLegacyCodexCommandTab() {
        let store = makeStore()
        let existing = store.openOrFocusCommandTab(projectId: "1", command: "codex", label: "Codex")

        store.openManagedAIPane(.codex, projectId: "1")

        let codexTabs = store.projectTabs(for: "1").filter { $0.managedAIPaneKind == .codex }
        XCTAssertEqual(codexTabs.count, 1)
        XCTAssertEqual(codexTabs.first?.id, existing.id)
        XCTAssertEqual(store.activeTabId, existing.id)
    }

    func testManagedAIPromptTitleIsOnlyAppliedOnce() {
        let store = makeStore()
        store.activeProjectId = "2"
        store.openManagedAIPane(.claude)

        let tab = try! XCTUnwrap(store.projectTabs(for: "2").first(where: { $0.command == "claude" }))
        XCTAssertTrue(store.applyManagedAIPromptTitleIfNeeded("Review workspace restore", for: tab.id))
        XCTAssertFalse(store.applyManagedAIPromptTitleIfNeeded("Something else", for: tab.id))

        let updatedTab = try! XCTUnwrap(store.tabsById[tab.id])
        XCTAssertEqual(updatedTab.label, "Review workspace restore")
        XCTAssertEqual(updatedTab.defaultLabel, "Review workspace restore")
    }

    func testShellStartedCodexAdoptsFirstPromptTitleAndRevertsOnShellPrompt() {
        let store = makeStore()
        let tabId = "t1"

        store.handleTerminalLineSubmission("codex", for: tabId)

        var updatedTab = try! XCTUnwrap(store.tabsById[tabId])
        XCTAssertEqual(updatedTab.label, "Codex")
        XCTAssertEqual(updatedTab.defaultLabel, "Terminal 1")

        XCTAssertFalse(store.applyManagedAIPromptTitleIfNeeded("codex", for: tabId))
        XCTAssertTrue(store.applyManagedAIPromptTitleIfNeeded("Fix autosave restore", for: tabId))

        updatedTab = try! XCTUnwrap(store.tabsById[tabId])
        XCTAssertEqual(updatedTab.label, "Fix autosave restore")
        XCTAssertEqual(updatedTab.defaultLabel, "Terminal 1")

        store.handleTerminalTitleUpdate("zsh", for: tabId)

        updatedTab = try! XCTUnwrap(store.tabsById[tabId])
        XCTAssertEqual(updatedTab.label, "Terminal 1")
        XCTAssertEqual(updatedTab.defaultLabel, "Terminal 1")
    }

    func testShellStartedClaudePromptTitleIsNotClobberedByLaterProviderTitles() {
        let store = makeStore()
        let tabId = "t1"

        store.handleTerminalLineSubmission("claude", for: tabId)
        XCTAssertFalse(store.applyManagedAIPromptTitleIfNeeded("claude", for: tabId))
        XCTAssertTrue(store.applyManagedAIPromptTitleIfNeeded("Review the sidebar tree", for: tabId))

        store.handleTerminalTitleUpdate("claude", for: tabId)

        let updatedTab = try! XCTUnwrap(store.tabsById[tabId])
        XCTAssertEqual(updatedTab.label, "Review the sidebar tree")
        XCTAssertEqual(updatedTab.defaultLabel, "Terminal 1")
    }

    func testShellStartedClaudeYoloIsDetectedFromSubmittedLine() {
        let store = makeStore()
        let tabId = "t1"

        store.handleTerminalLineSubmission("claude --dangerously-skip-permissions", for: tabId)

        let updatedTab = try! XCTUnwrap(store.tabsById[tabId])
        XCTAssertEqual(updatedTab.label, "Claude Code")
        XCTAssertEqual(updatedTab.defaultLabel, "Terminal 1")
    }

    func testRestoredManagedAIPaneCanStillAdoptFirstPromptTitle() {
        let store = makeStore()
        store.openManagedAIPane(.claude, projectId: "1")

        let originalTab = try! XCTUnwrap(store.projectTabs(for: "1").first(where: { $0.command == "claude" }))
        let originalSetup = try! XCTUnwrap(store.projectSetup(for: "1"))

        store.tabs.removeAll()
        store.columns["1"] = []
        store.activeProjectId = "1"
        store.activeTabId = nil
        store.projectSetups["1"] = originalSetup

        store.restoreProjectSetup(for: "1")

        let restoredTab = try! XCTUnwrap(store.projectTabs(for: "1").first(where: { $0.command == "claude" }))
        XCTAssertNotEqual(restoredTab.id, originalTab.id)
        XCTAssertEqual(restoredTab.label, "Claude Code")

        let applied = store.applyManagedAIPromptTitleIfNeeded("Audit the window resizing regression", for: restoredTab.id)

        XCTAssertTrue(applied)
        let updatedTab = try! XCTUnwrap(store.tabsById[restoredTab.id])
        XCTAssertEqual(updatedTab.label, "Audit the window resizing regression")
        XCTAssertEqual(updatedTab.defaultLabel, "Audit the window resizing regression")
    }

    func testHideTitleBarPersists() {
        XCTAssertFalse(AppStore().hideTitleBar)

        let store = AppStore()
        store.hideTitleBar = true

        XCTAssertTrue(AppStore().hideTitleBar)
    }

    func testLastActiveTabPersistsPerProject() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t2")

        let reloaded = AppStore()
        reloaded.projects = store.projects
        reloaded.tabs = store.tabs

        reloaded.setActiveProject("1")

        XCTAssertEqual(reloaded.activeTabId, "t2")
    }

    func testWorkspaceViewportOffsetPersists() {
        let store = AppStore()
        store.setWorkspaceViewportOffset(184, for: "1")

        XCTAssertEqual(AppStore().workspaceViewportOffset(for: "1"), 184, accuracy: 0.001)
    }

    func testProjectSessionAutosavesCurrentLayout() {
        let store = makeStore()
        let setup = store.projectSetup(for: "1")

        XCTAssertNotNil(setup)
        XCTAssertEqual(setup?.columns.count, 2)
        XCTAssertEqual(setup?.panes.count, 2)
        XCTAssertEqual(setup?.panes.map(\.label), ["Terminal 1", "Terminal 2"])
    }

    func testRestoreProjectSetupRebuildsTabsAndColumns() {
        let store = makeStore()
        XCTAssertNotNil(store.projectSetup(for: "1"))

        store.tabs.removeAll { $0.projectId == "1" }
        store.columns["1"] = []
        store.activeProjectId = "1"
        store.activeTabId = nil

        store.restoreProjectSetup(for: "1")

        XCTAssertEqual(store.projectTabs(for: "1").count, 2)
        XCTAssertEqual(store.projectColumns(for: "1").count, 2)
        XCTAssertNotNil(store.activeTabId)
    }

    func testOpenProjectSessionRestoresAutosavedSessionWhenNoLiveTabs() {
        let store = makeStore()
        XCTAssertNotNil(store.projectSetup(for: "1"))

        store.tabs.removeAll { $0.projectId == "1" }
        store.columns["1"] = []

        store.openProjectSession("1")

        XCTAssertEqual(store.projectTabs(for: "1").count, 2)
        XCTAssertEqual(store.projectColumns(for: "1").count, 2)
    }

    func testEmptyRuntimeDoesNotEraseAutosavedProjectSession() {
        let store = makeStore()
        let savedSetup = try! XCTUnwrap(store.projectSetup(for: "1"))

        store.tabs.removeAll { $0.projectId == "1" }
        store.columns["1"] = []

        XCTAssertEqual(store.projectSetup(for: "1"), savedSetup)
    }

    func testFocusLeftFromFirstColumnGoesToSidebar() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t1")
        store.sidebarVisible = true
        store.sidebarFocused = false

        store.focusLeft()

        XCTAssertTrue(store.sidebarFocused)
    }

    func testFocusLeftFromFirstColumnNoOpWhenSidebarClosed() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t1")
        store.sidebarVisible = false

        store.focusLeft()

        XCTAssertEqual(store.activeTabId, "t1")
        XCTAssertFalse(store.sidebarFocused)
    }

    func testFocusRightFromSidebarGoesToTerminal() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t1")
        store.sidebarFocused = true

        store.focusRight()

        XCTAssertFalse(store.sidebarFocused)
        XCTAssertEqual(store.activeTabId, "t1")
    }

    func testFocusRightNoOpAtLastColumn() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t2")

        store.focusRight()

        XCTAssertEqual(store.activeTabId, "t2")
    }

    func testFocusLeftBetweenColumns() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t2")
        store.sidebarVisible = false

        store.focusLeft()

        XCTAssertEqual(store.activeTabId, "t1")
    }

    func testFocusRightBetweenColumns() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t1")

        store.focusRight()

        XCTAssertEqual(store.activeTabId, "t2")
    }

    // MARK: - Overview Tests

    func testToggleOverviewEntersAndExits() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t1")

        store.toggleOverview()

        XCTAssertTrue(store.isOverviewMode)
        XCTAssertEqual(store.overviewHighlightedColumnId, "c1")

        store.toggleOverview()

        XCTAssertFalse(store.isOverviewMode)
        XCTAssertNil(store.overviewHighlightedColumnId)
    }

    func testEnterOverviewSetsHighlight() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t2")

        store.toggleOverview()

        XCTAssertEqual(store.overviewHighlightedColumnId, "c2")
    }

    func testOverviewHighlightLeftRight() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t1")
        store.toggleOverview()

        store.overviewHighlightRight()
        XCTAssertEqual(store.overviewHighlightedColumnId, "c2")

        store.overviewHighlightLeft()
        XCTAssertEqual(store.overviewHighlightedColumnId, "c1")
    }

    func testOverviewHighlightStopsAtEdges() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t1")
        store.toggleOverview()

        store.overviewHighlightLeft()
        XCTAssertEqual(store.overviewHighlightedColumnId, "c1")

        store.overviewHighlightRight()
        store.overviewHighlightRight()
        XCTAssertEqual(store.overviewHighlightedColumnId, "c2")
    }

    func testExitOverviewWithSelection() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t1")
        store.toggleOverview()

        store.exitOverview(selecting: "c2")

        XCTAssertFalse(store.isOverviewMode)
        XCTAssertNil(store.overviewHighlightedColumnId)
        XCTAssertEqual(store.activeTabId, "t2")
    }

    func testExitOverviewCancelKeepsOriginal() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t1")
        store.toggleOverview()

        store.overviewHighlightRight()
        store.exitOverview(selecting: nil)

        XCTAssertFalse(store.isOverviewMode)
        XCTAssertEqual(store.activeTabId, "t1")
    }

    func testOverviewNoOpWithNoTabs() {
        let store = makeStore()
        store.setActiveProject("4")

        store.toggleOverview()

        XCTAssertFalse(store.isOverviewMode)
        XCTAssertNil(store.overviewHighlightedColumnId)
    }

    // MARK: - Column Migration Tests

    func testOpenTabCreatesColumn() {
        let store = makeStore()
        store.setActiveProject("1")
        let tab = store.openTab(projectId: "1")
        let cols = store.projectColumns(for: "1")
        XCTAssertEqual(cols.count, 3) // 2 existing + 1 new
        XCTAssertEqual(cols.last?.tabIds, [tab.id])
    }

    func testNewShellTabsGetStableProjectPaneIds() {
        let store = makeStore()
        store.setActiveProject("1")

        let tab = store.openTab(projectId: "1")
        let paneId = try! XCTUnwrap(tab.projectSetupPaneId)
        let setup = try! XCTUnwrap(store.projectSetup(for: "1"))

        XCTAssertTrue(setup.panes.contains(where: { $0.id == paneId }))
    }

    func testPlainShellTabsLaunchThroughTmuxWhenPaneIdExists() {
        let store = makeStore()
        store.setActiveProject("1")
        let tab = store.openTab(projectId: "1")
        let project = try! XCTUnwrap(store.projects.first(where: { $0.id == "1" }))

        let command = store.terminalLaunchCommand(for: tab, project: project)

        XCTAssertNotNil(command)
        XCTAssertTrue(command?.contains("tmux -L") == true)
        XCTAssertTrue(command?.contains("attach-session") == true)
        XCTAssertTrue(command?.contains("new-session -d -t") == true)
        XCTAssertTrue(command?.contains("env -u TMUX tmux") == true)
        XCTAssertFalse(command?.contains("exec TMUX=") == true)
    }

    func testCloseTmuxBackedShellTabCleansUpClientSessionAndWindow() {
        let store = makeStore()
        store.setActiveProject("1")
        let tab = store.openTab(projectId: "1")
        let paneId = try! XCTUnwrap(tab.projectSetupPaneId)
        var commands: [String] = []
        store.detachedShellCommandHandler = { commands.append($0) }

        store.closeTab(tab.id)

        let command = try! XCTUnwrap(commands.first)
        XCTAssertTrue(command.contains("kill-session -t 'blink-1-\(paneId)'"))
        XCTAssertTrue(command.contains("kill-window -t 'blink-1:pane-\(paneId)'"))
    }

    func testRemoveProjectCleansUpBaseTmuxSessionAndClientSessions() {
        let store = makeStore()
        store.setActiveProject("1")
        let first = store.openTab(projectId: "1")
        let second = store.openTab(projectId: "1")
        let firstPaneId = try! XCTUnwrap(first.projectSetupPaneId)
        let secondPaneId = try! XCTUnwrap(second.projectSetupPaneId)
        var commands: [String] = []
        store.detachedShellCommandHandler = { commands.append($0) }

        store.removeProject("1")

        let command = try! XCTUnwrap(commands.first)
        XCTAssertTrue(command.contains("kill-session -t 'blink-1-\(firstPaneId)'"))
        XCTAssertTrue(command.contains("kill-session -t 'blink-1-\(secondPaneId)'"))
        XCTAssertTrue(command.contains("kill-session -t 'blink-1'"))
    }

    func testOpenFileInEditorTargetsExistingTmuxNeovimTab() {
        let store = makeStore()
        store.setActiveProject("1")
        let editorTab = store.openTab(projectId: "1")
        let paneId = try! XCTUnwrap(editorTab.projectSetupPaneId)
        store.handleTerminalTitleUpdate("nvim", for: editorTab.id)
        var commands: [String] = []
        store.detachedShellCommandHandler = { commands.append($0) }

        store.openFileInEditor(projectId: "1", path: "/tmp/blink/Blink/Chat/ProjectChatView.swift", line: 42)

        let command = try! XCTUnwrap(commands.first)
        XCTAssertEqual(store.activeTabId, editorTab.id)
        XCTAssertTrue(command.contains("send-keys"))
        XCTAssertTrue(command.contains("blink-1:pane-\(paneId)"))
        XCTAssertTrue(command.contains("/tmp/blink/Blink/Chat/ProjectChatView.swift"))
        XCTAssertTrue(command.contains("call cursor(42, 1)"))
        XCTAssertTrue(command.contains("tab drop"))
        XCTAssertEqual(store.projectTabs(for: "1").count, 3)
    }

    func testOpenFileInEditorCreatesNewTmuxNeovimTabWhenNoEditorPaneExists() {
        let store = makeStore()
        store.setActiveProject("1")
        let initialCount = store.projectTabs(for: "1").count
        var commands: [String] = []
        store.detachedShellCommandHandler = { commands.append($0) }

        store.openFileInEditor(projectId: "1", path: "/tmp/blink/README.md", line: 12)

        let tabs = store.projectTabs(for: "1")
        XCTAssertEqual(tabs.count, initialCount + 1)
        let newTab = try! XCTUnwrap(tabs.last)
        let paneId = try! XCTUnwrap(newTab.projectSetupPaneId)
        XCTAssertEqual(newTab.label, "Neovim")
        XCTAssertNil(newTab.command)
        XCTAssertEqual(store.activeTabId, newTab.id)
        XCTAssertTrue(commands.isEmpty)

        store.handleTerminalSurfaceReady(for: newTab.id)

        let command = try! XCTUnwrap(commands.first)
        XCTAssertTrue(command.contains("blink-1:pane-\(paneId)"))
        XCTAssertTrue(command.contains("send-keys"))
        XCTAssertTrue(command.contains("nvim +12"))
        XCTAssertTrue(command.contains("/tmp/blink/README.md"))
    }

    func testOpenFileInEditorResolvesMissingProjectPathByUniqueSuffix() throws {
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let nestedDirectory = tempRoot
            .appendingPathComponent("Blink/Views", isDirectory: true)
        let actualFile = nestedDirectory.appendingPathComponent("Sidebar.swift")
        try fileManager.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
        try "struct SidebarView {}".write(to: actualFile, atomically: true, encoding: .utf8)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let store = makeStore()
        let originalProject = store.projects[0]
        store.projects[0] = Project(
            id: originalProject.id,
            name: originalProject.name,
            path: tempRoot.path,
            color: originalProject.color,
            createdAt: originalProject.createdAt
        )
        store.setActiveProject("1")
        var commands: [String] = []
        store.detachedShellCommandHandler = { commands.append($0) }

        store.openFileInEditor(
            projectId: "1",
            path: tempRoot.appendingPathComponent("Views/Sidebar.swift").path,
            line: 130
        )

        let newTab = try XCTUnwrap(store.projectTabs(for: "1").last)
        store.handleTerminalSurfaceReady(for: newTab.id)

        let command = try XCTUnwrap(commands.first)
        let missingPath = tempRoot.appendingPathComponent("Views/Sidebar.swift").path
        XCTAssertTrue(command.contains("nvim +130"))
        XCTAssertTrue(command.contains(actualFile.path))
        XCTAssertFalse(command.contains(missingPath))
    }

    func testOpenFileInEditorUsesExternalEditorLauncherWhenConfigured() {
        let store = makeStore()
        store.setActiveProject("1")
        store.fileEditorLauncher = .cursor
        let initialCount = store.projectTabs(for: "1").count
        var commands: [String] = []
        store.detachedShellCommandHandler = { commands.append($0) }

        store.openFileInEditor(
            projectId: "1",
            path: "/tmp/blink/Blink/Views/Sidebar.swift",
            line: 130,
            column: 4
        )

        let command = try! XCTUnwrap(commands.first)
        XCTAssertEqual(store.projectTabs(for: "1").count, initialCount)
        XCTAssertTrue(command.contains("cursor "))
        XCTAssertTrue(command.contains("/tmp/blink/Blink/Views/Sidebar.swift:130:4"))
    }

    func testOpenFileInEditorUsesCustomEditorCommandTemplate() {
        let store = makeStore()
        store.setActiveProject("1")
        store.fileEditorLauncher = .custom
        store.fileEditorCustomCommand = "custom-open --path {path} --line {line} --column {column}"
        var commands: [String] = []
        store.detachedShellCommandHandler = { commands.append($0) }

        store.openFileInEditor(
            projectId: "1",
            path: "/tmp/blink/Blink/Views/Sidebar.swift",
            line: 18,
            column: 2
        )

        let command = try! XCTUnwrap(commands.first)
        XCTAssertTrue(command.contains("custom-open --path "))
        XCTAssertTrue(command.contains("/tmp/blink/Blink/Views/Sidebar.swift"))
        XCTAssertTrue(command.contains("--line 18"))
        XCTAssertTrue(command.contains("--column 2"))
    }

    func testSplitActivePaneWithNewTabInsertsBelowActivePane() {
        let store = makeStore()
        store.setActiveProject("1")
        store.columns["1"] = [Column(id: "c1", tabIds: ["t1", "t2"])]
        store.setActiveTab("t1")

        store.splitActivePaneWithNewTab()

        let cols = store.projectColumns(for: "1")
        XCTAssertEqual(cols.count, 1)
        XCTAssertEqual(cols[0].tabIds.count, 3)
        XCTAssertEqual(cols[0].tabIds[0], "t1")
        XCTAssertEqual(cols[0].tabIds[2], "t2")
        XCTAssertEqual(store.activeTabId, cols[0].tabIds[1])
    }

    func testSplitActivePaneWithNewTabFallsBackToOpenTabWithoutActivePane() {
        let store = makeStore()
        store.setActiveProject("4")

        store.splitActivePaneWithNewTab()

        let cols = store.projectColumns(for: "4")
        XCTAssertEqual(cols.count, 1)
        XCTAssertEqual(cols[0].tabIds.count, 1)
        XCTAssertEqual(store.activeTabId, cols[0].tabIds[0])
    }

    func testSplitActiveColumnWithNewTabInsertsColumnToRight() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t1")

        store.splitActiveColumnWithNewTab()

        let cols = store.projectColumns(for: "1")
        XCTAssertEqual(cols.count, 3)
        XCTAssertEqual(cols[0].tabIds, ["t1"])
        XCTAssertEqual(cols[2].tabIds, ["t2"])
        XCTAssertEqual(cols[1].tabIds.count, 1)
        XCTAssertEqual(store.activeTabId, cols[1].tabIds[0])
    }

    func testCloseTabInMultiPaneColumnFocusesNext() {
        let store = makeStore()
        store.setActiveProject("1")
        // Stack t1 and t2 in same column
        store.columns["1"] = [Column(id: "c1", tabIds: ["t1", "t2"])]
        store.setActiveTab("t1")

        store.closeTab("t1")

        XCTAssertEqual(store.activeTabId, "t2")
        XCTAssertEqual(store.projectColumns(for: "1").count, 1)
        XCTAssertEqual(store.projectColumns(for: "1")[0].tabIds, ["t2"])
    }

    func testCloseLastTabInColumnRemovesColumn() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t1")

        store.closeTab("t1")

        XCTAssertEqual(store.projectColumns(for: "1").count, 1)
        XCTAssertEqual(store.activeTabId, "t2")
    }

    func testRemoveProjectCleansUpColumns() {
        let store = makeStore()
        store.columnFocusedTab["c1"] = "t1"
        store.removeProject("1")
        XCTAssertNil(store.columns["1"])
        XCTAssertNil(store.columnFocusedTab["c1"])
    }

    // MARK: - Column Helper Tests

    func testProjectColumns() {
        let store = makeStore()
        let cols = store.projectColumns(for: "1")
        XCTAssertEqual(cols.count, 2)
        XCTAssertEqual(cols[0].tabIds, ["t1"])
        XCTAssertEqual(cols[1].tabIds, ["t2"])
    }

    func testProjectColumnsEmpty() {
        let store = makeStore()
        let cols = store.projectColumns(for: "4")
        XCTAssertEqual(cols.count, 0)
    }

    func testColumnForTabId() {
        let store = makeStore()
        let col = store.columnFor(tabId: "t1")
        XCTAssertEqual(col?.id, "c1")
    }

    func testActiveColumn() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t2")
        XCTAssertEqual(store.activeColumn?.id, "c2")
    }

    func testOrderedTabs() {
        let store = makeStore()
        store.columns["1"] = [
            Column(id: "c1", tabIds: ["t1", "t2"]),
        ]
        let ordered = store.orderedTabs(for: "1")
        XCTAssertEqual(ordered.map(\.id), ["t1", "t2"])
    }

    func testOrderedTabsAcrossColumns() {
        let store = makeStore()
        let ordered = store.orderedTabs(for: "1")
        XCTAssertEqual(ordered.map(\.id), ["t1", "t2"])
    }

    // MARK: - Vertical Focus Tests

    func testFocusDown() {
        let store = makeStore()
        store.setActiveProject("1")
        store.columns["1"] = [Column(id: "c1", tabIds: ["t1", "t2"])]
        store.setActiveTab("t1")

        store.focusDown()

        XCTAssertEqual(store.activeTabId, "t2")
    }

    func testFocusDownNoOpAtBottom() {
        let store = makeStore()
        store.setActiveProject("1")
        store.columns["1"] = [Column(id: "c1", tabIds: ["t1", "t2"])]
        store.setActiveTab("t2")

        store.focusDown()

        XCTAssertEqual(store.activeTabId, "t2")
    }

    func testFocusUp() {
        let store = makeStore()
        store.setActiveProject("1")
        store.columns["1"] = [Column(id: "c1", tabIds: ["t1", "t2"])]
        store.setActiveTab("t2")

        store.focusUp()

        XCTAssertEqual(store.activeTabId, "t1")
    }

    func testFocusUpNoOpAtTop() {
        let store = makeStore()
        store.setActiveProject("1")
        store.columns["1"] = [Column(id: "c1", tabIds: ["t1", "t2"])]
        store.setActiveTab("t1")

        store.focusUp()

        XCTAssertEqual(store.activeTabId, "t1")
    }

    func testFocusLeftRestoresColumnMemory() {
        let store = makeStore()
        store.setActiveProject("1")
        store.columns["1"] = [
            Column(id: "c1", tabIds: ["t1"]),
            Column(id: "c2", tabIds: ["t2"]),
        ]
        store.sidebarVisible = false
        // Focus t2 in c2, then focus left to c1, then right back — should remember t2
        store.setActiveTab("t2")
        store.focusLeft()
        XCTAssertEqual(store.activeTabId, "t1")

        store.focusRight()
        XCTAssertEqual(store.activeTabId, "t2")
    }

    // MARK: - Column Move Tests

    func testMoveColumnRight() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t1")

        store.moveColumnRight()

        let cols = store.projectColumns(for: "1")
        XCTAssertEqual(cols[0].tabIds, ["t2"])
        XCTAssertEqual(cols[1].tabIds, ["t1"])
    }

    func testMoveColumnLeft() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t2")

        store.moveColumnLeft()

        let cols = store.projectColumns(for: "1")
        XCTAssertEqual(cols[0].tabIds, ["t2"])
        XCTAssertEqual(cols[1].tabIds, ["t1"])
    }

    func testMoveColumnRightNoOpAtEnd() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t2")

        store.moveColumnRight()

        let cols = store.projectColumns(for: "1")
        XCTAssertEqual(cols[0].tabIds, ["t1"])
        XCTAssertEqual(cols[1].tabIds, ["t2"])
    }

    // MARK: - Absorb & Expel Tests

    func testAbsorbFromLeft() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t2")

        store.absorbFromLeft()

        let cols = store.projectColumns(for: "1")
        XCTAssertEqual(cols.count, 1)
        XCTAssertEqual(cols[0].tabIds, ["t2", "t1"])
    }

    func testAbsorbFromRight() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t1")

        store.absorbFromRight()

        let cols = store.projectColumns(for: "1")
        XCTAssertEqual(cols.count, 1)
        XCTAssertEqual(cols[0].tabIds, ["t1", "t2"])
    }

    func testAbsorbFromLeftNoOpAtFirstColumn() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t1")

        store.absorbFromLeft()

        XCTAssertEqual(store.projectColumns(for: "1").count, 2)
    }

    func testExpelActiveTab() {
        let store = makeStore()
        store.setActiveProject("1")
        store.columns["1"] = [Column(id: "c1", tabIds: ["t1", "t2"])]
        store.setActiveTab("t1")

        store.expelActiveTab()

        let cols = store.projectColumns(for: "1")
        XCTAssertEqual(cols.count, 2)
        XCTAssertEqual(cols[0].tabIds, ["t2"])
        XCTAssertEqual(cols[1].tabIds, ["t1"])
        XCTAssertEqual(store.activeTabId, "t1")
    }

    func testExpelNoOpOnSingleTabColumn() {
        let store = makeStore()
        store.setActiveProject("1")
        store.setActiveTab("t1")

        store.expelActiveTab()

        XCTAssertEqual(store.projectColumns(for: "1").count, 2)
    }

    private func makeStore() -> AppStore {
        let store = AppStore()
        store.projects = [
            project(id: "1", name: "blink"),
            project(id: "2", name: "krux"),
            project(id: "3", name: "api-server"),
            project(id: "4", name: "dotfiles"),
        ]
        store.tabs = [
            AppTab(id: "t1", type: "shell", label: "Terminal 1", defaultLabel: "Terminal 1", projectId: "1"),
            AppTab(id: "t2", type: "shell", label: "Terminal 2", defaultLabel: "Terminal 2", projectId: "1"),
            AppTab(id: "t3", type: "shell", label: "Terminal 1", defaultLabel: "Terminal 1", projectId: "2"),
        ]
        store.columns = [
            "1": [
                Column(id: "c1", tabIds: ["t1"]),
                Column(id: "c2", tabIds: ["t2"]),
            ],
            "2": [
                Column(id: "c3", tabIds: ["t3"]),
            ],
        ]
        store.activeProjectId = nil
        store.activeTabId = nil
        store.lastSelectedProjectId = nil
        store.unreadTabs = []
        return store
    }

    private func project(id: String, name: String) -> Project {
        Project(
            id: id,
            name: name,
            path: "/tmp/\(name)",
            color: "#7aa2f7",
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }
}
