import SwiftUI

private enum SidebarTreeSelection: Hashable {
    case workspace(String)
    case tab(workspaceId: String, tabId: String)

    var workspaceId: String {
        switch self {
        case .workspace(let workspaceId):
            return workspaceId
        case .tab(let workspaceId, _):
            return workspaceId
        }
    }
}

/// Workspace list — the middle section of the sidebar column.
/// Header/footer are handled by Shell's top bar and footer rows.
struct SidebarView: View {
    @Environment(AppStore.self) private var store
    @Environment(ThemeManager.self) private var themeManager

    @State private var keyMonitor: Any?
    @State private var selectedRow: SidebarTreeSelection?

    var body: some View {
        VStack(spacing: 0) {
            SidebarHeader(
                onPickWorkspaceFolder: { store.presentWorkspaceOnboarding() },
                onToggleNewWindowMenu: { store.showNewTabMenu.toggle() },
                onNewTabAction: handleNewWindowAction
            )

            Color.clear
                .frame(height: 1)
                .overlay(alignment: .center) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 1)
                }

            AllWorkspacesSidebarView(
                selectedRow: selectedRow,
                onSelectWorkspace: { workspaceId, shouldActivate in
                    if shouldActivate {
                        activate(.workspace(workspaceId))
                    } else {
                        select(.workspace(workspaceId))
                    }
                },
                onToggleWorkspaceExpansion: { workspaceId in
                    selectedRow = .workspace(workspaceId)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        store.toggleWorkspaceExpansion(workspaceId)
                    }
                },
                onSelectTab: { workspaceId, tabId, shouldActivate in
                    if shouldActivate {
                        activate(.tab(workspaceId: workspaceId, tabId: tabId))
                    } else {
                        select(.tab(workspaceId: workspaceId, tabId: tabId))
                    }
                }
            )
            .frame(maxHeight: .infinity)

            SidebarNowPlaying()
        }
        .onAppear {
            scheduleSelectionSync()
            installKeyMonitor()
        }
        .onChange(of: selectionSyncToken) { _, _ in
            scheduleSelectionSync()
        }
        .onDisappear { removeKeyMonitor() }
    }

    private func handleNewWindowAction(_ action: NewTabAction) {
        store.showNewTabMenu = false
        guard let workspaceId = store.activeWorkspaceId else { return }

        switch action {
        case .terminal:
            store.openTab(workspaceId: workspaceId)
        case .aiSession:
            store.presentAISessionPicker()
        case .browser:
            store.openBrowserTabForActiveWorkspace()
        case .lazygit:
            store.openOrFocusCommandTab(workspaceId: workspaceId, command: "lazygit", label: "lazygit")
        case .yazi:
            let command = YaziLauncher.command(theme: themeManager.activeTerminalTheme)
            store.openOrFocusCommandTab(workspaceId: workspaceId, command: command, label: "Yazi")
        case .neovim:
            let command = NvimLauncher.command()
            store.openOrFocusCommandTab(workspaceId: workspaceId, command: command, label: "Neovim")
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard store.sidebarFocused else { return event }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // Never intercept command-driven app shortcuts while the sidebar is focused.
            if modifiers.contains(.command) || modifiers.contains(.option) || modifiers.contains(.control) {
                return event
            }

            if modifiers.isEmpty {
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "j":
                    moveSelection(by: 1)
                    return nil
                case "k":
                    moveSelection(by: -1)
                    return nil
                case "h":
                    collapseSelectedRow()
                    return nil
                case "l":
                    expandSelectedRow()
                    return nil
                default:
                    break
                }
            }

            if modifiers.isEmpty {
                switch event.keyCode {
                case 53:
                    store.focusTerminal()
                    return nil
                case 36:
                    activateSelectedRow()
                    return nil
                case 123:
                    collapseSelectedRow()
                    return nil
                case 124:
                    expandSelectedRow()
                    return nil
                default:
                    break
                }
            }

            return event
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private var visibleRows: [SidebarTreeSelection] {
        store.workspaces.flatMap { workspace in
            let children = store.isWorkspaceExpanded(workspace.id)
                ? liveTabs(for: workspace.id).map { SidebarTreeSelection.tab(workspaceId: workspace.id, tabId: $0.id) }
                : []
            return [SidebarTreeSelection.workspace(workspace.id)] + children
        }
    }

    private var selectionSyncToken: String {
        let workspaceIds = store.workspaces.map(\.id).joined(separator: ",")
        let tabIds = store.tabs.map(\.id).joined(separator: ",")
        let expandedIds = store.expandedWorkspaceIds.sorted().joined(separator: ",")
        return [
            store.activeWorkspaceId ?? "",
            store.activeTabId ?? "",
            workspaceIds,
            tabIds,
            expandedIds,
            store.sidebarFocused ? "1" : "0"
        ].joined(separator: "|")
    }

    private func liveTabs(for workspaceId: String) -> [AppTab] {
        let ordered = store.orderedTabs(for: workspaceId)
        return ordered.isEmpty ? store.workspaceTabs(for: workspaceId) : ordered
    }

    private func scheduleSelectionSync() {
        DispatchQueue.main.async {
            syncSelectionIfNeeded()
        }
    }

    private func syncSelectionIfNeeded() {
        let hasValidSelection = selectedRow.map { visibleRows.contains($0) } ?? false
        if store.sidebarFocused, hasValidSelection {
            return
        }

        if let workspaceId = store.activeWorkspaceId {
            let activeTabSelection = store.activeTabId.map {
                SidebarTreeSelection.tab(workspaceId: workspaceId, tabId: $0)
            }
            if let activeTabSelection, visibleRows.contains(activeTabSelection) {
                selectedRow = activeTabSelection
                return
            }
            let workspaceSelection = SidebarTreeSelection.workspace(workspaceId)
            if visibleRows.contains(workspaceSelection) {
                selectedRow = workspaceSelection
                return
            }
        } else if hasValidSelection {
            return
        }

        selectedRow = visibleRows.first
    }

    private func select(_ row: SidebarTreeSelection) {
        selectedRow = row
        switch row {
        case .workspace(let workspaceId):
            store.setActiveWorkspace(workspaceId)
        case .tab(let workspaceId, let tabId):
            store.setActiveWorkspace(workspaceId)
            store.setActiveTab(tabId)
        }
    }

    private func activate(_ row: SidebarTreeSelection) {
        selectedRow = row
        switch row {
        case .workspace(let workspaceId):
            store.openWorkspaceSession(workspaceId, restoringSavedSetup: false)
        case .tab(let workspaceId, let tabId):
            store.openWorkspaceSession(workspaceId)
            store.setActiveTab(tabId)
        }
    }

    private func moveSelection(by delta: Int) {
        guard !visibleRows.isEmpty else { return }
        guard let selectedRow,
              let currentIndex = visibleRows.firstIndex(of: selectedRow) else {
            let fallbackIndex = delta >= 0 ? visibleRows.startIndex : visibleRows.index(before: visibleRows.endIndex)
            select(visibleRows[fallbackIndex])
            return
        }

        let nextIndex = max(visibleRows.startIndex, min(visibleRows.endIndex - 1, currentIndex + delta))
        guard nextIndex != currentIndex else { return }
        select(visibleRows[nextIndex])
    }

    private func collapseSelectedRow() {
        guard let selectedRow else { return }

        switch selectedRow {
        case .tab(let workspaceId, _):
            select(.workspace(workspaceId))
        case .workspace(let workspaceId):
            if store.isWorkspaceExpanded(workspaceId) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    store.collapseWorkspace(workspaceId)
                }
            }
        }
    }

    private func expandSelectedRow() {
        guard let selectedRow else { return }

        switch selectedRow {
        case .workspace(let workspaceId):
            let tabs = liveTabs(for: workspaceId)
            guard !tabs.isEmpty else {
                activate(.workspace(workspaceId))
                return
            }
            if !store.isWorkspaceExpanded(workspaceId) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    store.expandWorkspace(workspaceId)
                }
            } else if let firstTab = tabs.first {
                select(.tab(workspaceId: workspaceId, tabId: firstTab.id))
            }
        case .tab:
            activateSelectedRow()
        }
    }

    private func activateSelectedRow() {
        guard let selectedRow else { return }
        activate(selectedRow)
    }
}

