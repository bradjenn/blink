import SwiftUI

struct StatusLine: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

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

            // Center: project name
            if let project = activeProject {
                Text(project.name)
                    .font(Fonts.primary(size: 12))
                    .foregroundStyle(theme.textMuted)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
            } else {
                Spacer()
            }

            // Right: git placeholder + terminal count
            if store.activeProjectId != nil {
                HStack(spacing: 12) {
                    // Git status placeholder
                    HStack(spacing: 6) {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.textMuted)
                        Text("main")
                            .font(Fonts.primary(size: 12))
                            .foregroundStyle(theme.textMuted)
                        Text("+2")
                            .font(Fonts.primary(size: 12))
                            .foregroundStyle(theme.green)
                        Text("~1")
                            .font(Fonts.primary(size: 12))
                            .foregroundStyle(theme.yellow)
                        Text("-1")
                            .font(Fonts.primary(size: 12))
                            .foregroundStyle(theme.danger)
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
        .background(theme.bg)
        .overlay(alignment: .top) {
            theme.border.frame(height: 1)
        }
        .font(Fonts.primary(size: 12))
    }
}
