import SwiftUI

private enum SidebarTreeSelection: Hashable {
    case project(String)
    case tab(projectId: String, tabId: String)

    var projectId: String {
        switch self {
        case .project(let projectId):
            return projectId
        case .tab(let projectId, _):
            return projectId
        }
    }
}

/// Project list — the middle section of the sidebar column.
/// Header/footer are handled by Shell's top bar and footer rows.
struct SidebarView: View {
    @Environment(AppStore.self) private var store
    @Environment(ThemeManager.self) private var themeManager

    @State private var keyMonitor: Any?
    @State private var selectedRow: SidebarTreeSelection?

    var body: some View {
        VStack(spacing: 0) {
            SidebarHeader(
                onPickProjectFolder: { store.pickProjectFolder() },
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

            AllProjectsSidebarView(
                selectedRow: selectedRow,
                onSelectProject: { projectId, shouldActivate in
                    if shouldActivate {
                        activate(.project(projectId))
                    } else {
                        select(.project(projectId))
                    }
                },
                onToggleProjectExpansion: { projectId in
                    selectedRow = .project(projectId)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        store.toggleProjectExpansion(projectId)
                    }
                },
                onSelectTab: { projectId, tabId, shouldActivate in
                    if shouldActivate {
                        activate(.tab(projectId: projectId, tabId: tabId))
                    } else {
                        select(.tab(projectId: projectId, tabId: tabId))
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
        guard let projectId = store.activeProjectId else { return }

        switch action {
        case .terminal:
            store.openTab(projectId: projectId)
        case .browser:
            store.openBrowserTabForActiveProject()
        case .lazygit:
            store.openOrFocusCommandTab(projectId: projectId, command: "lazygit", label: "lazygit")
        case .yazi:
            let command = YaziLauncher.command(theme: themeManager.activeTerminalTheme)
            store.openOrFocusCommandTab(projectId: projectId, command: command, label: "Yazi")
        case .neovim:
            let command = NvimLauncher.command()
            store.openOrFocusCommandTab(projectId: projectId, command: command, label: "Neovim")
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
        store.projects.flatMap { project in
            let children = store.isProjectExpanded(project.id)
                ? liveTabs(for: project.id).map { SidebarTreeSelection.tab(projectId: project.id, tabId: $0.id) }
                : []
            return [SidebarTreeSelection.project(project.id)] + children
        }
    }

    private var selectionSyncToken: String {
        let projectIds = store.projects.map(\.id).joined(separator: ",")
        let tabIds = store.tabs.map(\.id).joined(separator: ",")
        let expandedIds = store.expandedProjectIds.sorted().joined(separator: ",")
        return [
            store.activeProjectId ?? "",
            store.activeTabId ?? "",
            projectIds,
            tabIds,
            expandedIds,
            store.sidebarFocused ? "1" : "0"
        ].joined(separator: "|")
    }

    private func liveTabs(for projectId: String) -> [AppTab] {
        let ordered = store.orderedTabs(for: projectId)
        return ordered.isEmpty ? store.projectTabs(for: projectId) : ordered
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

        if let projectId = store.activeProjectId {
            let activeTabSelection = store.activeTabId.map {
                SidebarTreeSelection.tab(projectId: projectId, tabId: $0)
            }
            if let activeTabSelection, visibleRows.contains(activeTabSelection) {
                selectedRow = activeTabSelection
                return
            }
            let projectSelection = SidebarTreeSelection.project(projectId)
            if visibleRows.contains(projectSelection) {
                selectedRow = projectSelection
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
        case .project(let projectId):
            store.setActiveProject(projectId)
        case .tab(let projectId, let tabId):
            store.setActiveProject(projectId)
            store.setActiveTab(tabId)
        }
    }

    private func activate(_ row: SidebarTreeSelection) {
        selectedRow = row
        switch row {
        case .project(let projectId):
            store.openProjectSession(projectId, restoringSavedSetup: false)
        case .tab(let projectId, let tabId):
            store.openProjectSession(projectId)
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
        case .tab(let projectId, _):
            select(.project(projectId))
        case .project(let projectId):
            if store.isProjectExpanded(projectId) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    store.collapseProject(projectId)
                }
            }
        }
    }

    private func expandSelectedRow() {
        guard let selectedRow else { return }

        switch selectedRow {
        case .project(let projectId):
            let tabs = liveTabs(for: projectId)
            guard !tabs.isEmpty else {
                activate(.project(projectId))
                return
            }
            if !store.isProjectExpanded(projectId) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    store.expandProject(projectId)
                }
            } else if let firstTab = tabs.first {
                select(.tab(projectId: projectId, tabId: firstTab.id))
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

    let onPickProjectFolder: () -> Void
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
                .disabled(store.activeProjectId == nil)

                SidebarHeaderIconButton(
                    systemImage: "plus",
                    accessibilityLabel: "Add Project",
                    action: onPickProjectFolder
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

private struct AllProjectsSidebarView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let selectedRow: SidebarTreeSelection?
    let onSelectProject: (String, Bool) -> Void
    let onToggleProjectExpansion: (String) -> Void
    let onSelectTab: (String, String, Bool) -> Void

    var body: some View {
        if store.projects.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "folder")
                    .font(.system(size: 48, weight: .thin))
                    .foregroundStyle(theme.textDim.opacity(0.5))
                Text("No projects yet")
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
                    ForEach(store.projects) { project in
                        let liveTabs = {
                            let ordered = store.orderedTabs(for: project.id)
                            return ordered.isEmpty ? store.projectTabs(for: project.id) : ordered
                        }()
                        SidebarProjectItem(
                            project: project,
                            isActive: store.activeProjectId == project.id,
                            isSelected: selectedRow == .project(project.id),
                            isExpanded: store.isProjectExpanded(project.id),
                            terminalCount: store.terminalCount(for: project.id),
                            hasUnread: store.hasUnread(projectId: project.id),
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
                                if case .tab(let projectId, let tabId) = selectedRow, projectId == project.id {
                                    return tabId
                                }
                                return nil
                            }(),
                            activeTabId: store.activeProjectId == project.id ? store.activeTabId : nil,
                            onSelect: { activate in
                                onSelectProject(project.id, activate)
                            },
                            onToggleExpansion: {
                                onToggleProjectExpansion(project.id)
                            },
                            onSelectTab: { tabId, activate in
                                onSelectTab(project.id, tabId, activate)
                            },
                            onRemove: { store.removeProject(project.id) }
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
        store.openOrFocusCommandTabForActiveProject(command: command, label: "Spotify", maximizeColumn: true)
    }
}
