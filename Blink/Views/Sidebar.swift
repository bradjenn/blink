import SwiftUI

struct SidebarView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    @State private var isAddHovered = false
    @State private var isSettingsHovered = false

    var body: some View {
        VStack(spacing: 0) {
            // Header: "PROJECTS" + add button
            HStack {
                Text("PROJECTS")
                    .font(Fonts.primary(size: 11, weight: .medium).leading(.tight))
                    .tracking(0.55) // Tailwind tracking-wider = 0.05em * 11pt
                    .textCase(.uppercase)
                    .foregroundStyle(theme.textDim)

                Spacer()

                Button(action: { /* non-functional in M1 */ }) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(isAddHovered ? theme.text : theme.textMuted)
                }
                .buttonStyle(.plain)
                .onHover { isAddHovered = $0 }
            }
            .padding(Layout.sidebarHeaderPadding)

            // Project list or empty state
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
                                onSelect: { store.setActiveProject(project.id) },
                                onRemove: { store.removeProject(project.id) }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: .infinity)
            }

            // Footer: settings button
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
        .frame(maxHeight: .infinity)
        .background(
            store.hasWallpaper
                ? AnyShapeStyle(theme.bg2.opacity(store.backgroundOpacity))
                : AnyShapeStyle(theme.bg2)
        )
    }
}
