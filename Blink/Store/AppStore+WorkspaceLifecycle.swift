import AppKit
import SwiftUI

struct SidebarProfileSection: Identifiable, Equatable {
    let profile: Profile
    let workspaces: [Workspace]

    var id: String { profile.id }
}

extension AppStore {
    var defaultProfile: Profile {
        profiles.first(where: \.isBuiltIn) ?? Profile.personal()
    }

    func profile(withId id: String) -> Profile? {
        profiles.first { $0.id == id }
    }

    func profileName(for profileId: String) -> String {
        profile(withId: profileId)?.name ?? defaultProfile.name
    }

    func profileId(for workspaceId: String) -> String {
        workspaces.first(where: { $0.id == workspaceId })?.profileId ?? defaultProfile.id
    }

    var sidebarProfileSections: [SidebarProfileSection] {
        profiles.compactMap { profile in
            let attachedWorkspaces = workspaces.filter { $0.profileId == profile.id }
            guard !attachedWorkspaces.isEmpty else { return nil }
            return SidebarProfileSection(
                profile: profile,
                workspaces: attachedWorkspaces
            )
        }
    }

    var sidebarOrderedWorkspaces: [Workspace] {
        sidebarProfileSections.flatMap(\.workspaces)
    }

    func addProfile(name: String) -> Profile? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        guard !profiles.contains(where: { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }) else {
            return profiles.first(where: { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame })
        }