private struct SidebarHeader: View {
    @Environment(AppStore.self) private var store

    let onPickWorkspaceFolder: () -> Void
    let onToggleNewWindowMenu: () -> Void
    let onNewTabAction: (NewTabAction) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Spacer()

            HStack(spacing: 6) {
                SidebarHeaderIconButton(
                    systemImage: "rectangle.on.rectangle",
                    accessibilityLabel: "New Window",
                    action: onToggleNewWindowMenu
                )
                .backgroundPopover(
                    isPresented: Binding(
                        get: { store.showNewTabMenu },
                        set: { store.showNewTabMenu = $0 }
                    )
                ) {
                    NewTabMenu(onAction: onNewTabAction)
                }
                .disabled(store.activeWorkspaceId == nil)

                SidebarHeaderIconButton(
                    systemImage: "plus",
                    accessibilityLabel: "New Workspace",
                    action: onPickWorkspaceFolder
                )
            }
        }
        .padding(Layout.sidebarHeaderPadding)
    }
}

private struct SidebarHeaderIconButton: View {
    @Environment(\.theme) private var theme

    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isHovered ? theme.text : theme.textDim)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(accessibilityLabel)
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isHovered ? theme.accent.opacity(0.08) : theme.border.opacity(0.2))
        )
        .scaleEffect(isHovered ? 1.04 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }
}

