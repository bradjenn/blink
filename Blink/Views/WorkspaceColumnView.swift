import SwiftUI
import GhosttyKit

struct WorkspaceColumnView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let column: Column
    let workspace: Workspace
    let activeTabId: String?
    let ghosttyApp: GhosttyApp
    let surfaceManager: SurfaceManager
    let browserManager: BrowserManager

    private var columnTabs: [AppTab] {
        column.tabIds.compactMap { store.tabsById[$0] }
    }

    var body: some View {
        @Bindable var browserManager = browserManager

        VStack(spacing: Layout.workspaceColumnSpacing) {
            ForEach(columnTabs) { tab in
                let isFocused = activeTabId == tab.id && !store.sidebarFocused
                let workspaceDownloads = browserManager.downloads
                    .filter { $0.workspaceId == workspace.id }
                    .sorted { $0.updatedAt > $1.updatedAt }

                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.clear)

                    switch tab.kind {
                    case .terminal:
                        if tab.isManagedCommand && store.isManagedCommandStopped(tab.id) {
                            StoppedCommandPaneView(tab: tab)
                        } else {
                            TerminalView(
                                tabId: tab.id,
                                paneId: tab.workspaceSetupPaneId ?? tab.id,
                                ghosttyApp: ghosttyApp,
                                surfaceManager: surfaceManager,
                                workspaceId: workspace.id,
                                workspaceName: workspace.name,
                                workingDirectory: store.resolvedWorkingDirectory(for: tab, workspace: workspace),
                                isFocused: isFocused,
                                command: store.terminalLaunchCommand(for: tab, workspace: workspace)
                            )
                        }
                    case .browser:
                        BrowserView(
                            tab: tab,
                            workspace: workspace,
                            browserManager: browserManager,
                            workspaceDownloads: workspaceDownloads,
                            isFocused: isFocused
                        )
                    case .chat:
                        VStack(spacing: 8) {
                            Text("This pane type is no longer supported.")
                                .font(Fonts.primary(size: 13))
                                .foregroundStyle(theme.text)

                            Text("Open a terminal, AI session, or browser pane instead.")
                                .font(Fonts.primary(size: 12))
                                .foregroundStyle(theme.textDim)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isFocused ? theme.accent.opacity(0.85) : theme.border, lineWidth: 1)
                )
            }
        }
        .animation(.easeInOut(duration: 0.18), value: activeTabId)
    }
}

struct StoppedCommandPaneView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let tab: AppTab

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "stop.circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.danger)

                Text("Command stopped")
                    .font(Fonts.primary(size: 13, weight: .medium))
                    .foregroundStyle(theme.text)
            }

            if let command = tab.command, !command.isEmpty {
                Text(command)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.textDim)
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: {
                store.restartManagedCommandTab(tab.id, focusAfterLaunch: true)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Restart")
                        .font(Fonts.primary(size: 12, weight: .medium))
                }
                .foregroundStyle(theme.bg)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(theme.accent)
                )
            }
            .buttonStyle(.plain)
            .pointerCursor()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(theme.bg.opacity(0.18))
        )
    }
}