        let profile = Profile(
            id: UUID().uuidString,
            name: trimmedName,
            color: nextProfileColor(),
            createdAt: .now
        )
        profiles.append(profile)
        return profile
    }

    @discardableResult
    func renameProfile(_ id: String, to name: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              let index = profiles.firstIndex(where: { $0.id == id }) else {
            return false
        }

        let profile = profiles[index]
        guard !profile.isBuiltIn else { return false }

        profiles[index] = Profile(
            id: profile.id,
            name: trimmedName,
            color: profile.color,
            createdAt: profile.createdAt
        )
        return true
    }

    @discardableResult
    func removeProfile(_ id: String) -> Bool {
        guard let profile = profile(withId: id), !profile.isBuiltIn else { return false }

        let replacementProfileId = defaultProfile.id
        for workspace in workspaces where workspace.profileId == id {
            _ = setWorkspaceProfile(workspace.id, profileId: replacementProfileId)
        }
        BlinkChromiumRuntime.shared().removeStorage(forProfileIdentifier: profile.id)
        BrowserProfileStorage.removeStorage(for: profile.id)
        profiles.removeAll { $0.id == id }
        return true
    }

    @discardableResult
    func resetBrowserStorage(for profileId: String) -> Bool {
        guard profile(withId: profileId) != nil else { return false }

        let affectedWorkspaceIds = workspaces
            .filter { $0.profileId == profileId }
            .map(\.id)
        let browserTabIds = affectedWorkspaceIds.flatMap { workspaceId in
            workspaceTabs(for: workspaceId).flatMap { browserControllerIds(for: $0) }
        }

        browserManager?.destroyControllers(tabIds: browserTabIds)
        BlinkChromiumRuntime.shared().removeStorage(forProfileIdentifier: profileId)
        BrowserProfileStorage.removeStorage(for: profileId)

        for workspaceId in affectedWorkspaceIds {
            for index in tabs.indices where tabs[index].workspaceId == workspaceId && tabs[index].isBrowser {
                guard var paneState = tabs[index].browserState else { continue }
                for browserTabIndex in paneState.tabs.indices {
                    paneState.tabs[browserTabIndex].state = BrowserTabState(
                        urlString: paneState.tabs[browserTabIndex].state.urlString,
                        title: nil,
                        canGoBack: false,
                        canGoForward: false,
                        isLoading: false,
                        preferredFocus: paneState.tabs[browserTabIndex].state.preferredFocus
                    )
                }
                tabs[index].browserState = paneState
                tabs[index].label = browserPaneLabel(for: paneState, fallback: tabs[index].defaultLabel)
            }
        }

        return true
    }

    @discardableResult
    func setWorkspaceProfile(_ workspaceId: String, profileId: String) -> Bool {
        guard profile(withId: profileId) != nil,
              let index = workspaces.firstIndex(where: { $0.id == workspaceId }) else {
            return false
        }

        let workspace = workspaces[index]
        guard workspace.profileId != profileId else { return true }

        workspaces[index] = Workspace(
            id: workspace.id,
            name: workspace.name,
            path: workspace.path,
            profileId: profileId,
            color: workspace.color,
            createdAt: workspace.createdAt
        )

        let browserTabIds = workspaceTabs(for: workspaceId).flatMap { browserControllerIds(for: $0) }
        browserManager?.destroyControllers(tabIds: browserTabIds)
        return true
    }

    @discardableResult
    func reorderWorkspace(_ workspaceId: String, inProfile profileId: String, to insertionIndex: Int) -> Bool {
        guard let sourceGlobalIndex = workspaces.firstIndex(where: { $0.id == workspaceId }) else {
            return false
        }

        let profileWorkspaces = workspaces.filter { $0.profileId == profileId }
        guard !profileWorkspaces.isEmpty,
              workspaces[sourceGlobalIndex].profileId == profileId else {
            return false
        }

        let clampedInsertionIndex = min(max(insertionIndex, 0), profileWorkspaces.count)
        guard let sourceLocalIndex = profileWorkspaces.firstIndex(where: { $0.id == workspaceId }) else {
            return false
        }

        let adjustedInsertionIndex = clampedInsertionIndex > sourceLocalIndex
            ? clampedInsertionIndex - 1
            : clampedInsertionIndex
        guard adjustedInsertionIndex != sourceLocalIndex else { return false }

        var updatedWorkspaces = workspaces
        let workspace = updatedWorkspaces.remove(at: sourceGlobalIndex)
        let remainingProfileIndices = updatedWorkspaces.indices.filter { updatedWorkspaces[$0].profileId == profileId }

        let destinationGlobalIndex: Int
        if adjustedInsertionIndex >= remainingProfileIndices.count {
            destinationGlobalIndex = remainingProfileIndices.last.map {
                updatedWorkspaces.index(after: $0)
            } ?? updatedWorkspaces.endIndex
        } else {
            destinationGlobalIndex = remainingProfileIndices[adjustedInsertionIndex]
        }

        updatedWorkspaces.insert(workspace, at: destinationGlobalIndex)
        workspaces = updatedWorkspaces
        return true
    }

    func normalizedWorkspacePath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    func workspaceForPath(_ path: String) -> Workspace? {
        let normalizedPath = normalizedWorkspacePath(path)
        return workspaces.first { normalizedWorkspacePath($0.path) == normalizedPath }
    }

    func isValidWorkspaceFolderName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return !trimmed.contains("/") && trimmed != "." && trimmed != ".."
    }

    private func chooseWorkspaceDirectory(message: String, startingAt path: String? = nil) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = message

        if let path {
            let normalizedPath = normalizedWorkspacePath(path)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: normalizedPath, isDirectory: &isDirectory) {
                let url = URL(fileURLWithPath: normalizedPath)
                panel.directoryURL = isDirectory.boolValue ? url : url.deletingLastPathComponent()
            } else {
                panel.directoryURL = URL(fileURLWithPath: normalizedPath).deletingLastPathComponent()
            }
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        return normalizedWorkspacePath(url.path)
    }

    func chooseExistingWorkspaceFolder(startingAt path: String? = nil) -> String? {
        chooseWorkspaceDirectory(
            message: "Select a workspace folder",
            startingAt: path
        )
    }

    func chooseWorkspaceParentFolder(startingAt path: String? = nil) -> String? {
        chooseWorkspaceDirectory(
            message: "Select the parent folder for the new workspace",
            startingAt: path
        )
    }

    private func seededWorkspaceSetup(
        for workspaceId: String,
        starter: WorkspaceStarter,
        aiProvider: WorkspaceAIProvider,
        browserURL: String
    ) -> WorkspaceSetup? {
        let paneId = makeWorkspaceSetupPaneId()
        let trimmedBrowserURL = browserURL.trimmingCharacters(in: .whitespacesAndNewlines)

        let pane: WorkspaceSetupPane?
        switch starter {
        case .empty:
            pane = nil
        case .terminal:
            pane = WorkspaceSetupPane(
                id: paneId,
                kind: .shell,
                label: "Terminal 1",
                role: nil,
                command: nil,
                workingDirectory: nil,
                browserState: nil
            )
        case .aiSession:
            let spec = aiSessionLaunchSpec(for: aiProvider)
            pane = WorkspaceSetupPane(
                id: paneId,
                kind: .command,
                label: spec.label,
                role: nil,
                command: spec.command,
                workingDirectory: nil,
                browserState: nil
            )
        case .browser:
            let resolvedURL = trimmedBrowserURL.isEmpty ? BrowserDefaults.homePageURLString : trimmedBrowserURL
            let state = BrowserPaneState.singleTab(
                urlString: BrowserURLResolver.resolve(resolvedURL)?.absoluteString ?? resolvedURL,
                preferredFocus: .addressBar
            )
            pane = WorkspaceSetupPane(
                id: paneId,
                kind: .browser,
                label: browserPaneLabel(for: state, fallback: "Workspace Browser 1"),
                role: nil,
                command: nil,
                workingDirectory: nil,
                browserState: state
            )
        case .git:
            pane = WorkspaceSetupPane(
                id: paneId,
                kind: .command,
                label: "lazygit",
                role: nil,
                command: "lazygit",
                workingDirectory: nil,
                browserState: nil
            )
        case .neovim:
            pane = WorkspaceSetupPane(
                id: paneId,
                kind: .command,
                label: "Neovim",
                role: nil,
                command: NvimLauncher.command(theme: TerminalTheme.load(name: theme)),
                workingDirectory: nil,
                browserState: nil
            )
        case .files:
            pane = WorkspaceSetupPane(
                id: paneId,
                kind: .command,
                label: "Yazi",
                role: nil,
                command: YaziLauncher.command(theme: nil),
                workingDirectory: nil,
                browserState: nil
            )
        }

        guard let pane else { return nil }
        return WorkspaceSetup(
            workspaceId: workspaceId,
            updatedAt: .now,
            columns: [WorkspaceSetupColumn(id: "col-0", paneIds: [pane.id])],
            panes: [pane]
        )
    }

    @discardableResult
    func completeWorkspaceOnboarding(
        mode: WorkspaceOnboardingMode,
        name: String,
        existingFolderPath: String,
        parentFolderPath: String,
        newFolderName: String,
        profileId: String,
        starter: WorkspaceStarter,
        aiProvider: WorkspaceAIProvider,
        browserURL: String
    ) throws -> Workspace {
        let fileManager = FileManager.default
        let resolvedURL: URL

        switch mode {
        case .existingFolder:
            let trimmedPath = existingFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedPath.isEmpty else {
                throw WorkspaceCreationError.missingWorkspaceFolder
            }

            let normalizedPath = normalizedWorkspacePath(trimmedPath)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: normalizedPath, isDirectory: &isDirectory) else {
                throw WorkspaceCreationError.workspaceFolderDoesNotExist
            }
            guard isDirectory.boolValue else {
                throw WorkspaceCreationError.selectedPathIsNotDirectory
            }

            resolvedURL = URL(fileURLWithPath: normalizedPath)

        case .createFolder:
            let trimmedParentPath = parentFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedParentPath.isEmpty else {
                throw WorkspaceCreationError.missingParentFolder
            }

            let trimmedFolderName = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedFolderName.isEmpty else {
                throw WorkspaceCreationError.missingFolderName
            }
            guard isValidWorkspaceFolderName(trimmedFolderName) else {
                throw WorkspaceCreationError.invalidFolderName
            }

            let normalizedParentPath = normalizedWorkspacePath(trimmedParentPath)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: normalizedParentPath, isDirectory: &isDirectory) else {
                throw WorkspaceCreationError.parentFolderDoesNotExist
            }
            guard isDirectory.boolValue else {
                throw WorkspaceCreationError.selectedPathIsNotDirectory
            }

            let workspaceURL = URL(fileURLWithPath: normalizedParentPath, isDirectory: true)
                .appendingPathComponent(trimmedFolderName, isDirectory: true)
                .standardizedFileURL

            if fileManager.fileExists(atPath: workspaceURL.path, isDirectory: &isDirectory) {
                guard isDirectory.boolValue else {
                    throw WorkspaceCreationError.selectedPathIsNotDirectory
                }
            } else {
                do {
                    try fileManager.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
                } catch {
                    throw WorkspaceCreationError.failedToCreateFolder(workspaceURL.path)
                }
            }

            resolvedURL = workspaceURL
        }

        if let existing = workspaceForPath(resolvedURL.path) {
            openWorkspaceSession(existing.id)
            return existing
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let workspace = addWorkspace(
            name: trimmedName.isEmpty ? nil : trimmedName,
            path: resolvedURL.path,
            profileId: profileId,
            activating: false
        )

        if workspaceTabs(for: workspace.id).isEmpty,
           !hasWorkspaceSetup(for: workspace.id),
           let setup = seededWorkspaceSetup(
            for: workspace.id,
            starter: starter,
            aiProvider: aiProvider,
            browserURL: browserURL
           ) {
            workspaceSetups[workspace.id] = setup
        }

        openWorkspaceSession(workspace.id)
        return workspace
    }

    @discardableResult
    func addWorkspace(
        name: String? = nil,
        path: String,
        profileId: String = Profile.personalId,
        activating: Bool = false
    ) -> Workspace {
        let normalizedPath = normalizedWorkspacePath(path)

        if let existing = workspaces.first(where: { normalizedWorkspacePath($0.path) == normalizedPath }) {
            if activating {
                openWorkspaceSession(existing.id)
            }
            return existing
        }

        let resolvedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let workspaceName = resolvedName?.isEmpty == false
            ? resolvedName!
            : (normalizedPath as NSString).lastPathComponent
        let workspace = Workspace(
            id: UUID().uuidString,
            name: workspaceName,
            path: normalizedPath,
            profileId: profile(withId: profileId)?.id ?? defaultProfile.id,
            color: "#7aa2f7",
            createdAt: .now
        )
        workspaces.append(workspace)
        expandedWorkspaceIds.insert(workspace.id)
        if activating {
            openWorkspaceSession(workspace.id)
        }
        return workspace
    }

    @discardableResult
    func pickWorkspaceFolder(activating: Bool = false) -> Workspace? {
        guard let path = chooseExistingWorkspaceFolder() else {
            return nil
        }

        return addWorkspace(path: path, activating: activating)
    }

    func workspaceViewportOffset(for workspaceId: String) -> CGFloat {
        CGFloat(workspaceViewportOffsets[workspaceId] ?? 0)
    }

    func hasWorkspaceViewportOffset(for workspaceId: String) -> Bool {
        workspaceViewportOffsets[workspaceId] != nil
    }

    func setWorkspaceViewportOffset(_ offset: CGFloat, for workspaceId: String) {
        workspaceViewportOffsets[workspaceId] = Double(offset)
    }

    func workspaceColumnFractions(for workspaceId: String) -> [String: CGFloat] {
        (workspaceColumnFractions[workspaceId] ?? [:]).reduce(into: [:]) { result, entry in
            result[entry.key] = CGFloat(entry.value)
        }
    }

    func setWorkspaceColumnFraction(_ fraction: CGFloat, for columnId: String, workspaceId: String) {
        var fractions = workspaceColumnFractions[workspaceId] ?? [:]
        fractions[columnId] = Double(fraction)
        workspaceColumnFractions[workspaceId] = fractions
    }

    func syncWorkspaceColumnFractions(for workspaceId: String, validColumnIds: [String]) {
        let validIds = Set(validColumnIds)
        let existing = workspaceColumnFractions[workspaceId] ?? [:]
        let filtered = existing.filter { validIds.contains($0.key) }

        if filtered.isEmpty {
            if workspaceColumnFractions[workspaceId] != nil {
                workspaceColumnFractions[workspaceId] = nil
            }
            return
        }

        if filtered != existing {
            workspaceColumnFractions[workspaceId] = filtered
        }
    }
}

