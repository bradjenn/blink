import SwiftUI

/// Project list — the middle section of the sidebar column.
/// Header/footer are handled by Shell's top bar and footer rows.
struct SidebarView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    @State private var isAddHovered = false
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("PROJECTS")
                    .font(Fonts.primary(size: 11, weight: .medium).leading(.tight))
                    .tracking(0.55)
                    .textCase(.uppercase)
                    .foregroundStyle(theme.textDim)

                Spacer()

                Button(action: { pickProjectFolder() }) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(isAddHovered ? theme.text : theme.textDim)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Add Project")
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isAddHovered ? theme.accent.opacity(0.1) : theme.border.opacity(0.3))
                )
                .scaleEffect(isAddHovered ? 1.08 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isAddHovered)
                .onHover { hovering in
                    isAddHovered = hovering
                    if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                }
            }
            .padding(Layout.sidebarHeaderPadding)

            // Project list
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
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: .infinity)
            }
        }
        .background(theme.accent.opacity(store.sidebarFocused ? 0.02 : 0))
        .animation(.easeInOut(duration: 0.15), value: store.sidebarFocused)
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
    }

    private func pickProjectFolder() {
        store.pickProjectFolder()
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