private struct AllWorkspacesSidebarView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let selectedRow: SidebarTreeSelection?
    let onSelectWorkspace: (String, Bool) -> Void
    let onToggleWorkspaceExpansion: (String) -> Void
    let onSelectTab: (String, String, Bool) -> Void

    var body: some View {
        if store.workspaces.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "folder")
                    .font(.system(size: 48, weight: .thin))
                    .foregroundStyle(theme.textDim.opacity(0.5))
                Text("No workspaces yet")
                    .font(Fonts.primary(size: 16))
                    .foregroundStyle(theme.textMuted)
                Text("Tap the icon above to add one")
                    .font(Fonts.primary(size: 12))
                    .foregroundStyle(theme.textDim)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 16)
        } else {
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(store.workspaces) { workspace in
                        let liveTabs = {
                            let ordered = store.orderedTabs(for: workspace.id)
                            return ordered.isEmpty ? store.workspaceTabs(for: workspace.id) : ordered
                        }()
                        SidebarWorkspaceItem(
                            workspace: workspace,
                            isActive: store.activeWorkspaceId == workspace.id,
                            isSelected: selectedRow == .workspace(workspace.id),
                            isPathMissing: store.isWorkspacePathMissing(workspace.id),
                            isExpanded: store.isWorkspaceExpanded(workspace.id),
                            terminalCount: store.terminalCount(for: workspace.id),
                            hasUnread: store.hasUnread(workspaceId: workspace.id),
                            claudeTabActivities: Dictionary(
                                uniqueKeysWithValues: liveTabs.compactMap { tab in
                                    store.claudeActivity(for: tab.id).map { (tab.id, $0) }
                                }
                            ),
                            shellDetectedAIPaneKinds: Dictionary(
                                uniqueKeysWithValues: liveTabs.compactMap { tab in
                                    store.shellDetectedAIPaneKinds[tab.id].map { (tab.id, $0) }
                                }
                            ),
                            tabs: liveTabs,
                            selectedTabId: {
                                if case .tab(let workspaceId, let tabId) = selectedRow, workspaceId == workspace.id {
                                    return tabId
                                }
                                return nil
                            }(),
                            activeTabId: store.activeWorkspaceId == workspace.id ? store.activeTabId : nil,
                            canRemove: !workspace.isScratchSpace,
                            onSelect: { activate in
                                onSelectWorkspace(workspace.id, activate)
                            },
                            onToggleExpansion: {
                                onToggleWorkspaceExpansion(workspace.id)
                            },
                            onSelectTab: { tabId, activate in
                                onSelectTab(workspace.id, tabId, activate)
                            },
                            onRename: { store.promptRenameWorkspace(workspace.id) },
                            onReveal: { store.revealWorkspaceInFinder(workspace.id) },
                            onRelink: { store.promptRelinkWorkspace(workspace.id) },
                            onRemove: { store.removeWorkspace(workspace.id) }
                        )
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: .infinity)
        }
    }
}