extension AppStore {
    static func loadProfiles() -> [Profile] {
        let persistedProfiles: [Profile]
        if let data = UserDefaults.standard.data(forKey: StorageKeys.profiles),
           let decodedProfiles = try? JSONDecoder().decode([Profile].self, from: data) {
            persistedProfiles = decodedProfiles.filter { !$0.isBuiltIn }
        } else {
            persistedProfiles = []
        }

        return [Profile.personal()] + persistedProfiles
    }

    static func saveProfiles(_ profiles: [Profile]) {
        let persistedProfiles = profiles.filter { !$0.isBuiltIn }
        if let data = try? JSONEncoder().encode(persistedProfiles) {
            UserDefaults.standard.set(data, forKey: StorageKeys.profiles)
        }
    }

    static func normalizedProfiles(_ profiles: [Profile], for workspaces: [Workspace]) -> [Profile] {
        var resolvedProfiles = profiles
        var existingIds = Set(resolvedProfiles.map(\.id))

        let legacyWorkspaceProfiles = workspaces.compactMap { workspace -> Profile? in
            guard !existingIds.contains(workspace.profileId) else { return nil }
            existingIds.insert(workspace.profileId)
            return Profile(
                id: workspace.profileId,
                name: workspace.name,
                color: workspace.color,
                createdAt: workspace.createdAt
            )
        }

        resolvedProfiles.append(contentsOf: legacyWorkspaceProfiles)
        return resolvedProfiles
    }

