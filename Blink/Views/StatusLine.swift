import SwiftUI

struct FooterBar: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(GitStatusMonitor.self) private var gitMonitor

    let onToggleSidebar: () -> Void
    let onShowSettings: () -> Void

    private var activeProject: Project? {
        store.projects.first { $0.id == store.activeProjectId }
    }

    private var activeProjectTabs: [AppTab] {
        guard let id = store.activeProjectId else { return [] }
        return store.projectTabs(for: id)
    }

    private var isSettingsActive: Bool {
        store.activeView == .settings
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                FooterIconButton(
                    systemImage: "sidebar.left",
                    accessibilityLabel: "Toggle Sidebar",
                    action: onToggleSidebar
                )

                FooterIconButton(
                    systemImage: "gearshape",
                    isActive: isSettingsActive,
                    accessibilityLabel: "Settings",
                    action: onShowSettings
                )
            }

            HStack(spacing: 20) {
                if let project = activeProject {
                    FooterProjectLabel(name: project.path)
                }

                if !gitMonitor.status.branch.isEmpty {
                    Button(action: openLazygit) {
                        GitStatusLabel(status: gitMonitor.status)
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                }
            }

            Spacer(minLength: 8)

            if !activeProjectTabs.isEmpty {
                WindowDots(tabs: activeProjectTabs, activeTabId: store.activeTabId)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .font(Fonts.primary(size: 12))
        .onChange(of: store.activeProjectId, initial: true) {
            if let project = activeProject {
                gitMonitor.startMonitoring(path: project.path)
            } else {
                gitMonitor.stopMonitoring()
            }
        }
    }

    private func openLazygit() {
        store.openOrFocusCommandTabForActiveProject(command: "lazygit", label: "lazygit")
    }
}

private struct FooterIconButton: View {
    @Environment(\.theme) private var theme

    let systemImage: String
    let isActive: Bool
    let accessibilityLabel: String
    let action: () -> Void

    @State private var isHovered = false

    init(
        systemImage: String,
        isActive: Bool = false,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.isActive = isActive
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isActive || isHovered ? theme.text : theme.textMuted)
                .frame(width: 28, height: 22)
                .background(buttonBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .pointerCursor()
        .accessibilityLabel(accessibilityLabel)
    }

    private var buttonBackground: some ShapeStyle {
        if isActive {
            AnyShapeStyle(theme.accent.opacity(0.14))
        } else if isHovered {
            AnyShapeStyle(theme.border.opacity(0.3))
        } else {
            AnyShapeStyle(theme.border.opacity(0.16))
        }
    }
}

private struct FooterProjectLabel: View {
    @Environment(\.theme) private var theme

    let name: String

    private var displayPath: String {
        (name as NSString).abbreviatingWithTildeInPath
    }

    var body: some View {
        Text(displayPath)
            .font(Fonts.primary(size: 12))
            .foregroundStyle(theme.textMuted)
            .lineLimit(1)
    }
}

private struct WindowDots: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let tabs: [AppTab]
    let activeTabId: String?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tabs) { tab in
                Button(action: { store.setActiveTab(tab.id) }) {
                    Capsule()
                        .fill(tab.id == activeTabId ? theme.accent : theme.textMuted.opacity(0.28))
                        .frame(width: tab.id == activeTabId ? 18 : 6, height: 6)
                        .animation(.easeInOut(duration: 0.16), value: activeTabId)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.label)
                .accessibilityValue(tab.id == activeTabId ? "Current window" : "Window")
            }
        }
    }
}

private struct GitStatusLabel: View {
    @Environment(\.theme) private var theme

    let status: GitStatus

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 10))
                .foregroundStyle(isHovered ? theme.text : theme.textMuted)

            Text(status.branch)
                .font(Fonts.primary(size: 12))
                .foregroundStyle(isHovered ? theme.text : theme.textMuted)

            if status.added > 0 {
                Text("+\(status.added)")
                    .font(Fonts.primary(size: 12))
                    .foregroundStyle(theme.green)
            }

            if status.modified > 0 {
                Text("~\(status.modified)")
                    .font(Fonts.primary(size: 12))
                    .foregroundStyle(theme.yellow)
            }

            if status.deleted > 0 {
                Text("-\(status.deleted)")
                    .font(Fonts.primary(size: 12))
                    .foregroundStyle(theme.danger)
            }
        }
        .onHover { isHovered = $0 }
    }
}
