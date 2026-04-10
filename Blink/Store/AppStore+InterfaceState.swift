import SwiftUI
import AppKit

extension AppStore {
    // MARK: - View Actions

    func setActiveView(_ view: ActiveView) {
        activeView = view
    }

    func toggleSettings() {
        showCommandPalette = false
        activeView = activeView == .settings ? .workspaces : .settings
    }

    func toggleSidebar() {
        withAnimation(.snappy(duration: 0.18, extraBounce: 0)) {
            sidebarVisible.toggle()
            if sidebarVisible && activeTabId == nil {
                sidebarFocused = true
                workspaceLandingFocused = false
            } else if !sidebarVisible {
                sidebarFocused = false
            }
        }
    }

    func isWorkspaceExpanded(_ id: String) -> Bool {
        expandedWorkspaceIds.contains(id)
    }

    func expandWorkspace(_ id: String) {
        expandedWorkspaceIds.insert(id)
    }

    func collapseWorkspace(_ id: String) {
        expandedWorkspaceIds.remove(id)
    }

    func toggleWorkspaceExpansion(_ id: String) {
        if isWorkspaceExpanded(id) {
            collapseWorkspace(id)
        } else {
            expandWorkspace(id)
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
            workspaceLandingFocused = false
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
        sidebarFocusProtectionDeadline = Date().addingTimeInterval(0.2)
        sidebarFocused = true
        workspaceLandingFocused = false
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

    func selectNextWorkspace() {
        guard !workspaces.isEmpty else { return }
        guard let currentId = activeWorkspaceId,
              let idx = workspaces.firstIndex(where: { $0.id == currentId }) else {
            setActiveWorkspace(workspaces.first?.id)
            return
        }
        let next = workspaces.index(after: idx)
        if next < workspaces.endIndex {
            setActiveWorkspace(workspaces[next].id)
        }
    }

    func selectPreviousWorkspace() {
        guard !workspaces.isEmpty else { return }
        guard let currentId = activeWorkspaceId,
              let idx = workspaces.firstIndex(where: { $0.id == currentId }) else {
            setActiveWorkspace(workspaces.last?.id)
            return
        }
        if idx > workspaces.startIndex {
            setActiveWorkspace(workspaces[workspaces.index(before: idx)].id)
        }
    }

    func presentWorkspaceSwitcher(focusSearch: Bool = false) {
        guard !workspaces.isEmpty else { return }
        workspacePrompt = nil
        showWorkspaceOnboarding = false
        showAISessionPicker = false
        showCommandPalette = false
        showWorkspaceSwitcher = true
        if focusSearch {
            workspaceSwitcherFocusRequest += 1
        }
    }

    func dismissWorkspaceSwitcher() {
        showWorkspaceSwitcher = false
    }

    func presentWorkspaceOnboarding() {
        sidebarFocused = false
        workspaceLandingFocused = false
        activeView = .workspaces
        workspacePrompt = nil
        showNewTabMenu = false
        showWorkspaceSwitcher = false
        showThemePicker = false
        showAISessionPicker = false
        showCommandPalette = false
        showWorkspaceOnboarding = true
    }

    func dismissWorkspaceOnboarding() {
        showWorkspaceOnboarding = false
    }

    func presentThemePicker(focusSearch: Bool = false) {
        sidebarFocused = false
        workspaceLandingFocused = false
        workspacePrompt = nil
        showWorkspaceOnboarding = false
        showWorkspaceSwitcher = false
        showAISessionPicker = false
        showCommandPalette = false
        showThemePicker = true
        if focusSearch {
            themePickerFocusRequest += 1
        }
    }

    func dismissThemePicker() {
        showThemePicker = false
    }

    func presentAISessionPicker() {
        sidebarFocused = false
        workspacePrompt = nil
        showWorkspaceOnboarding = false
        showWorkspaceSwitcher = false
        showThemePicker = false
        showCommandPalette = false
        showAISessionPicker = true
    }

    func dismissAISessionPicker() {
        showAISessionPicker = false
    }

    func presentCommandPalette() {
        sidebarFocused = false
        workspacePrompt = nil
        showWorkspaceOnboarding = false
        showAISessionPicker = false
        showWorkspaceSwitcher = false
        showThemePicker = false
        showCommandPalette = true
    }

    func dismissCommandPalette() {
        showCommandPalette = false
    }

    func dismissWorkspacePrompt() {
        workspacePrompt = nil
    }

    func aiSessionLaunchSpec(for provider: WorkspaceAIProvider) -> (command: String, label: String) {
        switch provider {
        case .claude:
            return ("claude --dangerously-skip-permissions", "Claude Code")
        case .codex:
            return ("codex --dangerously-bypass-approvals-and-sandbox", "Codex")
        case .opencode:
            return ("opencode", "OpenCode")
        }
    }

    @discardableResult
    func openClaudeSession() -> AppTab? {
        guard let workspaceId = aiSessionWorkspaceId() else { return nil }
        let spec = aiSessionLaunchSpec(for: .claude)
        return openTab(workspaceId: workspaceId, command: spec.command, label: spec.label)
    }

    @discardableResult
    func openCodexSession() -> AppTab? {
        guard let workspaceId = aiSessionWorkspaceId() else { return nil }
        let spec = aiSessionLaunchSpec(for: .codex)
        return openTab(workspaceId: workspaceId, command: spec.command, label: spec.label)
    }

    @discardableResult
    func openOpenCodeSession() -> AppTab? {
        guard let workspaceId = aiSessionWorkspaceId() else { return nil }
        let spec = aiSessionLaunchSpec(for: .opencode)
        return openTab(workspaceId: workspaceId, command: spec.command, label: spec.label)
    }

    private func aiSessionWorkspaceId() -> String? {
        if let activeWorkspaceId {
            return activeWorkspaceId
        }

        openScratchSpace()
        return activeWorkspaceId
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
}
