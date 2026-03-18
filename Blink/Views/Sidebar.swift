import SwiftUI

/// Project list — the middle section of the sidebar column.
/// Header/footer are handled by Shell's top bar and footer rows.
struct SidebarView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    @State private var isAddHovered = false
    @State private var isNewWindowHovered = false
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("PROJECTS")
                    .font(Fonts.primary(size: 11, weight: .medium).leading(.tight))
                    .tracking(0.55)
                    .textCase(.uppercase)
                    .foregroundStyle(theme.textDim)

                Spacer()

                HStack(spacing: 6) {
                    Button(action: toggleNewWindowMenu) {
                        Image(systemName: "rectangle.on.rectangle")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(isNewWindowHovered ? theme.text : theme.textDim)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("New Window")
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(isNewWindowHovered ? theme.accent.opacity(0.08) : theme.border.opacity(0.2))
                    )
                    .scaleEffect(isNewWindowHovered ? 1.04 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: isNewWindowHovered)
                    .onHover { hovering in
                        isNewWindowHovered = hovering
                        if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                    }
                    .backgroundPopover(
                        isPresented: Binding(
                            get: { store.showNewTabMenu },
                            set: { store.showNewTabMenu = $0 }
                        )
                    ) {
                        NewTabMenu(onAction: handleNewWindowAction)
                    }
                    .disabled(store.activeProjectId == nil)

                    Button(action: pickProjectFolder) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(isAddHovered ? theme.text : theme.textDim)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Add Project")
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(isAddHovered ? theme.accent.opacity(0.08) : theme.border.opacity(0.2))
                    )
                    .scaleEffect(isAddHovered ? 1.04 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: isAddHovered)
                    .onHover { hovering in
                        isAddHovered = hovering
                        if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                    }
                }
            }
            .padding(Layout.sidebarHeaderPadding)

            theme.border.opacity(0.7).frame(height: 1)

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
                    LazyVStack(spacing: 0) {
                        ForEach(store.projects) { project in
                            SidebarProjectItem(
                                project: project,
                                isActive: store.activeProjectId == project.id,
                                terminalCount: store.terminalCount(for: project.id),
                                hasUnread: store.hasUnread(projectId: project.id),
                                onSelect: { store.openProjectSession(project.id) },
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
        .background(theme.accent.opacity(store.sidebarFocused ? 0.025 : 0))
        .animation(.easeInOut(duration: 0.15), value: store.sidebarFocused)
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
    }

    private func pickProjectFolder() {
        store.pickProjectFolder()
    }

    private func toggleNewWindowMenu() {
        store.showNewTabMenu.toggle()
    }

    private func handleNewWindowAction(_ action: NewTabAction) {
        store.showNewTabMenu = false
        guard let projectId = store.activeProjectId else { return }

        switch action {
        case .terminal:
            store.openTab(projectId: projectId)
        case .claude:
            store.openOrFocusCommandTab(projectId: projectId, command: "claude", label: "Claude Code")
        case .claudeYolo:
            store.openOrFocusCommandTab(projectId: projectId, command: "claude --dangerously-skip-permissions", label: "Claude Code")
        case .codex:
            store.openOrFocusCommandTab(projectId: projectId, command: "codex", label: "Codex")
        case .openCode:
            store.openOrFocusCommandTab(projectId: projectId, command: "opencode", label: "Open Code")
        case .lazygit:
            store.openOrFocusCommandTab(projectId: projectId, command: "lazygit", label: "lazygit")
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard store.sidebarFocused else { return event }

            switch event.charactersIgnoringModifiers {
            case "j":
                store.selectNextProject()
                return nil
            case "k":
                store.selectPreviousProject()
                return nil
            case _ where event.keyCode == 53: // Escape
                store.focusTerminal()
                return nil
            case _ where event.keyCode == 36: // Return
                if let projectId = store.activeProjectId {
                    store.openProjectSession(projectId)
                }
                store.focusTerminal()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
}
