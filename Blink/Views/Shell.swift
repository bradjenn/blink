import SwiftUI
import GhosttyKit

struct Shell: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let ghosttyApp: GhosttyApp
    let surfaceManager: SurfaceManager

    private var isSettingsActive: Bool {
        store.activeView == .settings
    }

    private var chromeBackground: AnyShapeStyle {
        store.hasWallpaper
            ? AnyShapeStyle(theme.bg.opacity(store.backgroundOpacity))
            : AnyShapeStyle(theme.bg)
    }

    private var sidebarAnimation: Animation {
        reduceMotion ? .linear(duration: 0.01) : .snappy(duration: 0.18, extraBounce: 0)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                workspaceArea

                if activeProject != nil {
                    theme.border.frame(height: 1)
                    footer
                }
            }
            .font(Fonts.primary(size: 13))
            .ignoresSafeArea(.container, edges: .top)

            if isSettingsActive {
                SettingsPage(ghosttyApp: ghosttyApp)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Rectangle().fill(chromeBackground))
                    .transition(.opacity)
                    .zIndex(1)
            }

            if store.showProjectSwitcher {
                StartScreenProjectPicker(
                    onDismiss: { store.dismissProjectSwitcher() },
                    onSelect: { projectId in
                        store.openProjectSession(projectId)
                    }
                )
                .transition(.opacity)
                .zIndex(1)
            }

            if store.showThemePicker {
                ThemePicker(
                    ghosttyApp: ghosttyApp,
                    onDismiss: { store.showThemePicker = false }
                )
                .zIndex(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            windowBackground
                .ignoresSafeArea()
        }
    }

    private var workspaceArea: some View {
        ZStack {
            if store.activeProjectId != nil {
                Rectangle()
                    .fill(chromeBackground)
            }

            if store.activeProjectId == nil {
                Rectangle()
                    .fill(chromeBackground)
                    .overlay {
                        StartScreen()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
            } else if let project = activeProject {
                HStack(alignment: .top, spacing: Layout.workspaceColumnSpacing) {
                    if store.sidebarVisible {
                        WorkspaceSidebarPanel()
                            .frame(width: Layout.sidebarWidth)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }

                    WorkspaceColumnsView(
                        project: project,
                        ghosttyApp: ghosttyApp,
                        surfaceManager: surfaceManager
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, Layout.workspacePaddingH)
                .padding(.top, Layout.workspacePaddingV)
                .padding(.bottom, 8)
                .animation(sidebarAnimation, value: store.sidebarVisible)
            } else {
                VStack(spacing: 12) {
                    Text("No workspace available")
                        .font(Fonts.primary(size: 16))
                        .foregroundStyle(theme.textDim)
                    Text("Select a project to open a workspace")
                        .font(Fonts.primary(size: 13))
                        .foregroundStyle(theme.textDim)
                }
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .clipped()
    }

    private var footer: some View {
        FooterBar(
            onToggleSidebar: toggleSidebar,
            onShowSettings: showSettings
        )
        .frame(height: Layout.statusLineHeight)
        .background(chromeBackground)
        .background(WindowDragRegion())
    }

    @ViewBuilder
    private var windowBackground: some View {
        Rectangle()
            .fill(chromeBackground)

        if let wallpaperId = store.backgroundImage {
            wallpaperImage(for: wallpaperId)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(1.1)
                .blur(radius: store.backgroundBlur)
                .clipped()
        }
    }

    private var activeProject: Project? {
        guard let activeProjectId = store.activeProjectId else { return nil }
        return store.projects.first(where: { $0.id == activeProjectId })
    }

    private func showSettings() {
        store.setActiveView(.settings)
    }

    private func toggleSidebar() {
        store.toggleSidebar()
    }

    private func wallpaperImage(for id: String) -> Image {
        if let preset = WallpaperPreset.find(id) {
            let parts = preset.filename.split(separator: ".")
            if parts.count == 2,
               let url = Bundle.main.url(forResource: String(parts[0]), withExtension: String(parts[1])),
               let nsImage = NSImage(contentsOf: url) {
                return Image(nsImage: nsImage)
            }
        } else if !id.hasPrefix("preset:"), let nsImage = NSImage(contentsOfFile: id) {
            return Image(nsImage: nsImage)
        }
        return Image(systemName: "photo")
    }
}

private struct WorkspaceSidebarPanel: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    var body: some View {
        SidebarView()
            .frame(maxHeight: .infinity)
            .background(panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            )
    }

    private var panelBackground: some ShapeStyle {
        AnyShapeStyle(Color.clear)
    }
}

private struct WorkspaceColumnsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let project: Project
    let ghosttyApp: GhosttyApp
    let surfaceManager: SurfaceManager

    @State private var layoutState = WorkspaceLayoutState()

    private var tabs: [AppTab] {
        store.projectTabs(for: project.id)
    }

    private var workspaceAnimation: Animation {
        reduceMotion ? .linear(duration: 0.01) : .easeInOut(duration: 0.18)
    }

    private var workspaceColumnTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.985, anchor: .trailing)),
            removal: .move(edge: .leading)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.985, anchor: .leading))
        )
    }

    var body: some View {
        GeometryReader { geometry in
            if tabs.isEmpty {
                VStack(spacing: 12) {
                    Text("No windows in this workspace")
                        .font(Fonts.primary(size: 16))
                        .foregroundStyle(theme.text)
                    Text("Use the sidebar controls to open a terminal or tool window")
                        .font(Fonts.primary(size: 13))
                        .foregroundStyle(theme.textDim)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                columnStrip(viewportWidth: geometry.size.width, viewportHeight: geometry.size.height)
                    .onChange(of: tabs.map(\.id), initial: true) { _, _ in
                        syncTabs(viewportWidth: geometry.size.width)
                        restoreViewport(viewportWidth: geometry.size.width)
                    }
                    .onChange(of: store.activeTabId, initial: false) {
                        alignActiveTab(viewportWidth: geometry.size.width, animated: !reduceMotion)
                    }
                    .onChange(of: geometry.size.width, initial: true) { _, _ in
                        handleViewportChange(viewportWidth: geometry.size.width)
                    }
                    .onKeyPress(characters: CharacterSet(charactersIn: "rf")) { keyPress in
                        guard keyPress.modifiers == .control else { return .ignored }
                        guard let tabId = store.activeTabId else { return .ignored }
                        switch keyPress.characters {
                        case "r":
                            let _ = layoutState.cyclePreset(for: tabId, projectId: project.id, viewportWidth: geometry.size.width)
                            alignActiveTab(viewportWidth: geometry.size.width, animated: true)
                            return .handled
                        case "f":
                            let _ = layoutState.toggleMaximize(for: tabId, projectId: project.id, viewportWidth: geometry.size.width)
                            alignActiveTab(viewportWidth: geometry.size.width, animated: true)
                            return .handled
                        default:
                            return .ignored
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private func columnStrip(viewportWidth: CGFloat, viewportHeight: CGFloat) -> some View {
        let layout = stripLayout(viewportWidth: viewportWidth)

        ZStack(alignment: .topLeading) {
            ForEach(tabs) { tab in
                if let frame = layout.frames[tab.id] {
                    WorkspaceColumnView(
                        tab: tab,
                        project: project,
                        isFocused: store.activeTabId == tab.id,
                        ghosttyApp: ghosttyApp,
                        surfaceManager: surfaceManager
                    )
                    .frame(width: frame.width)
                    .frame(height: viewportHeight)
                    .offset(x: frame.minX)
                    .zIndex(store.activeTabId == tab.id ? 1 : 0)
                    .transition(workspaceColumnTransition)
                }
            }
        }
        .frame(width: max(layout.contentWidth, viewportWidth), height: viewportHeight, alignment: .topLeading)
        .offset(x: -layout.viewportOffset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .clipped()
        .contentShape(Rectangle())
        .animation(workspaceAnimation, value: tabs.map(\.id))
        .animation(workspaceAnimation, value: store.activeTabId)
    }

    private func syncTabs(viewportWidth: CGFloat) {
        layoutState.sync(
            projectId: project.id,
            tabIds: tabs.map(\.id),
            defaultFraction: Layout.workspaceColumnDefaultFraction
        )
    }

    private func restoreViewport(viewportWidth: CGFloat) {
        if layoutState.isInitialized(projectId: project.id) || store.hasWorkspaceViewportOffset(for: project.id) {
            clampViewportOffset(viewportWidth: viewportWidth, animated: false)
            layoutState.markInitialized(projectId: project.id)
        } else {
            alignActiveTab(viewportWidth: viewportWidth, animated: false)
        }
    }

    private func handleViewportChange(viewportWidth: CGFloat) {
        if layoutState.isInitialized(projectId: project.id) {
            clampViewportOffset(viewportWidth: viewportWidth, animated: false)
        } else {
            restoreViewport(viewportWidth: viewportWidth)
        }
    }

    private func alignActiveTab(viewportWidth: CGFloat, animated: Bool) {
        let targetOffset = focusedViewportOffset(viewportWidth: viewportWidth)
        if animated {
            withAnimation(workspaceAnimation) {
                store.setWorkspaceViewportOffset(targetOffset, for: project.id)
            }
        } else {
            store.setWorkspaceViewportOffset(targetOffset, for: project.id)
        }

        layoutState.markInitialized(projectId: project.id)
    }

    private func clampViewportOffset(viewportWidth: CGFloat, animated: Bool) {
        let layout = stripLayout(viewportWidth: viewportWidth)
        let clampedOffset = clampedViewportOffset(
            store.workspaceViewportOffset(for: project.id),
            contentWidth: layout.contentWidth,
            viewportWidth: viewportWidth
        )

        guard clampedOffset != layout.viewportOffset else { return }

        if animated {
            withAnimation(workspaceAnimation) {
                store.setWorkspaceViewportOffset(clampedOffset, for: project.id)
            }
        } else {
            store.setWorkspaceViewportOffset(clampedOffset, for: project.id)
        }
    }

    private func stripLayout(viewportWidth: CGFloat) -> WorkspaceStripLayout {
        var frames: [String: CGRect] = [:]
        var leadingX: CGFloat = 0

        for tab in tabs {
            let width = columnWidth(for: tab.id, viewportWidth: viewportWidth)
            frames[tab.id] = CGRect(x: leadingX, y: 0, width: width, height: 0)
            leadingX += width + Layout.workspaceColumnSpacing
        }

        let contentWidth = max(0, leadingX - Layout.workspaceColumnSpacing)
        let viewportOffset = clampedViewportOffset(
            store.workspaceViewportOffset(for: project.id),
            contentWidth: contentWidth,
            viewportWidth: viewportWidth
        )

        return WorkspaceStripLayout(
            frames: frames,
            contentWidth: contentWidth,
            viewportOffset: viewportOffset
        )
    }

    private func columnWidth(for tabId: String, viewportWidth: CGFloat) -> CGFloat {
        let width = layoutState.width(
            for: tabId,
            projectId: project.id,
            viewportWidth: viewportWidth
        )
        return min(max(width, Layout.workspaceColumnMinWidth), Layout.workspaceColumnMaxWidth)
    }

    private func focusedViewportOffset(viewportWidth: CGFloat) -> CGFloat {
        guard let activeTabId = store.activeTabId else { return 0 }
        let layout = stripLayout(viewportWidth: viewportWidth)
        guard let frame = layout.frames[activeTabId] else { return 0 }

        // Center the active column in the viewport
        let centeredOffset = frame.minX - (viewportWidth - frame.width) / 2
        return clampedViewportOffset(
            centeredOffset,
            contentWidth: layout.contentWidth,
            viewportWidth: viewportWidth
        )
    }

    private func clampedViewportOffset(_ offset: CGFloat, contentWidth: CGFloat, viewportWidth: CGFloat) -> CGFloat {
        let maxOffset = max(0, contentWidth - viewportWidth)
        return min(max(offset, 0), maxOffset)
    }
}

private struct WorkspaceStripLayout {
    let frames: [String: CGRect]
    let contentWidth: CGFloat
    let viewportOffset: CGFloat
}

private struct WorkspaceColumnView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let tab: AppTab
    let project: Project
    let isFocused: Bool
    let ghosttyApp: GhosttyApp
    let surfaceManager: SurfaceManager

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(windowPanelBackground)

            // Keep SwiftUI masks and gesture overlays off the Metal-backed
            // terminal surface. Ghostty handles input directly, and applying
            // clip/opacity effects here can break faint text rendering.
            TerminalView(
                tabId: tab.id,
                ghosttyApp: ghosttyApp,
                surfaceManager: surfaceManager,
                workingDirectory: project.path,
                isFocused: isFocused,
                command: tab.command
            )
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(isFocused ? theme.accent.opacity(0.85) : theme.border, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.18), value: isFocused)
    }

    private var windowPanelBackground: some ShapeStyle {
        AnyShapeStyle(Color.clear)
    }
}