    static func normalizedWorkspaces(
        _ workspaces: [Workspace],
        availableProfileIds: Set<String>
    ) -> [Workspace] {
        workspaces.map { workspace in
            guard availableProfileIds.contains(workspace.profileId) else {
                return Workspace(
                    id: workspace.id,
                    name: workspace.name,
                    path: workspace.path,
                    profileId: Profile.personalId,
                    color: workspace.color,
                    createdAt: workspace.createdAt
                )
            }
            return workspace
        }
    }

    static func loadWorkspaces() -> [Workspace] {
        let persistedWorkspaces: [Workspace]
        if let data = UserDefaults.standard.data(forKey: StorageKeys.workspaces)
            ?? UserDefaults.standard.data(forKey: StorageKeys.legacyWorkspaces),
           let decodedWorkspaces = try? JSONDecoder().decode([Workspace].self, from: data) {
            persistedWorkspaces = decodedWorkspaces.filter { !$0.isScratchSpace && directoryExists(at: $0.path) }
        } else {
            persistedWorkspaces = []
        }

        return [Workspace.scratchSpace()] + persistedWorkspaces
    }

    static func saveWorkspaces(_ workspaces: [Workspace]) {
        let persistedWorkspaces = workspaces.filter { !$0.isScratchSpace }
        if let data = try? JSONEncoder().encode(persistedWorkspaces) {
            UserDefaults.standard.set(data, forKey: StorageKeys.workspaces)
        }
    }

