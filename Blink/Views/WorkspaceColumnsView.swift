import AppKit
import SwiftUI
import GhosttyKit

struct WorkspaceColumnsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let workspace: Workspace
    let ghosttyApp: GhosttyApp
    let surfaceManager: SurfaceManager
    let browserManager: BrowserManager

    @State private var layoutState = WorkspaceLayoutState()
    @State private var overviewMonitor: Any?
    @State private var resizeMonitor: Any?
    @State private var currentViewportWidth: CGFloat = 0
    @State private var overviewSnapshots: [String: NSImage] = [:]
    @State private var cachedLayout: WorkspaceStripLayout?
    @State private var cachedLayoutKey: String = ""

    private var tabs: [AppTab] {
        store.workspaceTabs(for: workspace.id)
    }

    private var columns: [Column] {
        store.workspaceColumns(for: workspace.id)
    }

    private var activeColumnIdInCurrentWorkspace: String? {
        guard let activeTabId = store.activeTabId else { return nil }
        return columns.first(where: { $0.tabIds.contains(activeTabId) })?.id
    }

    private var workspaceAnimation: Animation {
        reduceMotion ? .linear(duration: 0.01) : .smooth(duration: 0.4)
    }

    private var overviewAnimation: Animation {
        reduceMotion ? .linear(duration: 0.01) : .easeInOut(duration: 0.25)
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
                WorkspaceLandingPage(workspace: workspace)
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
                        installResizeMonitor(viewportWidth: newWidth)
                    }
                    .onChange(of: workspace.id, initial: false) { _, _ in
                        cachedLayoutKey = ""
                        currentViewportWidth = geometry.size.width
                        installResizeMonitor(viewportWidth: geometry.size.width)
                    }
                    .onChange(of: columns.count) {
                        if store.isOverviewMode {
                            let cols = store.workspaceColumns(for: workspace.id)
                            if cols.isEmpty {
                                store.exitOverview(selecting: nil)
                            } else if let highlightId = store.overviewHighlightedColumnId,
                                      !cols.contains(where: { $0.id == highlightId }) {
                                store.overviewHighlightedColumnId = cols.first?.id
                                store.overviewHighlightedTabId = cols.first?.tabIds.first
                            }
                        }
                    }
                    .onChange(of: store.showWorkspaceSwitcher) {
                        if store.showWorkspaceSwitcher && store.isOverviewMode {
                            store.exitOverview(selecting: nil)
                        }
                    }
                    .onChange(of: store.showThemePicker) {
                        if store.showThemePicker && store.isOverviewMode {
                            store.exitOverview(selecting: nil)
                        }
                    }
                    .onChange(of: store.showWorkspaceOnboarding) {
                        if store.showWorkspaceOnboarding && store.isOverviewMode {
                            store.exitOverview(selecting: nil)
                        }
                    }
                    .onChange(of: store.showAISessionPicker) {
                        if store.showAISessionPicker && store.isOverviewMode {
                            store.exitOverview(selecting: nil)
                        }
                    }
                    .onChange(of: store.isOverviewMode) {
                        if store.isOverviewMode {
                            captureOverviewSnapshots()
                            installOverviewMonitor()
                        } else {
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
        .overlay(alignment: .top) {
            if !columns.isEmpty && store.isWorkspacePathMissing(workspace.id) {
                MissingWorkspaceBanner(workspace: workspace)
                    .padding(.top, 16)
                    .padding(.horizontal, 16)
            }
        }
    }

    private func overviewThumbnailScale(layout: WorkspaceStripLayout, viewportWidth: CGFloat, viewportHeight: CGFloat) -> CGFloat {
        let maxHeightScale = Layout.overviewThumbnailHeightRatio
        let gap = Layout.overviewGap
        let padding = Layout.overviewPadding * 2
        let totalGaps = CGFloat(max(0, columns.count - 1)) * gap
        let totalUnscaledWidth = columns.reduce(CGFloat(0)) { $0 + (layout.frames[$1.id]?.width ?? 200) }
        let availableForThumbnails = viewportWidth - totalGaps - padding
        let widthScale = availableForThumbnails / max(totalUnscaledWidth, 1)
        return min(maxHeightScale, widthScale)
    }

    @ViewBuilder
    private func columnStrip(viewportWidth: CGFloat, viewportHeight: CGFloat) -> some View {
        let layout = stripLayout(viewportWidth: viewportWidth)
        let isOverview = store.isOverviewMode

        ZStack {
            ZStack(alignment: .topLeading) {
                ForEach(columns) { col in
                    if let frame = layout.frames[col.id] {
                        WorkspaceColumnView(
                            column: col,
                            workspace: workspace,
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
        let colWidths: [(column: Column, width: CGFloat)] = columns.map { col in
            ((column: col, width: (layout.frames[col.id]?.width ?? 200) * scale))
        }
        let stripWidth = colWidths.reduce(0) { $0 + $1.width } + CGFloat(max(0, colWidths.count - 1)) * gap
        let fits = stripWidth <= viewportWidth

        let colPositions: [(column: Column, centerX: CGFloat)] = {
            var positions: [(Column, CGFloat)] = []
            var x: CGFloat = 0
            for (col, w) in colWidths {
                positions.append((col, x + w / 2))
                x += w + gap
            }
            return positions
        }()

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

        let xOffset = fits ? (viewportWidth - stripWidth) / 2 : -panOffset

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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [store] in
            store.focusTerminal()
        }
    }

    private func installOverviewMonitor() {
        removeOverviewMonitor()
        overviewMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [store] event in
            guard store.isOverviewMode else { return event }

            if event.modifierFlags.contains(.command) {
                if let key = event.charactersIgnoringModifiers?.lowercased(),
                   ["h", "j", "k", "l"].contains(key) {
                    return nil
                }
                return event
            }

            switch event.keyCode {
            case 123, 4:
                store.overviewHighlightLeft()
                return nil
            case 124, 37:
                store.overviewHighlightRight()
                return nil
            case 125, 38:
                store.overviewHighlightDown()
                return nil
            case 126, 40:
                store.overviewHighlightUp()
                return nil
            case 36:
                self.exitOverviewAnimated(selecting: store.overviewHighlightedTabId)
                return nil
            case 53:
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
                  let workspaceId = store.activeWorkspaceId,
                  let colId = store.activeColumn?.id,
                  let chars = event.charactersIgnoringModifiers else { return event }

            switch chars {
            case "]":
                DispatchQueue.main.async { [self] in
                    cachedLayoutKey = ""
                    withAnimation(.easeInOut(duration: 0.18)) {
                        let _ = layoutState.increasePreset(for: colId, workspaceId: workspaceId, viewportWidth: viewportWidth)
                        persistColumnFraction(columnId: colId)
                        ensureActiveColumnVisible(viewportWidth: viewportWidth)
                    }
                }
                return nil
            case "[":
                DispatchQueue.main.async { [self] in
                    cachedLayoutKey = ""
                    withAnimation(.easeInOut(duration: 0.18)) {
                        let _ = layoutState.decreasePreset(for: colId, workspaceId: workspaceId, viewportWidth: viewportWidth)
                        persistColumnFraction(columnId: colId)
                        ensureActiveColumnVisible(viewportWidth: viewportWidth)
                    }
                }
                return nil
            case "f":
                DispatchQueue.main.async { [self] in
                    cachedLayoutKey = ""
                    withAnimation(.easeInOut(duration: 0.18)) {
                        let _ = layoutState.toggleMaximize(for: colId, workspaceId: workspaceId, viewportWidth: viewportWidth)
                        persistColumnFraction(columnId: colId)
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
        store.syncWorkspaceColumnFractions(for: workspace.id, validColumnIds: columnIds)
        layoutState.sync(
            workspaceId: workspace.id,
            columnIds: columnIds,
            defaultFraction: defaultColumnFraction(for: columnIds),
            persistedFractions: store.workspaceColumnFractions(for: workspace.id)
        )
    }

    private func restoreViewport(viewportWidth: CGFloat) {
        if layoutState.isInitialized(workspaceId: workspace.id) || store.hasWorkspaceViewportOffset(for: workspace.id) {
            clampViewportOffset(viewportWidth: viewportWidth, animated: false)
            layoutState.markInitialized(workspaceId: workspace.id)
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

        if layoutState.isInitialized(workspaceId: workspace.id) {
            if activeColumnIdInCurrentWorkspace != nil {
                alignActiveTab(viewportWidth: viewportWidth, animated: false)
            } else {
                clampViewportOffset(viewportWidth: viewportWidth, animated: false)
            }
        } else {
            restoreViewport(viewportWidth: viewportWidth)
        }
    }

    private func ensureActiveColumnVisible(viewportWidth: CGFloat) {
        guard let colId = activeColumnIdInCurrentWorkspace else { return }
        let layout = stripLayout(viewportWidth: viewportWidth)
        var offset = store.workspaceViewportOffset(for: workspace.id)
        let fitsInViewport = layout.contentWidth <= viewportWidth + Layout.workspaceColumnSpacing
        if fitsInViewport {
            store.setWorkspaceViewportOffset(0, for: workspace.id)
            return
        }

        guard let frame = layout.frames[colId] else { return }
        let colLeft = frame.minX
        let colRight = frame.minX + frame.width
        let maxOffset = layout.contentWidth - viewportWidth
        if offset > maxOffset {
            offset = max(0, maxOffset)
        }
        if colRight > offset + viewportWidth {
            offset = colRight - viewportWidth
        }
        if colLeft < offset {
            offset = colLeft
        }

        store.setWorkspaceViewportOffset(max(0, offset), for: workspace.id)
    }

    private func alignActiveTab(viewportWidth: CGFloat, animated: Bool) {
        let targetOffset = focusedViewportOffset(viewportWidth: viewportWidth)
        if animated {
            withAnimation(workspaceAnimation) {
                store.setWorkspaceViewportOffset(targetOffset, for: workspace.id)
            }
        } else {
            store.setWorkspaceViewportOffset(targetOffset, for: workspace.id)
        }

        layoutState.markInitialized(workspaceId: workspace.id)
    }

    private func applyPendingColumnMaximize(viewportWidth: CGFloat) {
        guard viewportWidth > 0,
              let activeTabId = store.activeTabId,
              tabs.contains(where: { $0.id == activeTabId }),
              let colId = activeColumnIdInCurrentWorkspace,
              store.consumePendingColumnMaximize(for: activeTabId) else { return }

        cachedLayoutKey = ""
        withAnimation(workspaceAnimation) {
            let _ = layoutState.maximize(for: colId, workspaceId: workspace.id, viewportWidth: viewportWidth)
            persistColumnFraction(columnId: colId)
            ensureActiveColumnVisible(viewportWidth: viewportWidth)
        }
    }

    private func persistColumnFraction(columnId: String) {
        store.setWorkspaceColumnFraction(
            layoutState.fraction(for: columnId, workspaceId: workspace.id),
            for: columnId,
            workspaceId: workspace.id
        )
    }

    private func clampViewportOffset(viewportWidth: CGFloat, animated: Bool) {
        let layout = stripLayout(viewportWidth: viewportWidth)
        let clampedOffset = clampedViewportOffset(
            store.workspaceViewportOffset(for: workspace.id),
            contentWidth: layout.contentWidth,
            viewportWidth: viewportWidth
        )

        guard clampedOffset != layout.viewportOffset else { return }

        if animated {
            withAnimation(workspaceAnimation) {
                store.setWorkspaceViewportOffset(clampedOffset, for: workspace.id)
            }
        } else {
            store.setWorkspaceViewportOffset(clampedOffset, for: workspace.id)
        }
    }

    private func stripLayout(viewportWidth: CGFloat) -> WorkspaceStripLayout {
        let fractions = columns.map { col in
            String(format: "%.4f", layoutState.width(for: col.id, workspaceId: workspace.id, viewportWidth: viewportWidth))
        }.joined(separator: ",")
        let offset = store.workspaceViewportOffset(for: workspace.id)
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

        let result = WorkspaceStripLayout(
            frames: frames,
            contentWidth: max(0, leadingX - Layout.workspaceColumnSpacing),
            viewportOffset: max(0, offset)
        )

        cachedLayoutKey = key
        cachedLayout = result
        return result
    }

    private func columnWidth(for columnId: String, viewportWidth: CGFloat) -> CGFloat {
        let width = layoutState.width(
            for: columnId,
            workspaceId: workspace.id,
            viewportWidth: viewportWidth
        )
        return min(max(width, Layout.workspaceColumnMinWidth), Layout.workspaceColumnMaxWidth)
    }

    private func focusedViewportOffset(viewportWidth: CGFloat) -> CGFloat {
        guard let colId = activeColumnIdInCurrentWorkspace else { return 0 }
        let layout = stripLayout(viewportWidth: viewportWidth)

        guard layout.contentWidth > viewportWidth else { return 0 }
        guard let frame = layout.frames[colId] else { return 0 }

        let currentOffset = store.workspaceViewportOffset(for: workspace.id)
        let colLeft = frame.minX
        let colRight = frame.minX + frame.width
        let colCenter = frame.minX + frame.width / 2
        let maxOffset = layout.contentWidth - viewportWidth

        switch store.focusCenteringMode {
        case .always:
            let centered = colCenter - viewportWidth / 2
            return min(max(centered, 0), maxOffset)
        case .onOverflow:
            let cols = columns
            let colIdx = cols.firstIndex { $0.id == colId }
            let idealPadding = max((viewportWidth - frame.width) / 2, 0)
            let availablePadding = min(idealPadding, Layout.workspaceColumnSpacing)

            var leftNeighborFits = true
            if let colIdx, colIdx > cols.startIndex {
                let leftCol = cols[cols.index(before: colIdx)]
                if let leftFrame = layout.frames[leftCol.id] {
                    leftNeighborFits = leftFrame.width <= availablePadding
                }
            }

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
                return minimalScrollOffset(
                    currentOffset: currentOffset,
                    colLeft: colLeft,
                    colRight: colRight,
                    viewportWidth: viewportWidth,
                    maxOffset: maxOffset
                )
            } else {
                let centered = colCenter - viewportWidth / 2
                return min(max(centered, 0), maxOffset)
            }
        case .never:
            return minimalScrollOffset(
                currentOffset: currentOffset,
                colLeft: colLeft,
                colRight: colRight,
                viewportWidth: viewportWidth,
                maxOffset: maxOffset
            )
        }
    }

    private func repairActiveTabSelectionIfNeeded() {
        guard store.activeWorkspaceId == workspace.id else { return }

        if let activeTabId = store.activeTabId,
           columns.contains(where: { $0.tabIds.contains(activeTabId) }) {
            return
        }

        if let fallbackTabId = columns.first?.tabIds.first ?? tabs.first?.id {
            store.setActiveTab(fallbackTabId)
        }
    }

    private func minimalScrollOffset(
        currentOffset: CGFloat,
        colLeft: CGFloat,
        colRight: CGFloat,
        viewportWidth: CGFloat,
        maxOffset: CGFloat
    ) -> CGFloat {
        var targetOffset = currentOffset
        if colRight > currentOffset + viewportWidth {
            targetOffset = colRight - viewportWidth
        }
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

struct WorkspaceStripLayout {
    let frames: [String: CGRect]
    let contentWidth: CGFloat
    let viewportOffset: CGFloat
}