private struct SidebarNowPlaying: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(ThemeManager.self) private var themeManager
    @Environment(SpotifyMonitor.self) private var spotifyMonitor

    @State private var isHovered = false
    @State private var isAnimatingPlayback = false

    private var playbackStateLabel: String {
        spotifyMonitor.status.isPlaying ? "Playing" : "Paused"
    }

    private var content: some View {
        HStack(spacing: 10) {
            AsyncImage(url: URL(string: spotifyMonitor.status.artworkURL ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                default:
                    Image(systemName: "music.note")
                        .font(.system(size: 20))
                        .foregroundStyle(theme.textDim)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(theme.border.opacity(0.3))
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "music.note")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.textMuted)
                        .scaleEffect(spotifyMonitor.status.isPlaying && isAnimatingPlayback ? 1.15 : 1.0)
                        .opacity(reduceMotion ? 1.0 : (spotifyMonitor.status.isPlaying && isAnimatingPlayback ? 0.55 : 1.0))
                    Text(spotifyMonitor.status.track)
                        .font(Fonts.primary(size: 13))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                }
                Text(spotifyMonitor.status.artist)
                    .font(Fonts.primary(size: 12))
                    .foregroundStyle(theme.textMuted)
                    .lineLimit(1)
                Text(spotifyMonitor.status.album)
                    .font(Fonts.primary(size: 11))
                    .foregroundStyle(theme.textDim)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(Layout.sidebarHeaderPadding)
    }

    var body: some View {
        if store.spotifyEnabled, spotifyMonitor.status.hasTrack {
            theme.border.opacity(0.7).frame(height: 1)

            Button(action: openSpotifyTUI) {
                content
                    .background(isHovered ? theme.border.opacity(0.15) : Color.clear)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .pointerCursor()
            .help("\(playbackStateLabel) on Spotify")
            .accessibilityLabel("\(playbackStateLabel): \(spotifyMonitor.status.track) by \(spotifyMonitor.status.artist)")
            .animation(
                reduceMotion || !spotifyMonitor.status.isPlaying
                    ? nil
                    : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                value: isAnimatingPlayback
            )
            .onAppear {
                isAnimatingPlayback = spotifyMonitor.status.isPlaying && !reduceMotion
            }
            .onChange(of: spotifyMonitor.status.isPlaying, initial: true) {
                isAnimatingPlayback = spotifyMonitor.status.isPlaying && !reduceMotion
            }
            .onChange(of: reduceMotion, initial: true) {
                isAnimatingPlayback = spotifyMonitor.status.isPlaying && !reduceMotion
            }
        }
    }

    private func openSpotifyTUI() {
        let command = themeManager.activeTerminalTheme?.spotatuiLaunchCommand() ?? "spotatui"
        store.openOrFocusCommandTabForActiveWorkspace(command: command, label: "Spotify", maximizeColumn: true)
    }
}