    static func loadColumns() -> [String: [Column]] {
        guard let data = UserDefaults.standard.data(forKey: StorageKeys.columns),
              let columns = try? JSONDecoder().decode([String: [Column]].self, from: data) else {
            return [:]
        }
        return columns
    }

    static func saveColumns(_ columns: [String: [Column]]) {
        if let data = try? JSONEncoder().encode(columns) {
            UserDefaults.standard.set(data, forKey: StorageKeys.columns)
        }
    }

    static func loadWorkspaceSetups() -> [String: WorkspaceSetup] {
        guard let data = UserDefaults.standard.data(forKey: StorageKeys.workspaceSetups)
            ?? UserDefaults.standard.data(forKey: StorageKeys.legacyWorkspaceSetups),
              let setups = try? JSONDecoder().decode([String: WorkspaceSetup].self, from: data) else {
            return [:]
        }
        return setups.reduce(into: [:]) { result, entry in
            let sanitized = sanitizeLegacyChatPanes(in: entry.value)
            guard !sanitized.columns.isEmpty, !sanitized.panes.isEmpty else { return }
            result[entry.key] = sanitized
        }
    }

    static func saveWorkspaceSetups(_ setups: [String: WorkspaceSetup]) {
        if let data = try? JSONEncoder().encode(setups) {
            UserDefaults.standard.set(data, forKey: StorageKeys.workspaceSetups)
        }
    }

    static func sanitizeLegacyChatPanes(in setup: WorkspaceSetup) -> WorkspaceSetup {
        let allowedPaneIds = Set(
            setup.panes
                .filter { $0.kind != .chat }
                .map(\.id)
        )
        let panes = setup.panes.filter { allowedPaneIds.contains($0.id) }
        let columns: [WorkspaceSetupColumn] = setup.columns.compactMap { column in
            let paneIds = column.paneIds.filter { allowedPaneIds.contains($0) }
            guard !paneIds.isEmpty else { return nil }
            return WorkspaceSetupColumn(id: column.id, paneIds: paneIds)
        }
        return WorkspaceSetup(
            workspaceId: setup.workspaceId,
            updatedAt: setup.updatedAt,
            columns: columns,
            panes: panes
        )
    }

    static func directoryExists(at path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    static func loadDictionary<Value: Decodable>(forKey key: String) -> [String: Value] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode([String: Value].self, from: data) else {
            return [:]
        }
        return value
    }

    static func saveDictionary<Value: Encodable>(_ value: [String: Value], forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func nextProfileColor() -> String {
        let colors = [
            "#89b4fa",
            "#a6e3a1",
            "#f9e2af",
            "#f38ba8",
            "#94e2d5",
            "#cba6f7",
            "#fab387"
        ]
        return colors[profiles.count % colors.count]
    }
}
