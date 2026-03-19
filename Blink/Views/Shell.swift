import SwiftUI
import GhosttyKit

struct Shell: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let ghosttyApp: GhosttyApp
    let surfaceManager: SurfaceManager

    @State private var escapeMonitor: Any?

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

            SettingsPage(ghosttyApp: ghosttyApp)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(theme.accent.opacity(0.85), lineWidth: 1)
                )
                .padding(.horizontal, Layout.workspacePaddingH)
                .padding(.top, Layout.workspacePaddingV)
                .padding(.bottom, 8)
                .background(Rectangle().fill(chromeBackground))
                .opacity(isSettingsActive ? 1 : 0)
                .scaleEffect(isSettingsActive ? 1 : 0.97)
                .animation(.easeOut(duration: 0.25), value: isSettingsActive)
                .allowsHitTesting(isSettingsActive)
                .zIndex(1)

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
        .ignoresSafeArea(.container, edges: .top)
        .background {
            windowBackground
                .ignoresSafeArea()
        }
        .onAppear {
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [store] event in
                guard event.keyCode == 53, // Escape
                      store.activeView == .settings else { return event }
                DispatchQueue.main.async { store.toggleSettings() }
                return nil
            }
        }
        .onDisappear {
            if let monitor = escapeMonitor {
                NSEvent.removeMonitor(monitor)
                escapeMonitor = nil
            }
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

        if store.backgroundImage != nil {
            if let cached = store.cachedBlurredWallpaper {
                Image(nsImage: cached)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scaleEffect(1.1)
                    .clipped()
            }
        }
    }

    private var activeProject: Project? {
        guard let activeProjectId = store.activeProjectId else { return nil }
        return store.projects.first(where: { $0.id == activeProjectId })
    }

    private func showSettings() {
        store.toggleSettings()
    }

    private func toggleSidebar() {
        store.toggleSidebar()
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
                    .strokeBorder(store.sidebarFocused ? theme.accent.opacity(0.85) : theme.border, lineWidth: 1)
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
    @State private var resizeMonitor: Any?
    @State private var currentViewportWidth: CGFloat = 0

    // Cached strip layout to avoid redundant recomputation across
    // onChange handlers within the same evaluation cycle.
    @State private var cachedLayout: WorkspaceStripLayout?
    @State private var cachedLayoutKey: String = ""

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
                    .onAppear { installResizeMonitor(viewportWidth: geometry.size.width) }
                    .onDisappear { removeResizeMonitor() }
                    .onChange(of: geometry.size.width) { _, newWidth in
                        // Reinstall so the closure captures the current viewport width
                        installResizeMonitor(viewportWidth: newWidth)
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
            // Normal workspace view — always in hierarchy to preserve terminal surfaces
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
            .opacity(isOverview ? 0 : 1)
            .allowsHitTesting(!isOverview)

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
        let columnTabs = column.tabIds.compactMap { store.tabsById[$0] }

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

    private func installResizeMonitor(viewportWidth: CGFloat) {
        removeResizeMonitor()
        let projectId = project.id
        resizeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [store, layoutState] event in
            guard event.modifierFlags.contains(.command),
                  !event.modifierFlags.contains(.shift),
                  !store.isOverviewMode,
                  let colId = store.activeColumn?.id,
                  let chars = event.charactersIgnoringModifiers else { return event }

            switch chars {
            case "]":
                DispatchQueue.main.async { [self] in
                    cachedLayoutKey = ""
                    withAnimation(.easeInOut(duration: 0.18)) {
                        let _ = layoutState.increasePreset(for: colId, projectId: projectId, viewportWidth: viewportWidth)
                        ensureActiveColumnVisible(viewportWidth: viewportWidth)
                    }
                }
                return nil
            case "[":
                DispatchQueue.main.async { [self] in
                    cachedLayoutKey = ""
                    withAnimation(.easeInOut(duration: 0.18)) {
                        let _ = layoutState.decreasePreset(for: colId, projectId: projectId, viewportWidth: viewportWidth)
                        ensureActiveColumnVisible(viewportWidth: viewportWidth)
                    }
                }
                return nil
            case "f":
                DispatchQueue.main.async { [self] in
                    cachedLayoutKey = ""
                    withAnimation(.easeInOut(duration: 0.18)) {
                        let _ = layoutState.toggleMaximize(for: colId, projectId: projectId, viewportWidth: viewportWidth)
                        ensureActiveColumnVisible(viewportWidth: viewportWidth)
                    }
                }
                return nil
            default:
                return event
            }
        }
    }

    private func removeResizeMonitor() {
        if let monitor = resizeMonitor {
            NSEvent.removeMonitor(monitor)
            resizeMonitor = nil
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

    /// After resize: ensure the active column is visible and fill blank space
    /// by scrolling left to show more content when possible.
    private func ensureActiveColumnVisible(viewportWidth: CGFloat) {
        guard let colId = store.activeColumn?.id else { return }
        let layout = stripLayout(viewportWidth: viewportWidth)
        var offset = store.workspaceViewportOffset(for: project.id)

        // If everything fits, show it all
        let fitsInViewport = layout.contentWidth <= viewportWidth + Layout.workspaceColumnSpacing
        if fitsInViewport {
            store.setWorkspaceViewportOffset(0, for: project.id)
            return
        }

        guard let frame = layout.frames[colId] else { return }
        let colLeft = frame.minX
        let colRight = frame.minX + frame.width

        // If there's blank space on the right, scroll left to fill it
        // (this pulls in content from the left, e.g. a 75% col next to a 25% col)
        let maxOffset = layout.contentWidth - viewportWidth
        if offset > maxOffset {
            offset = max(0, maxOffset)
        }

        // Ensure active column is fully visible
        if colRight > offset + viewportWidth {
            // Right edge clipped — scroll right
            offset = colRight - viewportWidth
        }
        if colLeft < offset {
            // Left edge clipped — scroll to its left edge
            offset = colLeft
        }

        store.setWorkspaceViewportOffset(max(0, offset), for: project.id)
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
        // Build a cache key from geometry inputs (NOT viewport offset — that's derived)
        let fractions = columns.map { col in
            String(format: "%.4f", layoutState.width(for: col.id, projectId: project.id, viewportWidth: viewportWidth))
        }.joined(separator: ",")
        let offset = store.workspaceViewportOffset(for: project.id)
        let key = "\(viewportWidth)|\(columns.map(\.id).joined(separator: ","))|\(fractions)|\(offset)"
        if key == cachedLayoutKey, let cached = cachedLayout {
            return cached
        }

        var frames: [String: CGRect] = [:]
        var leadingX: CGFloat = 0

        for col in columns {
            let width = columnWidth(for: col.id, viewportWidth: viewportWidth)
            frames[col.id] = CGRect(x: leadingX, y: 0, width: width, height: 0)
            leadingX += width + Layout.workspaceColumnSpacing
        }

        let contentWidth = max(0, leadingX - Layout.workspaceColumnSpacing)
        // Only clamp to >= 0. Don't clamp to content width — allow empty space
        // on the right when a column shrinks in place.
        let viewportOffset = max(0, offset)

        let result = WorkspaceStripLayout(
            frames: frames,
            contentWidth: contentWidth,
            viewportOffset: viewportOffset
        )

        cachedLayoutKey = key
        cachedLayout = result
        return result
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

        // Niri-style: scroll the minimum amount to make the active column fully visible
        let currentOffset = store.workspaceViewportOffset(for: project.id)
        let colLeft = frame.minX
        let colRight = frame.minX + frame.width

        var targetOffset = currentOffset

        // If column's right edge is past the viewport, scroll right
        if colRight > currentOffset + viewportWidth {
            targetOffset = colRight - viewportWidth
        }
        // If column's left edge is before the viewport, scroll left
        if colLeft < targetOffset {
            targetOffset = colLeft
        }

        return max(0, targetOffset)
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
        column.tabIds.compactMap { store.tabsById[$0] }
    }

    var body: some View {
        VStack(spacing: Layout.workspaceColumnSpacing) {
            ForEach(columnTabs) { tab in
                let isFocused = activeTabId == tab.id && !store.sidebarFocused

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
