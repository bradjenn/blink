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
        "blink.profiles",
        "blink.workspaces",
        "blink.projects",
        "blink.lastSelectedWorkspaceId",
        "blink.lastSelectedProjectId",
        "blink.lastActiveTabs",
        "blink.workspaceViewportOffsets",
        "blink.columns",
        "blink.workspaceSetups",
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
        XCTAssertEqual(store.profiles.map(\.id), [Profile.personalId])
        XCTAssertEqual(store.workspaces.count, 1)
        XCTAssertEqual(store.workspaces.first?.id, Workspace.scratchSpaceId)
        XCTAssertEqual(store.workspaces.first?.profileId, Profile.personalId)
        XCTAssertNil(store.activeWorkspaceId)
        XCTAssertNil(store.activeTabId)
        XCTAssertTrue(store.sidebarVisible)
        XCTAssertEqual(store.expandedWorkspaceIds, [Workspace.scratchSpaceId])
    }

    func testLoadsLegacyProjectDefaultsIntoWorkspaceModel() throws {
        let legacyRoot = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: legacyRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: legacyRoot) }

        let legacyWorkspaceData = try JSONSerialization.data(
            withJSONObject: [
                [
                    "id": "legacy-1",
                    "name": "Legacy",
                    "path": legacyRoot.path,
                    "color": "#123456",
                    "createdAt": Date().timeIntervalSinceReferenceDate,
                ],
            ],
            options: [.sortedKeys]
        )
        defaults.set(legacyWorkspaceData, forKey: "blink.projects")
        defaults.set("legacy-1", forKey: "blink.lastSelectedProjectId")

        let legacySetupData = try JSONSerialization.data(
            withJSONObject: [
                "legacy-1": [
                    "projectId": "legacy-1",
                    "updatedAt": 0,
                    "columns": [
                        [
                            "id": "col-1",
                            "paneIds": ["pane-1"],
                        ],
                    ],
                    "panes": [
                        [
                            "id": "pane-1",
                            "kind": "shell",
                            "label": "Terminal 1",
                        ],
                    ],
                ],
            ],
            options: [.sortedKeys]
        )
        defaults.set(legacySetupData, forKey: "blink.projectSetups")

        let store = AppStore()

        XCTAssertTrue(store.workspaces.contains(where: { $0.id == "legacy-1" }))
        XCTAssertEqual(store.lastSelectedWorkspaceId, "legacy-1")
        XCTAssertEqual(store.workspaceSetups["legacy-1"]?.workspaceId, "legacy-1")
        XCTAssertEqual(store.workspaces.first(where: { $0.id == "legacy-1" })?.profileId, "legacy-1")
        XCTAssertTrue(store.profiles.contains(where: { $0.id == "legacy-1" }))
    }

    func testInitPrunesDeletedPersistedWorkspacesAndRelatedState() throws {
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let existingWorkspaceURL = tempRoot.appendingPathComponent("existing", isDirectory: true)
        let deletedWorkspaceURL = tempRoot.appendingPathComponent("deleted", isDirectory: true)
        try fileManager.createDirectory(at: existingWorkspaceURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let existingWorkspace = Workspace(
            id: "existing",
            name: "Existing",
            path: existingWorkspaceURL.path,
            color: "#123456",
            createdAt: .now
        )
        let deletedWorkspace = Workspace(
            id: "deleted",
            name: "Deleted",
            path: deletedWorkspaceURL.path,
            color: "#654321",
            createdAt: .now
        )

        defaults.set(
            try JSONEncoder().encode([existingWorkspace, deletedWorkspace]),
            forKey: "blink.workspaces"
        )
        defaults.set("deleted", forKey: "blink.lastSelectedWorkspaceId")
        defaults.set(["deleted": "tab-1"], forKey: "blink.lastActiveTabs")
        defaults.set(["deleted": 12.0], forKey: "blink.workspaceViewportOffsets")
        defaults.set(
            try JSONEncoder().encode([
                "deleted": [Column(id: "col-deleted", tabIds: ["tab-1"])],
            ]),
            forKey: "blink.columns"
        )
        defaults.set(
            try JSONEncoder().encode([
                "deleted": WorkspaceSetup(
                    workspaceId: "deleted",
                    updatedAt: .now,
                    columns: [WorkspaceSetupColumn(id: "col-deleted", paneIds: ["pane-1"])],
                    panes: [WorkspaceSetupPane(id: "pane-1", kind: .shell, label: "Terminal 1")]
                ),
            ]),
            forKey: "blink.workspaceSetups"
        )

        let store = AppStore()

        XCTAssertEqual(store.workspaces.map(\.id), [Workspace.scratchSpaceId, "existing"])
        XCTAssertNil(store.lastSelectedWorkspaceId)
        XCTAssertNil(store.workspaceSetups["deleted"])
        XCTAssertNil(store.columns["deleted"])

        let persistedWorkspaces = try XCTUnwrap(defaults.data(forKey: "blink.workspaces"))
        let decodedWorkspaces = try JSONDecoder().decode([Workspace].self, from: persistedWorkspaces)
        XCTAssertEqual(decodedWorkspaces.map(\.id), ["existing"])

        let persistedSetups = try XCTUnwrap(defaults.data(forKey: "blink.workspaceSetups"))
        let decodedSetups = try JSONDecoder().decode([String: WorkspaceSetup].self, from: persistedSetups)
        XCTAssertTrue(decodedSetups.isEmpty)
    }

    func testOpenScratchSpaceCreatesBuiltInWorkspace() {
        let store = AppStore()

        store.openScratchSpace()

        XCTAssertEqual(store.activeWorkspaceId, Workspace.scratchSpaceId)
        XCTAssertEqual(store.workspaces.first?.id, Workspace.scratchSpaceId)
        XCTAssertEqual(store.workspaces.first?.profileId, Profile.personalId)
        XCTAssertTrue(store.workspaceTabs(for: Workspace.scratchSpaceId).isEmpty)
    }

    func testSetWorkspaceProfileUpdatesWorkspace() {
        let store = makeStore()
        let profile = try! XCTUnwrap(store.addProfile(name: "Client A"))

        let didUpdate = store.setWorkspaceProfile("1", profileId: profile.id)

        XCTAssertTrue(didUpdate)
        XCTAssertEqual(store.workspaces.first(where: { $0.id == "1" })?.profileId, profile.id)
    }

    func testRemoveProfileReassignsWorkspacesToDefaultProfile() {
        let store = makeStore()
        let profile = try! XCTUnwrap(store.addProfile(name: "Client A"))
        _ = store.setWorkspaceProfile("1", profileId: profile.id)

        let didRemove = store.removeProfile(profile.id)

        XCTAssertTrue(didRemove)
        XCTAssertEqual(store.workspaces.first(where: { $0.id == "1" })?.profileId, Profile.personalId)
        XCTAssertFalse(store.profiles.contains(where: { $0.id == profile.id }))
    }

    func testSidebarProfileSectionsGroupWorkspacesByProfileOrder() {
        let store = makeStore()
        let clientA = try! XCTUnwrap(store.addProfile(name: "Client A"))
        let clientB = try! XCTUnwrap(store.addProfile(name: "Client B"))

        _ = store.setWorkspaceProfile("4", profileId: clientA.id)
        _ = store.setWorkspaceProfile("2", profileId: clientB.id)

        XCTAssertEqual(
            store.sidebarProfileSections.map(\.profile.id),
            [Profile.personalId, clientA.id, clientB.id]
        )
        XCTAssertEqual(
            store.sidebarProfileSections.map { $0.workspaces.map(\.id) },
            [["1", "3"], ["4"], ["2"]]
        )
        XCTAssertEqual(store.sidebarOrderedWorkspaces.map(\.id), ["1", "3", "4", "2"])
    }

    func testPresentWorkspaceOnboardingDismissesOtherPickers() {
        let store = AppStore()
        store.showWorkspaceSwitcher = true
        store.showThemePicker = true
        store.showAISessionPicker = true
        store.showCommandPalette = true
        store.workspacePrompt = WorkspacePromptState(
            workspaceId: Workspace.scratchSpaceId,
            kind: .rename,
            initialValue: "Scratch Space"
        )

        store.presentWorkspaceOnboarding()

        XCTAssertTrue(store.showWorkspaceOnboarding)
        XCTAssertFalse(store.showWorkspaceSwitcher)
        XCTAssertFalse(store.showThemePicker)
        XCTAssertFalse(store.showAISessionPicker)
        XCTAssertFalse(store.showCommandPalette)
        XCTAssertNil(store.workspacePrompt)
    }

    func testCompleteWorkspaceOnboardingImportsExistingFolderAndSeedsAISession() throws {
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceURL = tempRoot.appendingPathComponent("blink", isDirectory: true)
        try fileManager.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let store = AppStore()

        let workspace = try store.completeWorkspaceOnboarding(
            mode: .existingFolder,
            name: "Blink Workspace",
            existingFolderPath: workspaceURL.path,
            parentFolderPath: "",
            newFolderName: "",
            profileId: Profile.personalId,
            starter: .aiSession,
            aiProvider: .opencode,
            browserURL: ""
        )

        XCTAssertEqual(workspace.name, "Blink Workspace")
        XCTAssertEqual(workspace.path, workspaceURL.path)
        XCTAssertEqual(store.activeWorkspaceId, workspace.id)
        XCTAssertEqual(store.workspaceSetups[workspace.id]?.panes.first?.kind, .command)
        XCTAssertEqual(store.workspaceSetups[workspace.id]?.panes.first?.command, "opencode")
        XCTAssertEqual(store.tabsById[store.activeTabId ?? ""]?.label, "OpenCode")
    }

    func testCompleteWorkspaceOnboardingCreatesFolderAndSeedsBrowserPane() throws {
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let store = AppStore()
        let profile = try XCTUnwrap(store.addProfile(name: "Client A"))

        let workspace = try store.completeWorkspaceOnboarding(
            mode: .createFolder,
            name: "",
            existingFolderPath: "",
            parentFolderPath: tempRoot.path,
            newFolderName: "client",
            profileId: profile.id,
            starter: .browser,
            aiProvider: .claude,
            browserURL: "example.com"
        )

        let createdWorkspaceURL = tempRoot.appendingPathComponent("client", isDirectory: true)
        var isDirectory: ObjCBool = false

        XCTAssertTrue(fileManager.fileExists(atPath: createdWorkspaceURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertEqual(workspace.name, "client")
        XCTAssertEqual(workspace.path, createdWorkspaceURL.path)
        XCTAssertEqual(workspace.profileId, profile.id)
        XCTAssertEqual(store.workspaceSetups[workspace.id]?.panes.first?.kind, .browser)
        XCTAssertEqual(
            store.workspaceSetups[workspace.id]?.panes.first?.browserState?.selectedTab?.state.urlString,
            "https://example.com"
        )
    }

    func testCompleteWorkspaceOnboardingReusesExistingWorkspaceForDuplicatePath() throws {
        let store = makeStore()
        let existingWorkspace = try XCTUnwrap(store.workspaces.first(where: { $0.id == "1" }))
        let existingSetup = store.workspaceSetups["1"]

        let workspace = try store.completeWorkspaceOnboarding(
            mode: .existingFolder,
            name: "Renamed",
            existingFolderPath: existingWorkspace.path,
            parentFolderPath: "",
            newFolderName: "",
            profileId: Profile.personalId,
            starter: .browser,
            aiProvider: .claude,
            browserURL: "https://example.com"
        )

        XCTAssertEqual(workspace.id, "1")
        XCTAssertEqual(store.workspaces.count, 4)
        XCTAssertEqual(store.workspaceSetups["1"], existingSetup)
        XCTAssertEqual(store.activeWorkspaceId, "1")
    }

    func testCompleteWorkspaceOnboardingRejectsInvalidFolderName() throws {
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let store = AppStore()

        XCTAssertThrowsError(
            try store.completeWorkspaceOnboarding(
                mode: .createFolder,
                name: "",
                existingFolderPath: "",
                parentFolderPath: tempRoot.path,
                newFolderName: "../client",
                profileId: Profile.personalId,
                starter: .terminal,
                aiProvider: .claude,
                browserURL: ""
            )
        ) { error in
            XCTAssertEqual(error as? WorkspaceCreationError, .invalidFolderName)
        }
    }

    func testOpenClaudeSessionUsesScratchSpaceWhenNoWorkspaceIsActive() {
        let store = AppStore()

        let tab = store.openClaudeSession()

        XCTAssertEqual(store.activeWorkspaceId, Workspace.scratchSpaceId)
        XCTAssertEqual(tab?.workspaceId, Workspace.scratchSpaceId)
        XCTAssertEqual(tab?.command, "claude --dangerously-skip-permissions")
    }

    func testOpenCodexSessionUsesActiveWorkspace() {
        let store = makeStore()
        store.setActiveWorkspace("1")

        let tab = store.openCodexSession()

        XCTAssertEqual(tab?.workspaceId, "1")
        XCTAssertEqual(tab?.command, "codex --dangerously-bypass-approvals-and-sandbox")
    }

    func testOpenClaudeSessionCreatesNewManagedTabEachTime() {
        let store = makeStore()
        store.setActiveWorkspace("1")

        let first = store.openClaudeSession()
        let second = store.openClaudeSession()

        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertNotEqual(first?.id, second?.id)
        XCTAssertEqual(store.workspaceTabs(for: "1").filter { $0.command == "claude --dangerously-skip-permissions" }.count, 2)
    }

    func testOpenOpenCodeSessionUsesActiveWorkspace() {
        let store = makeStore()
        store.setActiveWorkspace("1")

        let tab = store.openOpenCodeSession()

        XCTAssertEqual(tab?.workspaceId, "1")
        XCTAssertEqual(tab?.command, "opencode")
        XCTAssertEqual(store.shellDetectedAIPaneKinds[tab?.id ?? ""], .opencode)
    }

    func testTerminalLaunchCommandWrapsOpenCodeWithBlinkScopedThemeConfig() throws {
        let store = makeStore()
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceConfigHomeURL = rootURL.appendingPathComponent("source-config", isDirectory: true)
        let scopedConfigHomeURL = rootURL.appendingPathComponent("blink-config", isDirectory: true)
        let sourceOpenCodeDirectory = sourceConfigHomeURL.appendingPathComponent("opencode", isDirectory: true)

        defer { try? fileManager.removeItem(at: rootURL) }

        try fileManager.createDirectory(at: sourceOpenCodeDirectory, withIntermediateDirectories: true)
        let sourceTUIURL = sourceOpenCodeDirectory.appendingPathComponent("tui.json")
        let sourceTUIData = try JSONSerialization.data(
            withJSONObject: [
                "$schema": "https://opencode.ai/tui.json",
                "keybinds": ["leader": "ctrl+x"],
                "theme": "ghosty-transparent",
            ],
            options: [.prettyPrinted, .sortedKeys]
        )
        try sourceTUIData.write(to: sourceTUIURL)
        let sourcePackageURL = sourceOpenCodeDirectory.appendingPathComponent("package.json")
        try "{}".write(to: sourcePackageURL, atomically: true, encoding: .utf8)

        store.openCodeSourceConfigHomeOverride = sourceConfigHomeURL
        store.openCodeConfigHomeOverride = scopedConfigHomeURL

        let tab = AppTab(
            id: "opencode-tab",
            type: "shell",
            label: "OpenCode",
            defaultLabel: "OpenCode",
            workspaceId: "1",
            command: "opencode"
        )
        let command = store.terminalLaunchCommand(for: tab, workspace: workspace(id: "1", name: "blink"))

        XCTAssertEqual(command, "env XDG_CONFIG_HOME='\(scopedConfigHomeURL.path)' opencode")

        let scopedOpenCodeDirectory = scopedConfigHomeURL.appendingPathComponent("opencode", isDirectory: true)
        let scopedTUIData = try Data(contentsOf: scopedOpenCodeDirectory.appendingPathComponent("tui.json"))
        let scopedTUI = try XCTUnwrap(
            JSONSerialization.jsonObject(with: scopedTUIData) as? [String: Any]
        )
        XCTAssertEqual(scopedTUI["theme"] as? String, "blink-current")
        XCTAssertEqual(
            (scopedTUI["keybinds"] as? [String: String])?["leader"],
            "ctrl+x"
        )
        XCTAssertTrue(
            fileManager.fileExists(
                atPath: scopedOpenCodeDirectory
                    .appendingPathComponent("themes/blink-current.json")
                    .path
            )
        )
        XCTAssertNoThrow(
            try fileManager.destinationOfSymbolicLink(
                atPath: scopedOpenCodeDirectory.appendingPathComponent("package.json").path
            )
        )
    }

    func testRemoveWorkspaceDoesNotRemoveScratchSpace() {
        let store = AppStore()

        store.removeWorkspace(Workspace.scratchSpaceId)

        XCTAssertTrue(store.workspaces.contains(where: { $0.id == Workspace.scratchSpaceId }))
    }

    func testRenameWorkspaceUpdatesName() {
        let store = makeStore()

        store.renameWorkspace("1", to: "client")

        XCTAssertEqual(store.workspaces.first(where: { $0.id == "1" })?.name, "client")
    }

    func testPromptRenameWorkspaceUsesBrandedPromptState() {
        let store = makeStore()

        store.promptRenameWorkspace("1")

        XCTAssertEqual(store.workspacePrompt?.workspaceId, "1")
        XCTAssertEqual(store.workspacePrompt?.kind, .rename)
        XCTAssertEqual(store.workspacePrompt?.initialValue, "blink")
    }

    func testRelinkWorkspaceUpdatesPath() throws {
        let store = makeStore()
        let relinkedURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: relinkedURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: relinkedURL) }

        store.relinkWorkspace("1", toPath: relinkedURL.path)

        XCTAssertEqual(store.workspaces.first(where: { $0.id == "1" })?.path, relinkedURL.path)
        XCTAssertFalse(store.isWorkspacePathMissing("1"))
    }

    func testPromptRelinkWorkspaceUsesBrandedPromptState() {
        let store = makeStore()

        store.promptRelinkWorkspace("1")

        XCTAssertEqual(store.workspacePrompt?.workspaceId, "1")
        XCTAssertEqual(store.workspacePrompt?.kind, .relink)
        XCTAssertEqual(
            store.workspacePrompt?.initialValue,
            store.workspaces.first(where: { $0.id == "1" })?.path
        )
    }

    func testSetActiveWorkspaceActivatesFirstTab() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        XCTAssertEqual(store.activeWorkspaceId, "1")
        XCTAssertEqual(store.activeTabId, "t1")
    }

    func testSetActiveWorkspaceNoTabs() {
        let store = makeStore()
        store.setActiveWorkspace("4")
        XCTAssertEqual(store.activeWorkspaceId, "4")
        XCTAssertNil(store.activeTabId)
    }

    func testOpenWorkspaceSessionWithoutRestoreLeavesWorkspaceEmptyWhenWorkspaceHasSavedBrowserSetup() {
        let store = makeStore()
        store.workspaceSetups["4"] = WorkspaceSetup(
            workspaceId: "4",
            updatedAt: .now,
            columns: [
                WorkspaceSetupColumn(id: "col-0", paneIds: ["pane-browser"])
            ],
            panes: [
                WorkspaceSetupPane(
                    id: "pane-browser",
                    kind: .browser,
                    label: "Browser 1",
                    role: nil,
                    command: nil,
                    workingDirectory: nil,
                    browserState: BrowserPaneState.singleTab(urlString: "https://example.com")
                )
            ]
        )

        store.openWorkspaceSession("4", restoringSavedSetup: false)

        XCTAssertEqual(store.activeWorkspaceId, "4")
        XCTAssertNil(store.activeTabId)
        XCTAssertTrue(store.workspaceTabs(for: "4").isEmpty)
    }

    func testClearActiveWorkspace() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        store.setActiveWorkspace(nil)
        XCTAssertNil(store.activeWorkspaceId)
        XCTAssertNil(store.activeTabId)
    }

    func testWorkspaceTabs() {
        let store = makeStore()
        let tabs = store.workspaceTabs(for: "1")
        XCTAssertEqual(tabs.count, 2)
        XCTAssertEqual(tabs[0].label, "Terminal 1")
    }

    func testRemoveWorkspace() {
        let store = makeStore()
        store.removeWorkspace("1")
        XCTAssertEqual(store.workspaces.count, 3)
        XCTAssertFalse(store.workspaces.contains(where: { $0.id == "1" }))
    }

    func testRemoveActiveWorkspaceClearsSelection() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        store.removeWorkspace("1")
        XCTAssertNil(store.activeWorkspaceId)
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
        store.setActiveWorkspace("1")
        store.setActiveTab("t2")
        XCTAssertEqual(store.activeTabId, "t2")
    }

    func testSetActiveTabSwitchesActiveWorkspaceWhenNeeded() {
        let store = makeStore()
        store.setActiveWorkspace("1")

        store.setActiveTab("t3")

        XCTAssertEqual(store.activeWorkspaceId, "2")
        XCTAssertEqual(store.activeTabId, "t3")
    }

    func testActiveColumnFallsBackWhenActiveTabIsNoLongerInColumns() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        store.activeTabId = "missing-tab"

        XCTAssertEqual(store.activeColumn?.id, "c1")
    }

    func testSelectNextTabWrapsWithinWorkspace() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        store.setActiveTab("t2")

        store.selectNextTab()

        XCTAssertEqual(store.activeTabId, "t1")
    }

    func testSelectPreviousTabWrapsWithinWorkspace() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        store.setActiveTab("t1")

        store.selectPreviousTab()

        XCTAssertEqual(store.activeTabId, "t2")
    }

    func testCloseTab() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        store.setActiveTab("t1")
        store.closeTab("t1")
        XCTAssertEqual(store.activeTabId, "t2")
        XCTAssertEqual(store.tabs.count, 2)
    }

    func testManagedCommandTabStartsRunning() {
        let store = makeStore()

        store.openOrFocusCommandTab(workspaceId: "1", command: "npm run dev", label: "Dev Server")

        let commandTabs = store.workspaceTabs(for: "1").filter { $0.command == "npm run dev" }
        XCTAssertEqual(commandTabs.count, 1)
        XCTAssertEqual(store.managedCommandStatus(for: commandTabs[0].id), .running)
    }

    func testManagedCommandExitStopsTabInsteadOfClosingIt() {
        let store = makeStore()
        store.openOrFocusCommandTab(workspaceId: "1", command: "npm run dev", label: "Dev Server")
        let tabId = try! XCTUnwrap(store.workspaceTabs(for: "1").first(where: { $0.command == "npm run dev" })?.id)

        let handled = store.handleProcessExit(for: tabId)

        XCTAssertTrue(handled)
        XCTAssertNotNil(store.tabsById[tabId])
        XCTAssertEqual(store.managedCommandStatus(for: tabId), .stopped)
    }

    func testOpenOrFocusCommandTabRestartsStoppedPaneWithoutDuplicatingIt() {
        let store = makeStore()
        store.openOrFocusCommandTab(workspaceId: "1", command: "npm run dev", label: "Dev Server")
        let tabId = try! XCTUnwrap(store.workspaceTabs(for: "1").first(where: { $0.command == "npm run dev" })?.id)
        _ = store.handleProcessExit(for: tabId)

        store.openOrFocusCommandTab(workspaceId: "1", command: "npm run dev", label: "Dev Server")

        let commandTabs = store.workspaceTabs(for: "1").filter { $0.command == "npm run dev" }
        XCTAssertEqual(commandTabs.count, 1)
        XCTAssertEqual(commandTabs[0].id, tabId)
        XCTAssertEqual(store.managedCommandStatus(for: tabId), .running)
    }

    func testHideTitleBarPersists() {
        XCTAssertFalse(AppStore().hideTitleBar)

        let store = AppStore()
        store.hideTitleBar = true

        XCTAssertTrue(AppStore().hideTitleBar)
    }

    func testLastActiveTabPersistsPerWorkspace() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        store.setActiveTab("t2")

        let reloaded = AppStore()
        reloaded.workspaces = store.workspaces
        reloaded.tabs = store.tabs

        reloaded.setActiveWorkspace("1")

        XCTAssertEqual(reloaded.activeTabId, "t2")
    }

    func testWorkspaceViewportOffsetPersists() {
        let store = makeStore()
        store.setWorkspaceViewportOffset(184, for: "1")

        XCTAssertEqual(AppStore().workspaceViewportOffset(for: "1"), 184, accuracy: 0.001)
    }

    func testWorkspaceSessionAutosavesCurrentLayout() {
        let store = makeStore()
        let setup = store.workspaceSetup(for: "1")

        XCTAssertNotNil(setup)
        XCTAssertEqual(setup?.columns.count, 2)
        XCTAssertEqual(setup?.panes.count, 2)
        XCTAssertEqual(setup?.panes.map(\.label), ["Terminal 1", "Terminal 2"])
    }

    func testRestoreWorkspaceSetupRebuildsTabsAndColumns() {
        let store = makeStore()
        XCTAssertNotNil(store.workspaceSetup(for: "1"))

        store.tabs.removeAll { $0.workspaceId == "1" }
        store.columns["1"] = []
        store.activeWorkspaceId = "1"
        store.activeTabId = nil

        store.restoreWorkspaceSetup(for: "1")

        XCTAssertEqual(store.workspaceTabs(for: "1").count, 2)
        XCTAssertEqual(store.workspaceColumns(for: "1").count, 2)
        XCTAssertNotNil(store.activeTabId)
    }

    func testOpenWorkspaceSessionRestoresAutosavedSessionWhenNoLiveTabs() {
        let store = makeStore()
        XCTAssertNotNil(store.workspaceSetup(for: "1"))

        store.tabs.removeAll { $0.workspaceId == "1" }
        store.columns["1"] = []

        store.openWorkspaceSession("1")

        XCTAssertEqual(store.workspaceTabs(for: "1").count, 2)
        XCTAssertEqual(store.workspaceColumns(for: "1").count, 2)
    }

    func testOpenWorkspaceSessionWithoutSavedSetupLeavesWorkspaceEmpty() {
        let store = makeStore()

        store.openWorkspaceSession("4")

        XCTAssertEqual(store.activeWorkspaceId, "4")
        XCTAssertNil(store.activeTabId)
        XCTAssertTrue(store.workspaceTabs(for: "4").isEmpty)
        XCTAssertTrue(store.workspaceColumns(for: "4").isEmpty)
    }

    func testOpenWorkspaceSessionDoesNotRestoreWhenWorkspacePathIsMissing() throws {
        let store = makeStore()
        let missingPath = try XCTUnwrap(store.workspaces.first(where: { $0.id == "1" })?.path)
        try fileManager.removeItem(atPath: missingPath)

        store.tabs.removeAll { $0.workspaceId == "1" }
        store.columns["1"] = []

        store.openWorkspaceSession("1")

        XCTAssertEqual(store.activeWorkspaceId, "1")
        XCTAssertNil(store.activeTabId)
        XCTAssertTrue(store.workspaceTabs(for: "1").isEmpty)
        XCTAssertTrue(store.workspaceColumns(for: "1").isEmpty)
        XCTAssertTrue(store.isWorkspacePathMissing("1"))
    }

    func testResumeLastWorkspaceSessionRestoresBrowserOnlyWorkspace() {
        let store = makeStore()
        store.tabs.removeAll { $0.workspaceId == "1" }
        store.columns["1"] = []
        store.lastSelectedWorkspaceId = "1"
        store.workspaceSetups["1"] = WorkspaceSetup(
            workspaceId: "1",
            updatedAt: .now,
            columns: [
                WorkspaceSetupColumn(id: "col-0", paneIds: ["pane-browser"])
            ],
            panes: [
                WorkspaceSetupPane(
                    id: "pane-browser",
                    kind: .browser,
                    label: "daily.dev",
                    role: nil,
                    command: nil,
                    workingDirectory: nil,
                    browserState: BrowserPaneState.singleTab(urlString: "https://app.daily.dev/")
                )
            ]
        )

        store.resumeLastWorkspaceSession()
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))

        XCTAssertEqual(store.activeWorkspaceId, "1")
        XCTAssertEqual(store.workspaceTabs(for: "1").count, 1)
        XCTAssertEqual(store.workspaceTabs(for: "1").first?.kind, .browser)
        XCTAssertEqual(
            store.workspaceTabs(for: "1").first?.browserState?.selectedTab?.state.urlString,
            "https://app.daily.dev/"
        )
        XCTAssertFalse(store.sidebarFocused)
        XCTAssertFalse(store.workspaceLandingFocused)
    }

    func testEmptyRuntimeDoesNotEraseAutosavedWorkspaceSession() {
        let store = makeStore()
        let savedSetup = try! XCTUnwrap(store.workspaceSetup(for: "1"))

        store.tabs.removeAll { $0.workspaceId == "1" }
        store.columns["1"] = []

        XCTAssertEqual(store.workspaceSetup(for: "1"), savedSetup)
    }

    func testFocusLeftFromFirstColumnGoesToSidebar() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        store.setActiveTab("t1")
        store.sidebarVisible = true
        store.sidebarFocused = false

        store.focusLeft()

        XCTAssertTrue(store.sidebarFocused)
    }

    func testFocusLeftFromFirstColumnNoOpWhenSidebarClosed() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        store.setActiveTab("t1")
        store.sidebarVisible = false

        store.focusLeft()

        XCTAssertEqual(store.activeTabId, "t1")
        XCTAssertFalse(store.sidebarFocused)
    }

    func testFocusRightFromSidebarGoesToTerminal() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        store.setActiveTab("t1")
        store.sidebarFocused = true

        store.focusRight()

        XCTAssertFalse(store.sidebarFocused)
        XCTAssertEqual(store.activeTabId, "t1")
    }

    func testFocusRightFromSidebarFocusesWorkspaceLandingWhenWorkspaceHasNoPanes() {
        let store = makeStore()
        store.setActiveWorkspace("4")
        store.sidebarFocused = true

        store.focusRight()

        XCTAssertFalse(store.sidebarFocused)
        XCTAssertTrue(store.workspaceLandingFocused)
        XCTAssertNil(store.activeTabId)
    }

    func testFocusRightFromSidebarRecoversMissingActiveTabUsingSelectablePane() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        store.activeTabId = nil
        store.sidebarFocused = true

        store.focusRight()

        XCTAssertFalse(store.sidebarFocused)
        XCTAssertEqual(store.activeTabId, "t1")
    }

    func testFocusLeftFromWorkspaceLandingReturnsToSidebar() {
        let store = makeStore()
        store.setActiveWorkspace("4")
        store.workspaceLandingFocused = true
        store.sidebarVisible = true

        store.focusLeft()

        XCTAssertTrue(store.sidebarFocused)
        XCTAssertFalse(store.workspaceLandingFocused)
    }

    func testFocusRightNoOpAtLastColumn() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        store.setActiveTab("t2")

        store.focusRight()

        XCTAssertEqual(store.activeTabId, "t2")
    }

    func testFocusLeftBetweenColumns() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        store.setActiveTab("t2")
        store.sidebarVisible = false

        store.focusLeft()

        XCTAssertEqual(store.activeTabId, "t1")
    }

    func testFocusRightBetweenColumns() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        store.setActiveTab("t1")

        store.focusRight()

        XCTAssertEqual(store.activeTabId, "t2")
    }

    // MARK: - Overview Tests

    func testToggleOverviewEntersAndExits() {
        let store = makeStore()
        store.setActiveWorkspace("1")
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
        store.setActiveWorkspace("1")
        store.setActiveTab("t2")

        store.toggleOverview()

        XCTAssertEqual(store.overviewHighlightedColumnId, "c2")
    }

    func testOverviewHighlightLeftRight() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        store.setActiveTab("t1")
        store.toggleOverview()

        store.overviewHighlightRight()
        XCTAssertEqual(store.overviewHighlightedColumnId, "c2")

        store.overviewHighlightLeft()
        XCTAssertEqual(store.overviewHighlightedColumnId, "c1")
    }

    func testOverviewHighlightStopsAtEdges() {
        let store = makeStore()
        store.setActiveWorkspace("1")
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
        store.setActiveWorkspace("1")
        store.setActiveTab("t1")
        store.toggleOverview()

        store.exitOverview(selecting: "c2")

        XCTAssertFalse(store.isOverviewMode)
        XCTAssertNil(store.overviewHighlightedColumnId)
        XCTAssertEqual(store.activeTabId, "t2")
    }

    func testExitOverviewCancelKeepsOriginal() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        store.setActiveTab("t1")
        store.toggleOverview()

        store.overviewHighlightRight()
        store.exitOverview(selecting: nil)

        XCTAssertFalse(store.isOverviewMode)
        XCTAssertEqual(store.activeTabId, "t1")
    }

    func testOverviewNoOpWithNoTabs() {
        let store = makeStore()
        store.setActiveWorkspace("4")

        store.toggleOverview()

        XCTAssertFalse(store.isOverviewMode)
        XCTAssertNil(store.overviewHighlightedColumnId)
    }

    // MARK: - Column Migration Tests

    func testOpenTabCreatesColumn() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        let tab = store.openTab(workspaceId: "1")
        let cols = store.workspaceColumns(for: "1")
        XCTAssertEqual(cols.count, 3) // 2 existing + 1 new
        XCTAssertEqual(cols.last?.tabIds, [tab.id])
    }

    func testNewShellTabsGetStableWorkspacePaneIds() {
        let store = makeStore()
        store.setActiveWorkspace("1")

        let tab = store.openTab(workspaceId: "1")
        let paneId = try! XCTUnwrap(tab.workspaceSetupPaneId)
        let setup = try! XCTUnwrap(store.workspaceSetup(for: "1"))

        XCTAssertTrue(setup.panes.contains(where: { $0.id == paneId }))
    }

    func testPlainShellTabsLaunchThroughTmuxWhenPaneIdExists() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        let tab = store.openTab(workspaceId: "1")
        let workspace = try! XCTUnwrap(store.workspaces.first(where: { $0.id == "1" }))

        let command = store.terminalLaunchCommand(for: tab, workspace: workspace)

        XCTAssertNotNil(command)
        XCTAssertTrue(command?.contains("tmux -L") == true)
        XCTAssertTrue(command?.contains("attach-session") == true)
        XCTAssertTrue(command?.contains("new-session -d -t") == true)
        XCTAssertTrue(command?.contains("env -u TMUX tmux") == true)
        XCTAssertFalse(command?.contains("exec TMUX=") == true)
    }

    func testCloseTmuxBackedShellTabCleansUpClientSessionAndWindow() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        let tab = store.openTab(workspaceId: "1")
        let paneId = try! XCTUnwrap(tab.workspaceSetupPaneId)
        var commands: [String] = []
        store.detachedShellCommandHandler = { commands.append($0) }

        store.closeTab(tab.id)

        let command = try! XCTUnwrap(commands.first)
        XCTAssertTrue(command.contains("kill-session -t 'blink-1-\(paneId)'"))
        XCTAssertTrue(command.contains("kill-window -t 'blink-1:pane-\(paneId)'"))
    }

    func testRemoveWorkspaceCleansUpBaseTmuxSessionAndClientSessions() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        let first = store.openTab(workspaceId: "1")
        let second = store.openTab(workspaceId: "1")
        let firstPaneId = try! XCTUnwrap(first.workspaceSetupPaneId)
        let secondPaneId = try! XCTUnwrap(second.workspaceSetupPaneId)
        var commands: [String] = []
        store.detachedShellCommandHandler = { commands.append($0) }

        store.removeWorkspace("1")

        let command = try! XCTUnwrap(commands.first)
        XCTAssertTrue(command.contains("kill-session -t 'blink-1-\(firstPaneId)'"))
        XCTAssertTrue(command.contains("kill-session -t 'blink-1-\(secondPaneId)'"))
        XCTAssertTrue(command.contains("kill-session -t 'blink-1'"))
    }

    func testOpenFileInEditorTargetsExistingTmuxNeovimTab() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        let editorTab = store.openTab(workspaceId: "1")
        let paneId = try! XCTUnwrap(editorTab.workspaceSetupPaneId)
        store.handleTerminalTitleUpdate("nvim", for: editorTab.id)
        var commands: [String] = []
        store.detachedShellCommandHandler = { commands.append($0) }

        store.openFileInEditor(workspaceId: "1", path: "/tmp/blink/Blink/Chat/WorkspaceChatView.swift", line: 42)

        let command = try! XCTUnwrap(commands.first)
        XCTAssertEqual(store.activeTabId, editorTab.id)
        XCTAssertTrue(command.contains("send-keys"))
        XCTAssertTrue(command.contains("blink-1:pane-\(paneId)"))
        XCTAssertTrue(command.contains("/tmp/blink/Blink/Chat/WorkspaceChatView.swift"))
        XCTAssertTrue(command.contains("call cursor(42, 1)"))
        XCTAssertTrue(command.contains("tab drop"))
        XCTAssertEqual(store.workspaceTabs(for: "1").count, 3)
    }

    func testClaudeTitleMarksTabRunningWithoutHooks() {
        let store = makeStore()
        store.setActiveWorkspace("1")

        store.handleTerminalTitleUpdate("claude", for: "t2")

        XCTAssertEqual(store.claudeActivity(for: "t2")?.kind, .running)
        XCTAssertEqual(store.tabsById["t2"]?.label, "Claude Code")
    }

    func testShellPromptClearsClaudeRunningFallbackAndMarksUnread() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        store.handleTerminalTitleUpdate("claude", for: "t2")
        store.clearUnread("t2")

        store.handleTerminalTitleUpdate("~/Code/blink", for: "t2")

        XCTAssertNil(store.claudeActivity(for: "t2"))
        XCTAssertEqual(store.tabsById["t2"]?.label, store.tabsById["t2"]?.defaultLabel)
        XCTAssertTrue(store.unreadTabs.contains("t2"))
    }

    func testClaudeLaunchArmsPromptTitleCapture() {
        let store = makeStore()
        store.setActiveWorkspace("1")

        store.handleTerminalLineSubmission("claude --resume", for: "t2")

        XCTAssertEqual(store.tabsById["t2"]?.label, "Claude Code")
        XCTAssertEqual(store.claudeActivity(for: "t2")?.kind, .running)
    }

    func testClaudePromptTitleUsesFirstPromptText() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        store.handleTerminalLineSubmission("claude", for: "t2")

        store.handleTerminalLineSubmission("Add Gemini CLI to Blink", for: "t2")

        XCTAssertEqual(store.tabsById["t2"]?.label, "Add Gemini CLI to Blink")
    }

    func testManagedClaudePromptTitleUsesFirstPromptText() {
        let store = makeStore()
        store.setActiveWorkspace("1")

        let tab = store.openOrFocusCommandTab(
            workspaceId: "1",
            command: "claude --dangerously-skip-permissions",
            label: "Claude Code"
        )

        store.handleTerminalLineSubmission("Add Gemini CLI to Blink", for: tab.id)

        XCTAssertEqual(store.tabsById[tab.id]?.label, "Add Gemini CLI to Blink")
        XCTAssertEqual(store.claudeActivity(for: tab.id)?.kind, .running)
    }

    func testClaudeForegroundTitleDoesNotOverwritePromptTitle() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        store.handleTerminalLineSubmission("claude", for: "t2")
        store.handleTerminalLineSubmission("Add Gemini CLI to Blink", for: "t2")

        store.handleTerminalTitleUpdate("claude", for: "t2")

        XCTAssertEqual(store.tabsById["t2"]?.label, "Add Gemini CLI to Blink")
    }

    func testClaudeIdleDoesNotClearCustomPromptTitle() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        store.handleTerminalLineSubmission("claude", for: "t2")
        store.handleTerminalLineSubmission("Add Gemini CLI to Blink", for: "t2")

        store.handleClaudeHookEventForTesting(
            event: "idle",
            workspaceId: "1",
            tabId: "t2",
            rawInput: ""
        )

        XCTAssertEqual(store.tabsById["t2"]?.label, "Add Gemini CLI to Blink")
        XCTAssertEqual(store.claudeActivity(for: "t2")?.kind, .completed)
    }

    func testClaudeSessionEndDoesNotClearCustomPromptTitle() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        store.handleTerminalLineSubmission("claude", for: "t2")
        store.handleTerminalLineSubmission("Add Gemini CLI to Blink", for: "t2")

        store.handleClaudeHookEventForTesting(
            event: "session-end",
            workspaceId: "1",
            tabId: "t2",
            rawInput: ""
        )

        XCTAssertEqual(store.tabsById["t2"]?.label, "Add Gemini CLI to Blink")
        XCTAssertEqual(store.claudeActivity(for: "t2")?.kind, .completed)
    }

    func testCodexLaunchTracksProviderKind() {
        let store = makeStore()
        store.setActiveWorkspace("1")

        store.handleTerminalLineSubmission("codex", for: "t2")

        XCTAssertEqual(store.shellDetectedAIPaneKinds["t2"], .codex)
        XCTAssertEqual(store.tabsById["t2"]?.label, "Codex")
    }

    func testShellPromptDoesNotClearPendingCodexLaunch() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        store.handleTerminalLineSubmission("codex", for: "t2")

        store.handleTerminalTitleUpdate("~/Code/blink", for: "t2")
        store.handleTerminalLineSubmission("Plan Blink release notes", for: "t2")

        XCTAssertEqual(store.shellDetectedAIPaneKinds["t2"], .codex)
        XCTAssertEqual(store.tabsById["t2"]?.label, "Plan Blink release notes")
    }

    func testManagedCodexPromptTitleUsesFirstPromptText() {
        let store = makeStore()
        store.setActiveWorkspace("1")

        let tab = store.openOrFocusCommandTab(
            workspaceId: "1",
            command: "codex --dangerously-bypass-approvals-and-sandbox",
            label: "Codex"
        )

        store.handleTerminalLineSubmission("Plan Blink release notes", for: tab.id)

        XCTAssertEqual(store.shellDetectedAIPaneKinds[tab.id], .codex)
        XCTAssertEqual(store.tabsById[tab.id]?.label, "Plan Blink release notes")
    }

    func testRestoreWorkspaceSetupResetsTransientShellTitles() {
        let store = makeStore()
        store.workspaceSetups["1"] = WorkspaceSetup(
            workspaceId: "1",
            updatedAt: .now,
            columns: [
                WorkspaceSetupColumn(id: "col-0", paneIds: ["pane-0"])
            ],
            panes: [
                WorkspaceSetupPane(
                    id: "pane-0",
                    kind: .shell,
                    label: "Codex",
                    role: nil,
                    command: nil,
                    workingDirectory: nil,
                    browserState: nil
                )
            ]
        )

        store.openWorkspaceSession("1")

        XCTAssertEqual(store.tabsById[store.activeTabId ?? ""]?.label, "Terminal 1")
        XCTAssertEqual(store.tabsById[store.activeTabId ?? ""]?.defaultLabel, "Terminal 1")
    }

    func testShellPromptDoesNotClearBufferedPendingCodexPrompt() {
        let store = makeStore()
        let surfaceManager = SurfaceManager()
        let surface = TerminalSurfaceView(
            app: GhosttyApp(),
            tabId: "t2",
            paneId: "pane-t2",
            workspaceId: "1",
            workspaceName: "blink",
            workingDirectory: "/tmp/blink"
        )
        surface.onSubmittedLine = { [weak store] line in
            store?.handleTerminalLineSubmission(line, for: "t2")
        }
        surfaceManager.surfaces["t2"] = surface
        store.surfaceManager = surfaceManager
        store.setActiveWorkspace("1")

        store.handleTerminalLineSubmission("codex", for: "t2")

        surface.sendText("Plan Blink release notes")
        store.handleTerminalTitleUpdate("~/Code/blink", for: "t2")
        surface.sendText("\n")

        XCTAssertEqual(store.shellDetectedAIPaneKinds["t2"], .codex)
        XCTAssertEqual(store.tabsById["t2"]?.label, "Plan Blink release notes")
    }

    func testShellPromptDoesNotClearBufferedCommandWhileTypingAtPrompt() {
        let store = makeStore()
        let surfaceManager = SurfaceManager()
        let surface = TerminalSurfaceView(
            app: GhosttyApp(),
            tabId: "t2",
            paneId: "pane-t2",
            workspaceId: "1",
            workspaceName: "blink",
            workingDirectory: "/tmp/blink"
        )
        surface.onSubmittedLine = { [weak store] line in
            store?.handleTerminalLineSubmission(line, for: "t2")
        }
        surfaceManager.surfaces["t2"] = surface
        store.surfaceManager = surfaceManager
        store.setActiveWorkspace("1")

        surface.sendText("co")
        store.handleTerminalTitleUpdate("~/Code/blink", for: "t2")
        surface.sendText("dex\n")

        XCTAssertEqual(store.shellDetectedAIPaneKinds["t2"], .codex)
        XCTAssertEqual(store.tabsById["t2"]?.label, "Codex")
    }

    func testShellPromptDoesNotClearCustomCodexPromptTitle() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        store.handleTerminalLineSubmission("codex", for: "t2")
        store.handleTerminalLineSubmission("Plan Blink release notes", for: "t2")

        store.handleTerminalTitleUpdate("~/Code/blink", for: "t2")

        XCTAssertEqual(store.shellDetectedAIPaneKinds["t2"], .codex)
        XCTAssertEqual(store.tabsById["t2"]?.label, "Plan Blink release notes")
    }

    func testShellPromptClearsTrackedTerminalInputWhilePreservingCodexState() {
        let store = makeStore()
        let surfaceManager = SurfaceManager()
        let surface = TerminalSurfaceView(
            app: GhosttyApp(),
            tabId: "t2",
            paneId: "pane-t2",
            workspaceId: "1",
            workspaceName: "blink",
            workingDirectory: "/tmp/blink"
        )
        var submittedLines: [String] = []
        surface.onSubmittedLine = { submittedLines.append($0) }
        surfaceManager.surfaces["t2"] = surface
        store.surfaceManager = surfaceManager
        store.setActiveWorkspace("1")

        store.handleTerminalLineSubmission("codex", for: "t2")
        store.handleTerminalLineSubmission("Plan Blink release notes", for: "t2")

        surface.sendText("stale")
        store.handleTerminalTitleUpdate("~/Code/blink", for: "t2")
        surface.sendText("codex\n")

        XCTAssertEqual(submittedLines, ["codex"])
        XCTAssertEqual(store.shellDetectedAIPaneKinds["t2"], .codex)
        XCTAssertEqual(store.tabsById["t2"]?.label, "Plan Blink release notes")
    }

    func testOpenFileInEditorCreatesNewTmuxNeovimTabWhenNoEditorPaneExists() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        let initialCount = store.workspaceTabs(for: "1").count
        var commands: [String] = []
        store.detachedShellCommandHandler = { commands.append($0) }

        store.openFileInEditor(workspaceId: "1", path: "/tmp/blink/README.md", line: 12)

        let tabs = store.workspaceTabs(for: "1")
        XCTAssertEqual(tabs.count, initialCount + 1)
        let newTab = try! XCTUnwrap(tabs.last)
        let paneId = try! XCTUnwrap(newTab.workspaceSetupPaneId)
        XCTAssertEqual(newTab.label, "Neovim")
        XCTAssertNil(newTab.command)
        XCTAssertEqual(store.activeTabId, newTab.id)
        XCTAssertTrue(commands.isEmpty)

        store.handleTerminalSurfaceReady(for: newTab.id)

        let command = try! XCTUnwrap(commands.first)
        let wrapperPath = NvimLauncher.wrapperCommandPath() ?? "nvim"
        XCTAssertTrue(command.contains("blink-1:pane-\(paneId)"))
        XCTAssertTrue(command.contains("send-keys"))
        XCTAssertTrue(command.contains(wrapperPath))
        XCTAssertTrue(command.contains("+12"))
        XCTAssertTrue(command.contains("/tmp/blink/README.md"))
    }

    func testOpenFileInEditorResolvesMissingWorkspacePathByUniqueSuffix() throws {
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let nestedDirectory = tempRoot
            .appendingPathComponent("Blink/Views", isDirectory: true)
        let actualFile = nestedDirectory.appendingPathComponent("Sidebar.swift")
        try fileManager.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
        try "struct SidebarView {}".write(to: actualFile, atomically: true, encoding: .utf8)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let store = makeStore()
        let originalWorkspace = store.workspaces[0]
        store.workspaces[0] = Workspace(
            id: originalWorkspace.id,
            name: originalWorkspace.name,
            path: tempRoot.path,
            color: originalWorkspace.color,
            createdAt: originalWorkspace.createdAt
        )
        store.setActiveWorkspace("1")
        var commands: [String] = []
        store.detachedShellCommandHandler = { commands.append($0) }

        store.openFileInEditor(
            workspaceId: "1",
            path: tempRoot.appendingPathComponent("Views/Sidebar.swift").path,
            line: 130
        )

        let newTab = try XCTUnwrap(store.workspaceTabs(for: "1").last)
        store.handleTerminalSurfaceReady(for: newTab.id)

        let command = try XCTUnwrap(commands.first)
        let missingPath = tempRoot.appendingPathComponent("Views/Sidebar.swift").path
        let wrapperPath = NvimLauncher.wrapperCommandPath() ?? "nvim"
        XCTAssertTrue(command.contains(wrapperPath))
        XCTAssertTrue(command.contains("+130"))
        XCTAssertTrue(command.contains(actualFile.path))
        XCTAssertFalse(command.contains(missingPath))
    }

    func testOpenFileInEditorUsesExternalEditorLauncherWhenConfigured() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        store.fileEditorLauncher = .cursor
        let initialCount = store.workspaceTabs(for: "1").count
        var commands: [String] = []
        store.detachedShellCommandHandler = { commands.append($0) }

        store.openFileInEditor(
            workspaceId: "1",
            path: "/tmp/blink/Blink/Views/Sidebar.swift",
            line: 130,
            column: 4
        )

        let command = try! XCTUnwrap(commands.first)
        XCTAssertEqual(store.workspaceTabs(for: "1").count, initialCount)
        XCTAssertTrue(command.contains("cursor "))
        XCTAssertTrue(command.contains("/tmp/blink/Blink/Views/Sidebar.swift:130:4"))
    }

    func testOpenFileInEditorUsesCustomEditorCommandTemplate() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        store.fileEditorLauncher = .custom
        store.fileEditorCustomCommand = "custom-open --path {path} --line {line} --column {column}"
        var commands: [String] = []
        store.detachedShellCommandHandler = { commands.append($0) }

        store.openFileInEditor(
            workspaceId: "1",
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
        store.setActiveWorkspace("1")
        store.columns["1"] = [Column(id: "c1", tabIds: ["t1", "t2"])]
        store.setActiveTab("t1")

        store.splitActivePaneWithNewTab()

        let cols = store.workspaceColumns(for: "1")
        XCTAssertEqual(cols.count, 1)
        XCTAssertEqual(cols[0].tabIds.count, 3)
        XCTAssertEqual(cols[0].tabIds[0], "t1")
        XCTAssertEqual(cols[0].tabIds[2], "t2")
        XCTAssertEqual(store.activeTabId, cols[0].tabIds[1])
    }

    func testSplitActivePaneWithNewTabFallsBackToOpenTabWithoutActivePane() {
        let store = makeStore()
        store.setActiveWorkspace("4")

        store.splitActivePaneWithNewTab()

        let cols = store.workspaceColumns(for: "4")
        XCTAssertEqual(cols.count, 1)
        XCTAssertEqual(cols[0].tabIds.count, 1)
        XCTAssertEqual(store.activeTabId, cols[0].tabIds[0])
    }

    func testSplitActiveColumnWithNewTabInsertsColumnToRight() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        store.setActiveTab("t1")

        store.splitActiveColumnWithNewTab()

        let cols = store.workspaceColumns(for: "1")
        XCTAssertEqual(cols.count, 3)
        XCTAssertEqual(cols[0].tabIds, ["t1"])
        XCTAssertEqual(cols[2].tabIds, ["t2"])
        XCTAssertEqual(cols[1].tabIds.count, 1)
        XCTAssertEqual(store.activeTabId, cols[1].tabIds[0])
    }

    func testCloseTabInMultiPaneColumnFocusesNext() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        // Stack t1 and t2 in same column
        store.columns["1"] = [Column(id: "c1", tabIds: ["t1", "t2"])]
        store.setActiveTab("t1")

        store.closeTab("t1")

        XCTAssertEqual(store.activeTabId, "t2")
        XCTAssertEqual(store.workspaceColumns(for: "1").count, 1)
        XCTAssertEqual(store.workspaceColumns(for: "1")[0].tabIds, ["t2"])
    }

    func testCloseLastTabInColumnRemovesColumn() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        store.setActiveTab("t1")

        store.closeTab("t1")

        XCTAssertEqual(store.workspaceColumns(for: "1").count, 1)
        XCTAssertEqual(store.activeTabId, "t2")
    }

    func testRemoveWorkspaceCleansUpColumns() {
        let store = makeStore()
        store.columnFocusedTab["c1"] = "t1"
        store.removeWorkspace("1")
        XCTAssertNil(store.columns["1"])
        XCTAssertNil(store.columnFocusedTab["c1"])
    }

    // MARK: - Column Helper Tests

    func testWorkspaceColumns() {
        let store = makeStore()
        let cols = store.workspaceColumns(for: "1")
        XCTAssertEqual(cols.count, 2)
        XCTAssertEqual(cols[0].tabIds, ["t1"])
        XCTAssertEqual(cols[1].tabIds, ["t2"])
    }

    func testWorkspaceColumnsEmpty() {
        let store = makeStore()
        let cols = store.workspaceColumns(for: "4")
        XCTAssertEqual(cols.count, 0)
    }

    func testColumnForTabId() {
        let store = makeStore()
        let col = store.columnFor(tabId: "t1")
        XCTAssertEqual(col?.id, "c1")
    }

    func testActiveColumn() {
        let store = makeStore()
        store.setActiveWorkspace("1")
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
        store.setActiveWorkspace("1")
        store.columns["1"] = [Column(id: "c1", tabIds: ["t1", "t2"])]
        store.setActiveTab("t1")

        store.focusDown()

        XCTAssertEqual(store.activeTabId, "t2")
    }

    func testFocusDownNoOpAtBottom() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        store.columns["1"] = [Column(id: "c1", tabIds: ["t1", "t2"])]
        store.setActiveTab("t2")

        store.focusDown()

        XCTAssertEqual(store.activeTabId, "t2")
    }

    func testFocusUp() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        store.columns["1"] = [Column(id: "c1", tabIds: ["t1", "t2"])]
        store.setActiveTab("t2")

        store.focusUp()

        XCTAssertEqual(store.activeTabId, "t1")
    }

    func testFocusUpNoOpAtTop() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        store.columns["1"] = [Column(id: "c1", tabIds: ["t1", "t2"])]
        store.setActiveTab("t1")

        store.focusUp()

        XCTAssertEqual(store.activeTabId, "t1")
    }

    func testFocusLeftRestoresColumnMemory() {
        let store = makeStore()
        store.setActiveWorkspace("1")
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
        store.setActiveWorkspace("1")
        store.setActiveTab("t1")

        store.moveColumnRight()

        let cols = store.workspaceColumns(for: "1")
        XCTAssertEqual(cols[0].tabIds, ["t2"])
        XCTAssertEqual(cols[1].tabIds, ["t1"])
    }

    func testMoveColumnLeft() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        store.setActiveTab("t2")

        store.moveColumnLeft()

        let cols = store.workspaceColumns(for: "1")
        XCTAssertEqual(cols[0].tabIds, ["t2"])
        XCTAssertEqual(cols[1].tabIds, ["t1"])
    }

    func testMoveColumnRightNoOpAtEnd() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        store.setActiveTab("t2")

        store.moveColumnRight()

        let cols = store.workspaceColumns(for: "1")
        XCTAssertEqual(cols[0].tabIds, ["t1"])
        XCTAssertEqual(cols[1].tabIds, ["t2"])
    }

    // MARK: - Absorb & Expel Tests

    func testAbsorbFromLeft() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        store.setActiveTab("t2")

        store.absorbFromLeft()

        let cols = store.workspaceColumns(for: "1")
        XCTAssertEqual(cols.count, 1)
        XCTAssertEqual(cols[0].tabIds, ["t2", "t1"])
    }

    func testAbsorbFromRight() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        store.setActiveTab("t1")

        store.absorbFromRight()

        let cols = store.workspaceColumns(for: "1")
        XCTAssertEqual(cols.count, 1)
        XCTAssertEqual(cols[0].tabIds, ["t1", "t2"])
    }

    func testAbsorbFromLeftNoOpAtFirstColumn() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        store.setActiveTab("t1")

        store.absorbFromLeft()

        XCTAssertEqual(store.workspaceColumns(for: "1").count, 2)
    }

    func testExpelActiveTab() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        store.columns["1"] = [Column(id: "c1", tabIds: ["t1", "t2"])]
        store.setActiveTab("t1")

        store.expelActiveTab()

        let cols = store.workspaceColumns(for: "1")
        XCTAssertEqual(cols.count, 2)
        XCTAssertEqual(cols[0].tabIds, ["t2"])
        XCTAssertEqual(cols[1].tabIds, ["t1"])
        XCTAssertEqual(store.activeTabId, "t1")
    }

    func testExpelNoOpOnSingleTabColumn() {
        let store = makeStore()
        store.setActiveWorkspace("1")
        store.setActiveTab("t1")

        store.expelActiveTab()

        XCTAssertEqual(store.workspaceColumns(for: "1").count, 2)
    }

    private func makeStore() -> AppStore {
        let store = AppStore()
        store.workspaces = [
            workspace(id: "1", name: "blink"),
            workspace(id: "2", name: "krux"),
            workspace(id: "3", name: "api-server"),
            workspace(id: "4", name: "dotfiles"),
        ]
        store.tabs = [
            AppTab(id: "t1", type: "shell", label: "Terminal 1", defaultLabel: "Terminal 1", workspaceId: "1"),
            AppTab(id: "t2", type: "shell", label: "Terminal 2", defaultLabel: "Terminal 2", workspaceId: "1"),
            AppTab(id: "t3", type: "shell", label: "Terminal 1", defaultLabel: "Terminal 1", workspaceId: "2"),
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
        store.activeWorkspaceId = nil
        store.activeTabId = nil
        store.lastSelectedWorkspaceId = nil
        store.unreadTabs = []
        return store
    }

    private func workspace(id: String, name: String) -> Workspace {
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("blink-appstore-tests", isDirectory: true)
        let path = root.appendingPathComponent(name, isDirectory: true)
        try? fileManager.createDirectory(at: path, withIntermediateDirectories: true)
        return Workspace(
            id: id,
            name: name,
            path: path.path,
            color: "#7aa2f7",
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }
}
