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
    @State private var overviewMonitor: Any?
    @State private var currentViewportWidth: CGFloat = 0

    private var tabs: [AppTab] {
        store.projectTabs(for: project.id)
    }

    private var columns: [Column] {
        store.projectColumns(for: project.id)
    }

    private var workspaceAnimation: Animation {
        reduceMotion ? .linear(duration: 0.01) : .easeInOut(duration: 0.18)
    }

    private var overviewAnimation: Animation {
        reduceMotion ? .linear(duration: 0.01) : .easeInOut(duration: 0.25)
    }

    private func overviewScale(contentWidth: CGFloat, viewportWidth: CGFloat) -> CGFloat {
        guard store.isOverviewMode else { return 1.0 }
        let padded = viewportWidth - Layout.overviewPadding * 2
        return min(1.0, max(Layout.overviewMinScale, padded / max(contentWidth, 1)))
    }

    private var workspaceColumnTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.985, anchor: .trailing)),
            removal: .opacity
                .combined(with: .scale(scale: 0.96))
        )
    }

    var body: some View {
        GeometryReader { geometry in
            if columns.isEmpty {
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
                    .onChange(of: columns.map(\.id), initial: true) { _, _ in
                        syncColumns(viewportWidth: geometry.size.width)
                        restoreViewport(viewportWidth: geometry.size.width)
                    }
                    .onChange(of: store.activeTabId, initial: false) {
                        alignActiveTab(viewportWidth: geometry.size.width, animated: !reduceMotion)
                    }
                    .onChange(of: geometry.size.width, initial: true) { _, _ in
                        currentViewportWidth = geometry.size.width
                        handleViewportChange(viewportWidth: geometry.size.width)
                    }
                    .onKeyPress(characters: CharacterSet(charactersIn: "rf")) { keyPress in
                        guard keyPress.modifiers == .command else { return .ignored }
                        guard !store.isOverviewMode else { return .ignored }
                        guard let colId = store.activeColumn?.id else { return .ignored }
                        switch keyPress.characters {
                        case "r":
                            let _ = layoutState.cyclePreset(for: colId, projectId: project.id, viewportWidth: geometry.size.width)
                            alignActiveTab(viewportWidth: geometry.size.width, animated: true)
                            return .handled
                        case "f":
                            let _ = layoutState.toggleMaximize(for: colId, projectId: project.id, viewportWidth: geometry.size.width)
                            alignActiveTab(viewportWidth: geometry.size.width, animated: true)
                            return .handled
                        default:
                            return .ignored
                        }
                    }
                    .onChange(of: columns.count) {
                        if store.isOverviewMode {
                            let cols = store.projectColumns(for: project.id)
                            if cols.isEmpty {
                                store.exitOverview(selecting: nil)
                            } else if let highlightId = store.overviewHighlightedColumnId,
                                      !cols.contains(where: { $0.id == highlightId }) {
                                store.overviewHighlightedColumnId = cols.first?.id
                            }
                        }
                    }
                    .onChange(of: store.showProjectSwitcher) {
                        if store.showProjectSwitcher && store.isOverviewMode {
                            store.exitOverview(selecting: nil)
                        }
                    }
                    .onChange(of: store.showThemePicker) {
                        if store.showThemePicker && store.isOverviewMode {
                            store.exitOverview(selecting: nil)
                        }
                    }
                    .onChange(of: store.isOverviewMode) {
                        if store.isOverviewMode {
                            installOverviewMonitor()
                        } else {
                            // Align viewport to active tab so exit doesn't slide
                            alignActiveTab(viewportWidth: currentViewportWidth, animated: false)
                            removeOverviewMonitor()
                        }
                    }
                    .onDisappear {
                        removeOverviewMonitor()
                    }
            }
        }
    }

    @ViewBuilder
    private func columnStrip(viewportWidth: CGFloat, viewportHeight: CGFloat) -> some View {
        let layout = stripLayout(viewportWidth: viewportWidth)
        let isOverview = store.isOverviewMode

        ZStack {
            // Normal workspace view
            if !isOverview {
                ZStack(alignment: .topLeading) {
                    ForEach(columns) { col in
                        if let frame = layout.frames[col.id] {
                            WorkspaceColumnView(
                                column: col,
                                project: project,
                                activeTabId: store.activeTabId,
                                ghosttyApp: ghosttyApp,
                                surfaceManager: surfaceManager
                            )
                            .frame(width: frame.width)
                            .frame(height: viewportHeight)
                            .offset(x: frame.minX)
                            .zIndex(col.tabIds.contains(store.activeTabId ?? "") ? 1 : 0)
                            .transition(workspaceColumnTransition)
                        }
                    }
                }
                .frame(width: max(layout.contentWidth, viewportWidth), height: viewportHeight, alignment: .topLeading)
                .offset(x: -layout.viewportOffset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .clipped()
                .transition(.opacity.combined(with: .scale(scale: 1.02)))
            }

            // Overview grid
            if isOverview {
                overviewGrid(layout: layout, viewportWidth: viewportWidth, viewportHeight: viewportHeight)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .contentShape(Rectangle())
        .animation(workspaceAnimation, value: columns.map(\.id))
        .animation(overviewAnimation, value: isOverview)
    }

    @ViewBuilder
    private func overviewGrid(layout: WorkspaceStripLayout, viewportWidth: CGFloat, viewportHeight: CGFloat) -> some View {
        let scale = overviewScale(contentWidth: layout.contentWidth, viewportWidth: viewportWidth)
        let scaledContent = layout.contentWidth * scale
        let scaledHeight = viewportHeight * scale
        let offsetX = max((viewportWidth - scaledContent) / 2, Layout.overviewPadding)
        let offsetY = (viewportHeight - scaledHeight) / 2

        ZStack(alignment: .topLeading) {
            ForEach(columns) { col in
                if let frame = layout.frames[col.id] {
                    overviewThumbnail(column: col, frame: frame, viewportHeight: viewportHeight)
                        .frame(width: frame.width, height: viewportHeight)
                        .offset(x: frame.minX)
                        .zIndex(store.overviewHighlightedColumnId == col.id ? 1 : 0)
                }
            }
        }
        .frame(width: max(layout.contentWidth, viewportWidth), height: viewportHeight, alignment: .topLeading)
        .scaleEffect(scale, anchor: .topLeading)
        .offset(x: offsetX, y: offsetY)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func overviewThumbnail(column: Column, frame: CGRect, viewportHeight: CGFloat) -> some View {
        let isHighlighted = store.overviewHighlightedColumnId == column.id
        let columnTabs = column.tabIds.compactMap { tabId in
            store.tabs.first { $0.id == tabId }
        }

        VStack(spacing: Layout.workspaceColumnSpacing) {
            ForEach(columnTabs) { tab in
                let isActive = store.activeTabId == tab.id

                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(theme.bg.opacity(isHighlighted ? 0.85 : 0.7))
                    .overlay(alignment: .bottomLeading) {
                        Text(tab.label)
                            .font(Fonts.primary(size: 13))
                            .foregroundStyle(isHighlighted ? theme.text : theme.textDim)
                            .lineLimit(1)
                            .padding(8)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(
                                isActive ? theme.accent.opacity(0.85) : theme.border,
                                lineWidth: isActive ? 2 : 1
                            )
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.setActiveTab(tab.id)
                        exitOverviewAnimated(selecting: column.id)
                    }
            }
        }
        .shadow(color: isHighlighted ? theme.accent.opacity(0.3) : .clear, radius: 8)
        .animation(.easeInOut(duration: 0.15), value: isHighlighted)
    }

    private func exitOverviewAnimated(selecting columnId: String?) {
        // Set active tab from selected column before animating exit
        if let columnId,
           let projectId = store.activeProjectId,
           let col = store.projectColumns(for: projectId).first(where: { $0.id == columnId }),
           let targetTab = store.columnFocusedTab[columnId] ?? col.tabIds.first {
            store.setActiveTab(targetTab)
        }
        alignActiveTab(viewportWidth: currentViewportWidth, animated: false)
        withAnimation(overviewAnimation) {
            store.isOverviewMode = false
            store.overviewHighlightedColumnId = nil
        }
        removeOverviewMonitor()
        // Focus the terminal surface after the animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [store] in
            store.focusTerminal()
        }
    }

    private func installOverviewMonitor() {
        removeOverviewMonitor()
        overviewMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [store] event in
            guard store.isOverviewMode else { return event }
            // Let Cmd-modified keys pass through to menu shortcuts
            if event.modifierFlags.contains(.command) { return event }

            switch event.keyCode {
            case 123, 4: // left arrow, H
                store.overviewHighlightLeft()
                return nil
            case 124, 37: // right arrow, L
                store.overviewHighlightRight()
                return nil
            case 36: // return
                self.exitOverviewAnimated(selecting: store.overviewHighlightedColumnId)
                return nil
            case 53: // escape
                self.exitOverviewAnimated(selecting: nil)
                return nil
            default:
                return event
            }
        }
    }

    private func removeOverviewMonitor() {
        if let monitor = overviewMonitor {
            NSEvent.removeMonitor(monitor)
            overviewMonitor = nil
        }
    }

    private func syncColumns(viewportWidth: CGFloat) {
        layoutState.sync(
            projectId: project.id,
            columnIds: columns.map(\.id),
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

        for col in columns {
            let width = columnWidth(for: col.id, viewportWidth: viewportWidth)
            frames[col.id] = CGRect(x: leadingX, y: 0, width: width, height: 0)
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

    private func columnWidth(for columnId: String, viewportWidth: CGFloat) -> CGFloat {
        let width = layoutState.width(
            for: columnId,
            projectId: project.id,
            viewportWidth: viewportWidth
        )
        return min(max(width, Layout.workspaceColumnMinWidth), Layout.workspaceColumnMaxWidth)
    }

    private func focusedViewportOffset(viewportWidth: CGFloat) -> CGFloat {
        guard let colId = store.activeColumn?.id else { return 0 }
        let layout = stripLayout(viewportWidth: viewportWidth)

        guard layout.contentWidth > viewportWidth else { return 0 }
        guard let frame = layout.frames[colId] else { return 0 }

        let centeredOffset = frame.minX - (viewportWidth - frame.width) / 2
        return clampedViewportOffset(
            centeredOffset,
            contentWidth: layout.contentWidth,
            viewportWidth: viewportWidth
        )
    }

    private func clampedViewportOffset(_ offset: CGFloat, contentWidth: CGFloat, viewportWidth: CGFloat) -> CGFloat {
        guard contentWidth > viewportWidth else { return 0 }
        let maxOffset = contentWidth - viewportWidth
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

    let column: Column
    let project: Project
    let activeTabId: String?
    let ghosttyApp: GhosttyApp
    let surfaceManager: SurfaceManager

    private var columnTabs: [AppTab] {
        column.tabIds.compactMap { tabId in
            store.tabs.first { $0.id == tabId }
        }
    }

    var body: some View {
        VStack(spacing: Layout.workspaceColumnSpacing) {
            ForEach(columnTabs) { tab in
                let isFocused = activeTabId == tab.id

                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.clear)

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
            }
        }
        .animation(.easeInOut(duration: 0.18), value: activeTabId)
    }
}
