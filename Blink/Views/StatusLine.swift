import SwiftUI

struct FooterBar: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(GitStatusMonitor.self) private var gitMonitor
    @Environment(UpdateChecker.self) private var updateChecker

    let onToggleSidebar: () -> Void
    let onShowSettings: () -> Void

    private var activeWorkspace: Workspace? {
        store.workspaces.first { $0.id == store.activeWorkspaceId }
    }

    private var activeWorkspaceTabs: [AppTab] {
        guard let id = store.activeWorkspaceId else { return [] }
        return store.workspaceTabs(for: id)
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
                if let workspace = activeWorkspace {
                    FooterWorkspaceLabel(
                        name: workspace.isScratchSpace ? workspace.name : workspace.path,
                        isMissing: store.isWorkspacePathMissing(workspace.id)
                    )
                }

                if !gitMonitor.status.branch.isEmpty {
                    Button(action: openLazygit) {
                        GitStatusLabel(status: gitMonitor.status)
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                }
            }

            if let release = updateChecker.availableRelease {
                UpdateBadge(release: release, updateChecker: updateChecker)
            }

            Spacer(minLength: 8)

            SpotifyNowPlaying()
                .padding(.trailing, 30)

            if let workspaceId = store.activeWorkspaceId {
                let cols = store.workspaceColumns(for: workspaceId)
                if !cols.isEmpty {
                    WindowDots(columns: cols, activeTabId: store.activeTabId)
                } else if !activeWorkspaceTabs.isEmpty {
                    // Fallback before columns are initialized
                    WindowDots(
                        columns: activeWorkspaceTabs.map { Column(id: $0.id, tabIds: [$0.id]) },
                        activeTabId: store.activeTabId
                    )
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .font(Fonts.primary(size: 12))
        .onChange(of: store.activeWorkspaceId, initial: true) {
            if let workspace = activeWorkspace,
               !workspace.isScratchSpace,
               !store.isWorkspacePathMissing(workspace.id) {
                gitMonitor.startMonitoring(path: workspace.path)
            } else {
                gitMonitor.stopMonitoring()
            }
        }
    }

    private func openLazygit() {
        store.openOrFocusCommandTabForActiveWorkspace(command: "lazygit", label: "lazygit")
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

private struct FooterWorkspaceLabel: View {
    @Environment(\.theme) private var theme

    let name: String
    let isMissing: Bool

    private var displayPath: String {
        (name as NSString).abbreviatingWithTildeInPath
    }

    var body: some View {
        HStack(spacing: 6) {
            if isMissing {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.yellow)
            }

            Text(isMissing ? "Missing folder" : displayPath)
                .font(Fonts.primary(size: 12))
                .foregroundStyle(isMissing ? theme.yellow : theme.textMuted)
                .lineLimit(1)
        }
    }
}

private struct WindowDots: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let columns: [Column]
    let activeTabId: String?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(columns) { col in
                let isActive = col.tabIds.contains(activeTabId ?? "")
                Button(action: {
                    if let tabId = store.columnFocusedTab[col.id] ?? col.tabIds.first {
                        store.setActiveTab(tabId)
                    }
                }) {
                    HStack(spacing: 2) {
                        ForEach(col.tabIds, id: \.self) { tabId in
                            Capsule()
                                .fill(tabId == activeTabId ? theme.accent : isActive ? theme.accent.opacity(0.4) : theme.textMuted.opacity(0.28))
                                .frame(width: tabId == activeTabId ? 14 : 6, height: 6)
                        }
                    }
                    .animation(.easeInOut(duration: 0.16), value: activeTabId)
                }
                .buttonStyle(.plain)
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

private struct UpdateBadge: View {
    @Environment(\.theme) private var theme

    let release: AppRelease
    let updateChecker: UpdateChecker

    @State private var isHovered = false

    private var version: String {
        String(release.tagName.trimmingPrefix("v"))
    }

    var body: some View {
        Button(action: { updateChecker.openReleasePage() }) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 10))
                Text(version)
                    .font(Fonts.primary(size: 12))
            }
            .foregroundStyle(isHovered ? theme.accent : theme.textMuted)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .pointerCursor()
        .help("Update available — click to view release")
    }
}

private struct SpotifyNowPlaying: View {
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

    var body: some View {
        if store.spotifyEnabled, spotifyMonitor.status.hasTrack {
            Button(action: openSpotifyTUI) {
                HStack(spacing: 5) {
                    Image(systemName: "music.note")
                        .font(.system(size: 10))
                        .scaleEffect(spotifyMonitor.status.isPlaying && isAnimatingPlayback ? 1.15 : 1.0)
                        .opacity(reduceMotion ? 1.0 : (spotifyMonitor.status.isPlaying && isAnimatingPlayback ? 0.55 : 1.0))
                    Text("\(spotifyMonitor.status.artist) — \(spotifyMonitor.status.track)")
                        .font(Fonts.primary(size: 12))
                        .lineLimit(1)
                }
                .foregroundStyle(isHovered ? theme.text : theme.textMuted)
                .frame(maxWidth: 200, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .pointerCursor()
            .help("\(playbackStateLabel) on Spotify")
            .accessibilityLabel("\(playbackStateLabel): \(spotifyMonitor.status.artist) — \(spotifyMonitor.status.track)")
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
        store.openOrFocusCommandTabForActiveWorkspace(command: command, label: "Spotify", maximizeColumn: true)
    }
}
