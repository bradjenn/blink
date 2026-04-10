import SwiftUI

struct WorkspaceLandingPage: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(ThemeManager.self) private var themeManager

    let workspace: Workspace

    @State private var selectedIndex = 0
    @State private var keyMonitor: Any?
    @State private var hoveredActionId: String?

    private let actionColumnCount = 3

    private var isPathMissing: Bool {
        store.isWorkspacePathMissing(workspace.id)
    }

    private var isKeyboardFocused: Bool {
        store.workspaceLandingFocused
            && store.activeWorkspaceId == workspace.id
            && store.activeView == .workspaces
            && !store.showWorkspaceSwitcher
            && !store.showWorkspaceOnboarding
            && !store.showThemePicker
            && !store.showAISessionPicker
            && !store.showCommandPalette
            && store.workspacePrompt == nil
    }

    private var subtitle: String {
        if workspace.isScratchSpace {
            return "Start a shell, AI session, or browser workspace."
        }
        if isPathMissing {
            return "This workspace folder could not be found. Relink it or remove the workspace."
        }
        return "Open your first window to start working in \(workspace.displayPath)."
    }

    private var primaryActions: [WorkspaceLandingAction] {
        [
            WorkspaceLandingAction(
                id: "terminal",
                title: "New Terminal",
                subtitle: "Open a shell in this workspace",
                systemImage: "terminal",
                action: { _ = store.openTab(workspaceId: workspace.id) }
            ),
            WorkspaceLandingAction(
                id: "ai-session",
                title: "AI Session",
                subtitle: "Open Claude Code, Codex, or OpenCode",
                systemImage: "sparkles.rectangle.stack",
                action: {
                    if store.activeWorkspaceId != workspace.id {
                        store.openWorkspaceSession(workspace.id)
                    }
                    store.presentAISessionPicker()
                }
            ),
            WorkspaceLandingAction(
                id: "browser",
                title: workspace.isScratchSpace ? "Browser" : "Workspace Browser",
                subtitle: "Open an isolated browser pane",
                systemImage: "globe",
                action: {
                    _ = store.openBrowserTab(
                        workspaceId: workspace.id,
                        url: BrowserDefaults.homePageURLString,
                        preferredFocus: .addressBar
                    )
                }
            ),
        ]
    }

    private var secondaryActions: [WorkspaceLandingAction] {
        [
            WorkspaceLandingAction(
                id: "git",
                title: "Git",
                subtitle: "Open lazygit in this workspace",
                systemImage: "point.3.connected.trianglepath.dotted",
                action: {
                    _ = store.openOrFocusCommandTab(
                        workspaceId: workspace.id,
                        command: "lazygit",
                        label: "lazygit"
                    )
                }
            ),
            WorkspaceLandingAction(
                id: "neovim",
                title: "Neovim",
                subtitle: "Open the editor in a pane",
                systemImage: "square.and.pencil",
                action: {
                    _ = store.openOrFocusCommandTab(
                        workspaceId: workspace.id,
                        command: NvimLauncher.command(theme: themeManager.activeTerminalTheme),
                        label: "Neovim"
                    )
                }
            ),
            WorkspaceLandingAction(
                id: "files",
                title: "Files",
                subtitle: "Browse the working directory",
                systemImage: "folder",
                action: {
                    _ = store.openOrFocusCommandTab(
                        workspaceId: workspace.id,
                        command: YaziLauncher.command(theme: nil),
                        label: "Yazi"
                    )
                }
            ),
        ]
    }

    private var allActions: [WorkspaceLandingAction] {
        if isPathMissing {
            return missingWorkspaceActions
        }
        return primaryActions + secondaryActions
    }

    private var missingWorkspaceActions: [WorkspaceLandingAction] {
        [
            WorkspaceLandingAction(
                id: "relink",
                title: "Relink Folder",
                subtitle: "Choose the new folder location for this workspace",
                systemImage: "arrow.trianglehead.branch",
                action: { store.promptRelinkWorkspace(workspace.id) }
            ),
            WorkspaceLandingAction(
                id: "scratch",
                title: "Open Scratch Space",
                subtitle: "Keep working in a generic shell and browser workspace",
                systemImage: "terminal",
                action: { store.openScratchSpace() }
            ),
            WorkspaceLandingAction(
                id: "remove",
                title: "Remove Workspace",
                subtitle: "Delete this missing workspace entry from Blink",
                systemImage: "trash",
                action: { store.removeWorkspace(workspace.id) }
            ),
        ]
    }

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 10) {
                HStack(spacing: 14) {
                    WorkspaceFavicon(workspaceName: workspace.name, workspacePath: workspace.path, size: 56)

                    Text(workspace.name)
                        .font(Fonts.primary(size: 24, weight: .bold))
                        .foregroundStyle(theme.text)
                }

                Text(subtitle)
                    .font(Fonts.primary(size: 13))
                    .foregroundStyle(isPathMissing ? theme.yellow : theme.textDim)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 180), spacing: 12),
                    GridItem(.flexible(minimum: 180), spacing: 12),
                    GridItem(.flexible(minimum: 180), spacing: 12),
                ],
                spacing: 12
            ) {
                ForEach(Array(allActions.enumerated()), id: \.element.id) { index, action in
                    WorkspaceLandingActionCard(
                        action: action,
                        isSelected: isKeyboardFocused && index == selectedIndex,
                        isHovered: hoveredActionId == action.id,
                        onHoverChanged: { isHovered in
                            hoveredActionId = isHovered ? action.id : nil
                        },
                        onSelect: {
                            selectedIndex = index
                            action.action()
                        }
                    )
                }
            }
            .frame(maxWidth: 636)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .onAppear {
            selectedIndex = 0
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .onChange(of: workspace.id, initial: false) { _, _ in
            selectedIndex = 0
        }
        .onChange(of: allActions.map(\.id), initial: true) { _, _ in
            guard !allActions.isEmpty else {
                selectedIndex = 0
                return
            }
            selectedIndex = min(selectedIndex, allActions.count - 1)
        }
        .onChange(of: isKeyboardFocused, initial: false) { _, isFocused in
            guard isFocused, !allActions.isEmpty else { return }
            selectedIndex = min(selectedIndex, allActions.count - 1)
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isKeyboardFocused, !allActions.isEmpty else { return event }

            let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
            guard modifiers.isEmpty else { return event }

            switch event.keyCode {
            case 123: // Left arrow
                moveSelectionHorizontally(by: -1)
                return nil
            case 124: // Right arrow
                moveSelectionHorizontally(by: 1)
                return nil
            case 125: // Down arrow
                moveSelectionVertically(by: 1)
                return nil
            case 126: // Up arrow
                moveSelectionVertically(by: -1)
                return nil
            case 36: // Return
                activateSelectedAction()
                return nil
            case 53: // Escape
                store.focusSidebar()
                return nil
            default:
                break
            }

            switch event.charactersIgnoringModifiers?.lowercased() {
            case "h":
                moveSelectionHorizontally(by: -1)
                return nil
            case "j":
                moveSelectionVertically(by: 1)
                return nil
            case "k":
                moveSelectionVertically(by: -1)
                return nil
            case "l":
                moveSelectionHorizontally(by: 1)
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func moveSelectionHorizontally(by delta: Int) {
        guard allActions.indices.contains(selectedIndex) else { return }

        let rowStart = (selectedIndex / actionColumnCount) * actionColumnCount
        let rowEnd = min(rowStart + actionColumnCount - 1, allActions.count - 1)
        let candidate = selectedIndex + delta

        if candidate < rowStart {
            if store.sidebarVisible {
                store.focusSidebar()
            }
            return
        }

        guard candidate <= rowEnd else { return }
        selectedIndex = candidate
    }

    private func moveSelectionVertically(by delta: Int) {
        guard allActions.indices.contains(selectedIndex) else { return }
        let candidate = selectedIndex + (delta * actionColumnCount)
        guard candidate >= 0, candidate < allActions.count else { return }
        selectedIndex = candidate
    }

    private func activateSelectedAction() {
        guard allActions.indices.contains(selectedIndex) else { return }
        allActions[selectedIndex].action()
    }
}

private struct WorkspaceLandingAction: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void
}

private struct WorkspaceLandingActionCard: View {
    @Environment(\.theme) private var theme

    let action: WorkspaceLandingAction
    let isSelected: Bool
    let isHovered: Bool
    let onHoverChanged: (Bool) -> Void
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(theme.accent)

                VStack(alignment: .leading, spacing: 4) {
                    Text(action.title)
                        .font(Fonts.primary(size: 14, weight: .medium))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)

                    Text(action.subtitle)
                        .font(Fonts.primary(size: 11))
                        .foregroundStyle(theme.textDim)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 118, maxHeight: 118, alignment: .topLeading)
            .padding(16)
            .background(cardBackground)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(borderColor, lineWidth: isSelected ? 1.5 : 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover(perform: onHoverChanged)
        .pointerCursor()
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    private var cardBackground: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(theme.accent.opacity(0.12))
        }
        if isHovered {
            return AnyShapeStyle(theme.accent.opacity(0.08))
        }
        return AnyShapeStyle(Color.white.opacity(0.04))
    }

    private var borderColor: Color {
        if isSelected {
            return theme.accent.opacity(0.9)
        }
        if isHovered {
            return theme.accent.opacity(0.28)
        }
        return theme.border
    }
}

struct MissingWorkspaceBanner: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let workspace: Workspace

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.yellow)

            VStack(alignment: .leading, spacing: 2) {
                Text("Workspace folder missing")
                    .font(Fonts.primary(size: 13, weight: .bold))
                    .foregroundStyle(theme.text)

                Text(workspace.displayPath)
                    .font(Fonts.primary(size: 11))
                    .foregroundStyle(theme.textDim)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Button("Relink Folder") {
                store.promptRelinkWorkspace(workspace.id)
            }
            .buttonStyle(.plain)
            .font(Fonts.primary(size: 12, weight: .medium))
            .foregroundStyle(theme.bg)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Capsule(style: .continuous).fill(theme.accent))
            .pointerCursor()

            Button("Remove") {
                store.removeWorkspace(workspace.id)
            }
            .buttonStyle(.plain)
            .font(Fonts.primary(size: 12, weight: .medium))
            .foregroundStyle(theme.textMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Capsule(style: .continuous).fill(theme.border.opacity(0.24)))
            .pointerCursor()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.bg.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(theme.yellow.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 14, y: 8)
    }
}
