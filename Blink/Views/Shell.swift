import SwiftUI
import GhosttyKit

struct Shell: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let ghosttyApp: GhosttyApp
    let surfaceManager: SurfaceManager
    let browserManager: BrowserManager

    @State private var escapeMonitor: Any?
    @State private var shortcutMonitor: Any?

    private var isSettingsActive: Bool {
        store.activeView == .settings
    }

    private var chromeBackground: AnyShapeStyle {
        store.hasWallpaper
            ? AnyShapeStyle(theme.bg.opacity(store.backgroundOpacity))
            : AnyShapeStyle(theme.bg)
    }

    private var settingsBackground: AnyShapeStyle {
        if store.hasWallpaper {
            let opacity = max(store.backgroundOpacity + 0.22, 0.9)
            return AnyShapeStyle(theme.bg.opacity(min(opacity, 0.97)))
        } else {
            return AnyShapeStyle(theme.bg.opacity(0.97))
        }
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
                .background(Rectangle().fill(settingsBackground))
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

            if store.showCommandPalette {
                CommandPalette(
                    onDismiss: { store.dismissCommandPalette() }
                )
                .zIndex(3)
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
            shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [store] event in
                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                guard store.activeProjectId != nil,
                      !store.showProjectSwitcher,
                      !store.showThemePicker,
                      !store.showCommandPalette,
                      store.activeView == .projects else { return event }

                switch modifiers {
                case [.command]:
                    switch event.keyCode {
                    case 123: // Left arrow
                        DispatchQueue.main.async {
                            store.focusLeft()
                        }
                        return nil
                    case 124: // Right arrow
                        DispatchQueue.main.async {
                            store.focusRight()
                        }
                        return nil
                    default:
                        switch event.charactersIgnoringModifiers?.lowercased() {
                        case "h":
                            DispatchQueue.main.async {
                                store.focusLeft()
                            }
                            return nil
                        case "l":
                            DispatchQueue.main.async {
                                store.focusRight()
                            }
                            return nil
                        default:
                            return event
                        }
                    }
                case [.command, .shift]:
                    switch event.charactersIgnoringModifiers {
                    case "-":
                        DispatchQueue.main.async {
                            store.splitActivePaneWithNewTab()
                        }
                        return nil
                    case "\\":
                        DispatchQueue.main.async {
                            store.splitActiveColumnWithNewTab()
                        }
                        return nil
                    default:
                        return event
                    }
                default:
                    return event
                }
            }
        }
        .onDisappear {
            if let monitor = escapeMonitor {
                NSEvent.removeMonitor(monitor)
                escapeMonitor = nil
            }
            if let monitor = shortcutMonitor {
                NSEvent.removeMonitor(monitor)
                shortcutMonitor = nil
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
                        surfaceManager: surfaceManager,
                        browserManager: browserManager
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
            .onAppear {
                store.completePendingSidebarRevealFocus()
            }
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
    let browserManager: BrowserManager

    @State private var layoutState = WorkspaceLayoutState()
    @State private var overviewMonitor: Any?
    @State private var resizeMonitor: Any?
    @State private var currentViewportWidth: CGFloat = 0
    @State private var overviewSnapshots: [String: NSImage] = [:]

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

    private var activeColumnIdInCurrentProject: String? {
        guard let activeTabId = store.activeTabId else { return nil }
        return columns.first(where: { $0.tabIds.contains(activeTabId) })?.id
    }

    private var workspaceAnimation: Animation {
        reduceMotion ? .linear(duration: 0.01) : .smooth(duration: 0.4)
    }

    private var overviewAnimation: Animation {
        reduceMotion ? .linear(duration: 0.01) : .easeInOut(duration: 0.25)
    }

    /// Compute thumbnail scale so all columns fit in viewport width, capped by max height ratio.
    private func overviewThumbnailScale(layout: WorkspaceStripLayout, viewportWidth: CGFloat, viewportHeight: CGFloat) -> CGFloat {
        let maxHeightScale = Layout.overviewThumbnailHeightRatio
        let gap = Layout.overviewGap
        let padding = Layout.overviewPadding * 2

        // Total unscaled column widths + gaps + padding
        let totalGaps = CGFloat(max(0, columns.count - 1)) * gap
        let totalUnscaledWidth = columns.reduce(CGFloat(0)) { $0 + (layout.frames[$1.id]?.width ?? 200) }

        // Scale to fit: (totalUnscaledWidth * scale) + gaps + padding <= viewportWidth
        let availableForThumbnails = viewportWidth - totalGaps - padding
        let widthScale = availableForThumbnails / max(totalUnscaledWidth, 1)

        return min(maxHeightScale, widthScale)
    }

    private var workspaceColumnTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.985, anchor: .trailing)),
            removal: .opacity
                .combined(with: .scale(scale: 0.8))
        )
    }

    var body: some View {
        GeometryReader { geometry in
            if columns.isEmpty {
                VStack(spacing: 12) {
                    Text("No windows in this workspace")
                        .font(Fonts.primary(size: 16))
                        .foregroundStyle(theme.text)
                    Text("Use the sidebar controls to open a terminal, browser, or tool window")
                        .font(Fonts.primary(size: 13))
                        .foregroundStyle(theme.textDim)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                columnStrip(viewportWidth: geometry.size.width, viewportHeight: geometry.size.height)
                    .onChange(of: columns.map(\.id), initial: true) { _, _ in
                        repairActiveTabSelectionIfNeeded()
                        syncColumns(viewportWidth: geometry.size.width)
                        restoreViewport(viewportWidth: geometry.size.width)
                        alignActiveTab(viewportWidth: geometry.size.width, animated: false)
                        applyPendingColumnMaximize(viewportWidth: geometry.size.width)
                    }
                    .onChange(of: store.activeTabId, initial: false) {
                        repairActiveTabSelectionIfNeeded()
                        alignActiveTab(viewportWidth: geometry.size.width, animated: !reduceMotion)
                        applyPendingColumnMaximize(viewportWidth: geometry.size.width)
                    }
                    .onChange(of: store.pendingMaximizedTabId, initial: false) {
                        applyPendingColumnMaximize(viewportWidth: geometry.size.width)
                    }
                    .onChange(of: store.sidebarVisible, initial: false) {
                        handleViewportChange(viewportWidth: geometry.size.width)
                    }
                    .onChange(of: geometry.size.width, initial: true) { _, newWidth in
                        currentViewportWidth = newWidth
                        handleViewportChange(viewportWidth: newWidth)
                    }
                    .onAppear {
                        currentViewportWidth = geometry.size.width
                        installResizeMonitor(viewportWidth: geometry.size.width)
                    }
                    .onDisappear {
                        removeResizeMonitor()
                    }
                    .onChange(of: geometry.size.width) { _, newWidth in
                        currentViewportWidth = newWidth
                        // Reinstall so the closure captures the current viewport width
                        installResizeMonitor(viewportWidth: newWidth)
                    }
                    .onChange(of: project.id, initial: false) { _, _ in
                        cachedLayoutKey = ""
                        currentViewportWidth = geometry.size.width
                        installResizeMonitor(viewportWidth: geometry.size.width)
                    }
                    .onChange(of: columns.count) {
                        if store.isOverviewMode {
                            let cols = store.projectColumns(for: project.id)
                            if cols.isEmpty {
                                store.exitOverview(selecting: nil)
                            } else if let highlightId = store.overviewHighlightedColumnId,
                                      !cols.contains(where: { $0.id == highlightId }) {
                                store.overviewHighlightedColumnId = cols.first?.id
                                store.overviewHighlightedTabId = cols.first?.tabIds.first
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
                            captureOverviewSnapshots()
                            installOverviewMonitor()
                        } else {
                            // Align viewport to active tab so exit doesn't slide
                            alignActiveTab(viewportWidth: currentViewportWidth, animated: false)
                            removeOverviewMonitor()
                            overviewSnapshots = [:]
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
                            surfaceManager: surfaceManager,
                            browserManager: browserManager
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

            // Overview grid — explicitly sized to viewport and pinned to top-leading
            // so it isn't affected by the workspace content expanding beyond viewport
            if isOverview {
                overviewGrid(layout: layout, viewportWidth: viewportWidth, viewportHeight: viewportHeight)
                    .frame(width: viewportWidth, height: viewportHeight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .animation(workspaceAnimation, value: columns.map(\.id))
        .animation(overviewAnimation, value: isOverview)
    }

    @ViewBuilder
    private func overviewGrid(layout: WorkspaceStripLayout, viewportWidth: CGFloat, viewportHeight: CGFloat) -> some View {
        let scale = overviewThumbnailScale(layout: layout, viewportWidth: viewportWidth, viewportHeight: viewportHeight)
        let gap = Layout.overviewGap
        let thumbnailHeight = viewportHeight * scale

        // Compute column widths at thumbnail scale
        let colWidths: [(column: Column, width: CGFloat)] = columns.map { col in
            let w = (layout.frames[col.id]?.width ?? 200) * scale
            return (col, w)
        }

        let stripWidth = colWidths.reduce(0) { $0 + $1.width } + CGFloat(max(0, colWidths.count - 1)) * gap
        let fits = stripWidth <= viewportWidth

        // Compute cumulative X positions for panning
        let colPositions: [(column: Column, centerX: CGFloat)] = {
            var positions: [(Column, CGFloat)] = []
            var x: CGFloat = 0
            for (col, w) in colWidths {
                positions.append((col, x + w / 2))
                x += w + gap
            }
            return positions
        }()

        // Pan offset: center on highlighted column when strip overflows
        let panOffset: CGFloat = {
            guard !fits,
                  let highlightId = store.overviewHighlightedColumnId,
                  let entry = colPositions.first(where: { $0.column.id == highlightId }) else {
                return 0
            }
            let idealOffset = entry.centerX - viewportWidth / 2
            let maxOffset = max(0, stripWidth - viewportWidth)
            return min(max(idealOffset, 0), maxOffset)
        }()

        let xOffset: CGFloat = fits
            ? (viewportWidth - stripWidth) / 2   // Center when everything fits
            : -panOffset                          // Pan to highlighted column

        HStack(spacing: gap) {
            ForEach(colWidths, id: \.column.id) { entry in
                overviewThumbnail(column: entry.column, viewportHeight: viewportHeight, scale: scale)
                    .frame(width: entry.width, height: thumbnailHeight)
                    .zIndex(store.overviewHighlightedColumnId == entry.column.id ? 1 : 0)
            }
        }
        .offset(x: xOffset)
        .frame(width: viewportWidth, height: viewportHeight, alignment: .leading)
        .clipped()
        .animation(overviewAnimation, value: store.overviewHighlightedColumnId)
    }

    @ViewBuilder
    private func overviewThumbnail(column: Column, viewportHeight: CGFloat, scale: CGFloat) -> some View {
        let isHighlightedColumn = store.overviewHighlightedColumnId == column.id
        let columnTabs = column.tabIds.compactMap { store.tabsById[$0] }
        let cornerRadius = Layout.overviewCornerRadius
        let paneSpacing: CGFloat = Layout.workspaceColumnSpacing * scale

        VStack(spacing: paneSpacing) {
            ForEach(columnTabs) { tab in
                let isHighlightedTab = store.overviewHighlightedTabId == tab.id

                ZStack {
                    theme.bg.opacity(isHighlightedTab ? 0.85 : isHighlightedColumn ? 0.75 : 0.7)
                    if let snapshot = overviewSnapshots[tab.id] {
                        Image(nsImage: snapshot)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    Text(tab.label)
                        .font(Fonts.primary(size: 11))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(theme.bg.opacity(0.75))
                        )
                        .padding(4)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            isHighlightedTab ? theme.accent : theme.border.opacity(0.5),
                            lineWidth: isHighlightedTab ? 2 : 1
                        )
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    store.setActiveTab(tab.id)
                    exitOverviewAnimated(selecting: nil)
                }
            }
        }
        .scaleEffect(isHighlightedColumn ? 1.03 : 1.0)
        .shadow(color: isHighlightedColumn ? theme.accent.opacity(0.3) : .clear, radius: 12)
        .animation(.easeInOut(duration: 0.15), value: store.overviewHighlightedTabId)
        .animation(.easeInOut(duration: 0.15), value: isHighlightedColumn)
    }

    private func exitOverviewAnimated(selecting tabId: String?) {
        if let tabId {
            store.setActiveTab(tabId)
        }
        alignActiveTab(viewportWidth: currentViewportWidth, animated: false)
        withAnimation(overviewAnimation) {
            store.isOverviewMode = false
            store.overviewHighlightedColumnId = nil
            store.overviewHighlightedTabId = nil
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

            // Block Cmd+HJKL during overview so normal focus commands don't fire
            if event.modifierFlags.contains(.command) {
                if let key = event.charactersIgnoringModifiers?.lowercased(),
                   ["h", "j", "k", "l"].contains(key) {
                    return nil
                }
                return event
            }

            switch event.keyCode {
            case 123, 4: // left arrow, H
                store.overviewHighlightLeft()
                return nil
            case 124, 37: // right arrow, L
                store.overviewHighlightRight()
                return nil
            case 125, 38: // down arrow, J
                store.overviewHighlightDown()
                return nil
            case 126, 40: // up arrow, K
                store.overviewHighlightUp()
                return nil
            case 36: // return
                self.exitOverviewAnimated(selecting: store.overviewHighlightedTabId)
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

    private func captureOverviewSnapshots() {
        var snapshots: [String: NSImage] = [:]
        for (tabId, surfaceView) in surfaceManager.surfaces {
            let bounds = surfaceView.bounds
            guard bounds.width > 0 && bounds.height > 0 else { continue }
            let image = NSImage(size: bounds.size)
            image.lockFocus()
            if let ctx = NSGraphicsContext.current?.cgContext {
                surfaceView.layer?.render(in: ctx)
            }
            image.unlockFocus()
            snapshots[tabId] = image
        }
        overviewSnapshots = snapshots
    }

    private func installResizeMonitor(viewportWidth: CGFloat) {
        removeResizeMonitor()
        resizeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [store, layoutState] event in
            guard event.modifierFlags.contains(.command),
                  !event.modifierFlags.contains(.shift),
                  !store.isOverviewMode,
                  let projectId = store.activeProjectId,
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

    private func defaultColumnFraction(for columnIds: [String]) -> CGFloat {
        guard columnIds.count == 1,
              let column = columns.first,
              column.id == columnIds[0],
              column.tabIds.count == 1,
              let tabId = column.tabIds.first,
              store.isFullWidthTab(tabId) else {
            return Layout.workspaceColumnDefaultFraction
        }

        return 1.0
    }

    private func syncColumns(viewportWidth: CGFloat) {
        let columnIds = columns.map(\.id)
        layoutState.sync(
            projectId: project.id,
            columnIds: columnIds,
            defaultFraction: defaultColumnFraction(for: columnIds)
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
        guard viewportWidth > 0 else { return }

        if store.isOverviewMode {
            clampViewportOffset(viewportWidth: viewportWidth, animated: false)
            return
        }

        if layoutState.isInitialized(projectId: project.id) {
            if activeColumnIdInCurrentProject != nil {
                alignActiveTab(viewportWidth: viewportWidth, animated: false)
            } else {
                clampViewportOffset(viewportWidth: viewportWidth, animated: false)
            }
        } else {
            restoreViewport(viewportWidth: viewportWidth)
        }
    }

    /// After resize: ensure the active column is visible and fill blank space
    /// by scrolling left to show more content when possible.
    private func ensureActiveColumnVisible(viewportWidth: CGFloat) {
        guard let colId = activeColumnIdInCurrentProject else { return }
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

    private func applyPendingColumnMaximize(viewportWidth: CGFloat) {
        guard viewportWidth > 0,
              let activeTabId = store.activeTabId,
              tabs.contains(where: { $0.id == activeTabId }),
              let colId = activeColumnIdInCurrentProject,
              store.consumePendingColumnMaximize(for: activeTabId) else { return }

        cachedLayoutKey = ""
        withAnimation(workspaceAnimation) {
            let _ = layoutState.maximize(for: colId, projectId: project.id, viewportWidth: viewportWidth)
            ensureActiveColumnVisible(viewportWidth: viewportWidth)
        }
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
        guard let colId = activeColumnIdInCurrentProject else { return 0 }
        let layout = stripLayout(viewportWidth: viewportWidth)

        guard layout.contentWidth > viewportWidth else { return 0 }
        guard let frame = layout.frames[colId] else { return 0 }

        let currentOffset = store.workspaceViewportOffset(for: project.id)
        let colLeft = frame.minX
        let colRight = frame.minX + frame.width
        let colCenter = frame.minX + frame.width / 2
        let maxOffset = layout.contentWidth - viewportWidth

        switch store.focusCenteringMode {
        case .always:
            // Center the active column in the viewport
            let centered = colCenter - viewportWidth / 2
            return min(max(centered, 0), maxOffset)

        case .onOverflow:
            // Center only when adjacent columns don't fit alongside
            let cols = columns
            let colIdx = cols.firstIndex { $0.id == colId }

            // Calculate how much padding we'd ideally give on each side
            let idealPadding = max((viewportWidth - frame.width) / 2, 0)
            let availablePadding = min(idealPadding, Layout.workspaceColumnSpacing)

            // Check if left neighbor fits
            var leftNeighborFits = true
            if let colIdx, colIdx > cols.startIndex {
                let leftCol = cols[cols.index(before: colIdx)]
                if let leftFrame = layout.frames[leftCol.id] {
                    leftNeighborFits = leftFrame.width <= availablePadding
                }
            }

            // Check if right neighbor fits
            var rightNeighborFits = true
            if let colIdx {
                let nextIdx = cols.index(after: colIdx)
                if nextIdx < cols.endIndex {
                    let rightCol = cols[nextIdx]
                    if let rightFrame = layout.frames[rightCol.id] {
                        rightNeighborFits = rightFrame.width <= availablePadding
                    }
                }
            }

            if leftNeighborFits && rightNeighborFits {
                // Both neighbors fit — use minimal scroll (same as .never)
                return minimalScrollOffset(
                    currentOffset: currentOffset, colLeft: colLeft,
                    colRight: colRight, viewportWidth: viewportWidth, maxOffset: maxOffset
                )
            } else {
                // Neighbors don't fit — center the active column
                let centered = colCenter - viewportWidth / 2
                return min(max(centered, 0), maxOffset)
            }

        case .never:
            // Niri-style: scroll the minimum amount to make the active column fully visible
            return minimalScrollOffset(
                currentOffset: currentOffset, colLeft: colLeft,
                colRight: colRight, viewportWidth: viewportWidth, maxOffset: maxOffset
            )
        }
    }

    private func repairActiveTabSelectionIfNeeded() {
        guard store.activeProjectId == project.id else { return }

        if let activeTabId = store.activeTabId,
           columns.contains(where: { $0.tabIds.contains(activeTabId) }) {
            return
        }

        if let fallbackTabId = columns.first?.tabIds.first ?? tabs.first?.id {
            store.setActiveTab(fallbackTabId)
        }
    }

    /// Scroll the minimum amount to make the column fully visible.
    private func minimalScrollOffset(
        currentOffset: CGFloat, colLeft: CGFloat, colRight: CGFloat,
        viewportWidth: CGFloat, maxOffset: CGFloat
    ) -> CGFloat {
        var targetOffset = currentOffset

        // If column's right edge is past the viewport, scroll right
        if colRight > currentOffset + viewportWidth {
            targetOffset = colRight - viewportWidth
        }
        // If column's left edge is before the viewport, scroll left
        if colLeft < targetOffset {
            targetOffset = colLeft
        }

        return min(max(targetOffset, 0), maxOffset)
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
    let browserManager: BrowserManager

    private var columnTabs: [AppTab] {
        column.tabIds.compactMap { store.tabsById[$0] }
    }

    var body: some View {
        @Bindable var browserManager = browserManager

        VStack(spacing: Layout.workspaceColumnSpacing) {
            ForEach(columnTabs) { tab in
                let isFocused = activeTabId == tab.id && !store.sidebarFocused
                let projectDownloads = browserManager.downloads
                    .filter { $0.projectId == project.id }
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
                                paneId: tab.projectSetupPaneId ?? tab.id,
                                ghosttyApp: ghosttyApp,
                                surfaceManager: surfaceManager,
                                projectId: project.id,
                                projectName: project.name,
                                workingDirectory: tab.workingDirectory ?? project.path,
                                isFocused: isFocused,
                                command: store.terminalLaunchCommand(for: tab, project: project)
                            )
                        }
                    case .browser:
                        BrowserView(
                            tab: tab,
                            project: project,
                            browserManager: browserManager,
                            projectDownloads: projectDownloads,
                            isFocused: isFocused
                        )
                    case .chat:
                        Text("Chat panes are not currently supported in Blink workspaces.")
                            .font(Fonts.primary(size: 13))
                            .foregroundStyle(theme.textDim)
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

private struct StoppedCommandPaneView: View {
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
