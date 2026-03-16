import SwiftUI

struct StatusLine: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(GitStatusMonitor.self) private var gitMonitor

    private var activeProject: Project? {
        store.projects.first { $0.id == store.activeProjectId }
    }

    private var terminalCount: Int {
        guard let id = store.activeProjectId else { return 0 }
        return store.terminalCount(for: id)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left: mode indicator (placeholder — always terminal mode in M1)
            HStack(spacing: 8) {
                // Mode badge would go here in M2
            }
            .frame(minWidth: 0)

            // Center: project name (left-aligned within flex space)
            if let project = activeProject {
                Text(project.name)
                    .font(Fonts.primary(size: 12).leading(.tight))
                    .foregroundStyle(theme.textMuted)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 8)
                    .padding(.trailing, 16)
            } else {
                Spacer()
            }

            // Right: git status + terminal count
            if store.activeProjectId != nil {
                HStack(spacing: 12) {
                    if !gitMonitor.status.branch.isEmpty {
                        GitStatusBadge(status: gitMonitor.status)
                            .onTapGesture { openLazygit() }
                            .pointerCursor()
                    }

                    if terminalCount > 0 {
                        Text("\(terminalCount) term\(terminalCount != 1 ? "s" : "")")
                            .font(Fonts.primary(size: 12))
                            .foregroundStyle(theme.textMuted)
                    }
                }
            }
        }
        .padding(.horizontal, Layout.statusLinePaddingH)
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
        guard let project = activeProject else { return }
        if let existing = store.projectTabs(for: project.id).first(where: { $0.command == "lazygit" }) {
            store.setActiveTab(existing.id)
        } else {
            store.openTab(projectId: project.id, command: "lazygit", label: "lazygit")
        }
    }
}

struct GitStatusBadge: View {
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
