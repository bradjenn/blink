import SwiftUI

struct SidebarView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    @State private var isAddHovered = false
    @State private var isSettingsHovered = false

    var body: some View {
        Group {
            if store.sidebarVisible {
                expandedSidebar
            } else {
                collapsedSidebar
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Expanded sidebar (340pt)

    private var expandedSidebar: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("PROJECTS")
                    .font(Fonts.primary(size: 11, weight: .medium).leading(.tight))
                    .tracking(0.55)
                    .textCase(.uppercase)
                    .foregroundStyle(theme.textDim)

                Spacer()

                Button(action: { /* non-functional */ }) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isAddHovered ? theme.text : theme.textMuted)
                }
                .buttonStyle(.plain)
                .onHover { isAddHovered = $0 }
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
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(store.projects) { project in
                            SidebarProjectItem(
                                project: project,
                                isActive: store.activeProjectId == project.id,
                                terminalCount: store.terminalCount(for: project.id),
                                hasUnread: store.hasUnread(projectId: project.id),
                                onSelect: { store.setActiveProject(project.id) },
                                onRemove: { store.removeProject(project.id) }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: .infinity)
            }

            // Footer
            VStack(spacing: 0) {
                theme.border.frame(height: 1)
                Button(action: { store.setActiveView(.settings) }) {
                    HStack(spacing: 10) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14, weight: .light))
                        Text("Settings")
                            .font(Fonts.primary(size: 12.5).leading(.tight))
                    }
                    .foregroundStyle(isSettingsHovered ? theme.text : theme.textDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: Layout.sidebarSettingsHeight)
                    .padding(.horizontal, 16)
                }
                .buttonStyle(.plain)
                .onHover { isSettingsHovered = $0 }
            }
        }
    }

    // MARK: - Collapsed sidebar (50pt)

    private var collapsedSidebar: some View {
        VStack(spacing: 0) {
            // Add button
            Button(action: { /* non-functional */ }) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isAddHovered ? theme.text : theme.textDim)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
            }
            .buttonStyle(.plain)
            .onHover { isAddHovered = $0 }

            // Project avatars
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 6) {
                    ForEach(store.projects) { project in
                        CollapsedProjectIcon(
                            project: project,
                            isActive: store.activeProjectId == project.id,
                            hasTerminals: store.terminalCount(for: project.id) > 0,
                            onSelect: { store.setActiveProject(project.id) }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: .infinity)

            // Settings icon
            VStack(spacing: 0) {
                theme.border.frame(height: 1)
                Button(action: { store.setActiveView(.settings) }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .light))
                        .foregroundStyle(isSettingsHovered ? theme.text : theme.textDim)
                        .frame(maxWidth: .infinity)
                        .frame(height: Layout.sidebarSettingsHeight)
                }
                .buttonStyle(.plain)
                .onHover { isSettingsHovered = $0 }
            }
        }
    }
}

/// Compact project avatar for collapsed sidebar.
struct CollapsedProjectIcon: View {
    @Environment(\.theme) private var theme

    let project: Project
    let isActive: Bool
    let hasTerminals: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .bottomTrailing) {
                ProjectFavicon(projectName: project.name, size: 30)
                    .overlay(
                        Circle()
                            .stroke(isActive ? theme.accent.opacity(0.5) : Color.clear, lineWidth: 2)
                    )

                if hasTerminals {
                    Circle()
                        .fill(theme.accent)
                        .frame(width: 6, height: 6)
                        .offset(x: 1, y: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .onHover { isHovered = $0 }
        .overlay(alignment: .trailing) {
            if isHovered {
                Text(project.name)
                    .font(Fonts.primary(size: 12).leading(.tight))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                    .fixedSize()
                    .offset(x: 50)
                    .allowsHitTesting(false)
            }
        }
    }
}
