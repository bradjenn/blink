import SwiftUI

extension AppStore {
    // MARK: - Workspace Navigation

    func setActiveWorkspace(_ id: String?) {
        if let currentWorkspace = activeWorkspaceId, let currentTab = activeTabId {
            lastActiveTab[currentWorkspace] = currentTab
        }

        workspaceLandingFocused = false
        activeWorkspaceId = id
        if let id {
            lastSelectedWorkspaceId = id
        }
        activeView = .workspaces

        if let id {
            let existingTabIds = Set(workspaceTabs(for: id).map(\.id))
            var cols = workspaceColumns(for: id)
            cols = cols.compactMap { col in
                var cleaned = col
                cleaned.tabIds = col.tabIds.filter { existingTabIds.contains($0) }
                return cleaned.tabIds.isEmpty ? nil : cleaned
            }

            let columnedTabIds = Set(cols.flatMap(\.tabIds))
            let uncolumnedTabs = workspaceTabs(for: id).filter { !columnedTabIds.contains($0.id) }
            for tab in uncolumnedTabs {
                cols.append(Column(id: UUID().uuidString, tabIds: [tab.id]))
            }

            columns[id] = cols
        }

        if let id {
            activeTabId = resolvedSelectableTabId(
                for: id,
                preferred: [lastActiveTab[id]].compactMap { $0 }
            )
            if let tabId = activeTabId {
                clearUnread(tabId)
            }
        } else {
            activeTabId = nil
        }
    }

    var lastSelectedWorkspace: Workspace? {
        guard let id = lastSelectedWorkspaceId else { return nil }
        return workspaces.first { $0.id == id }
    }

    func isWorkspacePathMissing(_ workspaceId: String) -> Bool {
        guard let workspace = workspaces.first(where: { $0.id == workspaceId }) else { return false }
        guard !workspace.isScratchSpace else { return false }
        return !Self.directoryExists(at: workspace.path)
    }

    @discardableResult
    func ensureScratchSpace() -> Workspace {
        if let scratch = workspaces.first(where: \.isScratchSpace) {
            return scratch
        }

        let scratch = Workspace.scratchSpace()
        workspaces.insert(scratch, at: 0)
        expandedWorkspaceIds.insert(scratch.id)
        return scratch
    }

    func openScratchSpace() {
        let scratch = ensureScratchSpace()
        openWorkspaceSession(scratch.id)
    }

    func openWorkspaceSession(_ id: String, restoringSavedSetup: Bool = true) {
        setActiveWorkspace(id)
        if activeTabId == nil,
           restoringSavedSetup,
           !isWorkspacePathMissing(id),
           hasWorkspaceSetup(for: id) {
            restoreWorkspaceSetup(for: id)
        }
        sidebarFocused = false
        workspaceLandingFocused = false
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            if let activeTabId = self.activeTabId,
               let activeTab = self.tabsById[activeTabId],
               activeTab.workspaceId == id,
               activeTab.isBrowser {
                self.sidebarFocused = false
                self.workspaceLandingFocused = false
                return
            }

            self.focusTerminal()
        }
    }

    func resumeLastWorkspaceSession() {
        guard let workspace = lastSelectedWorkspace else { return }
        openWorkspaceSession(workspace.id)
    }

    func setActiveTab(_ id: String) {
        guard let tab = tabsById[id] else { return }
        if activeWorkspaceId != tab.workspaceId {
            setActiveWorkspace(tab.workspaceId)
        }

        expandWorkspace(tab.workspaceId)
        let resolvedTabId = resolvedSelectableTabId(for: tab.workspaceId, preferred: [id]) ?? id
        activeTabId = resolvedTabId
        workspaceLandingFocused = false
        lastActiveTab[tab.workspaceId] = resolvedTabId
        clearUnread(resolvedTabId)
    }

    func selectNextTab() {
        guard let workspaceId = activeWorkspaceId else { return }
        let ordered = orderedTabs(for: workspaceId)
        guard !ordered.isEmpty else { return }

        guard let activeTabId,
              let currentIndex = ordered.firstIndex(where: { $0.id == activeTabId }) else {
            setActiveTab(ordered[0].id)
            return
        }

        let nextIndex = ordered.index(after: currentIndex)
        if nextIndex < ordered.endIndex {
            setActiveTab(ordered[nextIndex].id)
        } else {
            setActiveTab(ordered[ordered.startIndex].id)
        }
    }

    func selectPreviousTab() {
        guard let workspaceId = activeWorkspaceId else { return }
        let ordered = orderedTabs(for: workspaceId)
        guard !ordered.isEmpty else { return }

        guard let activeTabId,
              let currentIndex = ordered.firstIndex(where: { $0.id == activeTabId }) else {
            setActiveTab(ordered[ordered.index(before: ordered.endIndex)].id)
            return
        }

        if currentIndex > ordered.startIndex {
            setActiveTab(ordered[ordered.index(before: currentIndex)].id)
        } else {
            setActiveTab(ordered[ordered.index(before: ordered.endIndex)].id)
        }
    }

    func focusLeft() {
        guard let workspaceId = activeWorkspaceId else { return }
        let cols = workspaceColumns(for: workspaceId)

        if sidebarFocused { return }

        if workspaceLandingFocused {
            if sidebarVisible {
                focusSidebar()
            }
            return
        }

        guard let currentCol = activeColumn,
              let colIdx = cols.firstIndex(where: { $0.id == currentCol.id }) else { return }

        if let tabId = activeTabId {
            columnFocusedTab[currentCol.id] = tabId
        }

        if colIdx > cols.startIndex {
            let targetCol = cols[cols.index(before: colIdx)]
            let targetTab = columnFocusedTab[targetCol.id] ?? targetCol.tabIds.first
            if let targetTab { setActiveTab(targetTab) }
        } else if sidebarVisible {
            sidebarFocused = true
        }
    }

    func focusRight() {
        if sidebarFocused {
            focusTerminal()
            return
        }

        guard let workspaceId = activeWorkspaceId else { return }
        let cols = workspaceColumns(for: workspaceId)

        if workspaceLandingFocused { return }

        guard let currentCol = activeColumn,
              let colIdx = cols.firstIndex(where: { $0.id == currentCol.id }) else { return }

        if let tabId = activeTabId {
            columnFocusedTab[currentCol.id] = tabId
        }

        let nextIdx = cols.index(after: colIdx)
        if nextIdx < cols.endIndex {
            let targetCol = cols[nextIdx]
            let targetTab = columnFocusedTab[targetCol.id] ?? targetCol.tabIds.first
            if let targetTab { setActiveTab(targetTab) }
        }
    }

    func focusDown() {
        guard let currentCol = activeColumn,
              let activeTabId,
              let paneIdx = currentCol.tabIds.firstIndex(of: activeTabId) else { return }

        let nextIdx = currentCol.tabIds.index(after: paneIdx)
        if nextIdx < currentCol.tabIds.endIndex {
            setActiveTab(currentCol.tabIds[nextIdx])
        }
    }

    func focusUp() {
        guard let currentCol = activeColumn,
              let activeTabId,
              let paneIdx = currentCol.tabIds.firstIndex(of: activeTabId) else { return }

        if paneIdx > currentCol.tabIds.startIndex {
            setActiveTab(currentCol.tabIds[currentCol.tabIds.index(before: paneIdx)])
        }
    }

    func moveColumnLeft() {
        guard let workspaceId = activeWorkspaceId,
              let currentCol = activeColumn else { return }
        var cols = workspaceColumns(for: workspaceId)
        guard let idx = cols.firstIndex(where: { $0.id == currentCol.id }),
              idx > cols.startIndex else { return }
        cols.swapAt(idx, cols.index(before: idx))
        columns[workspaceId] = cols
    }

    func moveColumnRight() {
        guard let workspaceId = activeWorkspaceId,
              let currentCol = activeColumn else { return }
        var cols = workspaceColumns(for: workspaceId)
        guard let idx = cols.firstIndex(where: { $0.id == currentCol.id }) else { return }
        let nextIdx = cols.index(after: idx)
        guard nextIdx < cols.endIndex else { return }
        cols.swapAt(idx, nextIdx)
        columns[workspaceId] = cols
    }

    func absorbFromLeft() {
        guard let workspaceId = activeWorkspaceId,
              let currentCol = activeColumn else { return }
        var cols = workspaceColumns(for: workspaceId)
        guard let colIdx = cols.firstIndex(where: { $0.id == currentCol.id }),
              colIdx > cols.startIndex else { return }

        let sourceIdx = cols.index(before: colIdx)
        guard let absorbedTabId = cols[sourceIdx].tabIds.last else { return }

        cols[sourceIdx].tabIds.removeLast()
        cols[colIdx].tabIds.append(absorbedTabId)

        if columnFocusedTab[cols[sourceIdx].id] == absorbedTabId {
            columnFocusedTab.removeValue(forKey: cols[sourceIdx].id)
        }

        if cols[sourceIdx].tabIds.isEmpty {
            columnFocusedTab[cols[sourceIdx].id] = nil
            cols.remove(at: sourceIdx)
        }

        columns[workspaceId] = cols
    }

    func absorbFromRight() {
        guard let workspaceId = activeWorkspaceId,
              let currentCol = activeColumn else { return }
        var cols = workspaceColumns(for: workspaceId)
        guard let colIdx = cols.firstIndex(where: { $0.id == currentCol.id }) else { return }

        let sourceIdx = cols.index(after: colIdx)
        guard sourceIdx < cols.endIndex,
              let absorbedTabId = cols[sourceIdx].tabIds.last else { return }

        cols[sourceIdx].tabIds.removeLast()
        cols[colIdx].tabIds.append(absorbedTabId)

        if columnFocusedTab[cols[sourceIdx].id] == absorbedTabId {
            columnFocusedTab.removeValue(forKey: cols[sourceIdx].id)
        }

        if cols[sourceIdx].tabIds.isEmpty {
            columnFocusedTab[cols[sourceIdx].id] = nil
            cols.remove(at: sourceIdx)
        }

        columns[workspaceId] = cols
    }

    func expelActiveTab() {
        guard let workspaceId = activeWorkspaceId,
              let activeTabId,
              let currentCol = activeColumn else { return }
        guard currentCol.tabIds.count > 1 else { return }

        var cols = workspaceColumns(for: workspaceId)
        guard let colIdx = cols.firstIndex(where: { $0.id == currentCol.id }) else { return }

        cols[colIdx].tabIds.removeAll { $0 == activeTabId }
        columnFocusedTab.removeValue(forKey: currentCol.id)

        let newCol = Column(id: UUID().uuidString, tabIds: [activeTabId])
        cols.insert(newCol, at: cols.index(after: colIdx))

        columns[workspaceId] = cols
    }

    // MARK: - Overview Actions

    func toggleOverview() {
        guard let workspaceId = activeWorkspaceId else { return }
        let cols = workspaceColumns(for: workspaceId)
        guard !cols.isEmpty else { return }

        if isOverviewMode {
            exitOverview(selecting: overviewHighlightedTabId)
        } else {
            isOverviewMode = true
            overviewHighlightedColumnId = activeColumn?.id
            overviewHighlightedTabId = activeTabId
        }
    }

    func exitOverview(selecting tabId: String?) {
        if let tabId {
            if tabsById[tabId] != nil {
                setActiveTab(tabId)
            } else if let workspaceId = activeWorkspaceId,
                      let column = workspaceColumns(for: workspaceId).first(where: { $0.id == tabId }),
                      let fallback = column.tabIds.first {
                setActiveTab(fallback)
            }
        }
        isOverviewMode = false
        overviewHighlightedColumnId = nil
        overviewHighlightedTabId = nil
    }

    func overviewHighlightLeft() {
        guard let workspaceId = activeWorkspaceId else { return }
        let cols = workspaceColumns(for: workspaceId)
        guard let highlightId = overviewHighlightedColumnId,
              let idx = cols.firstIndex(where: { $0.id == highlightId }),
              idx > cols.startIndex else { return }
        let newCol = cols[cols.index(before: idx)]
        overviewHighlightedColumnId = newCol.id
        overviewHighlightedTabId = newCol.tabIds.first
    }

    func overviewHighlightRight() {
        guard let workspaceId = activeWorkspaceId else { return }
        let cols = workspaceColumns(for: workspaceId)
        guard let highlightId = overviewHighlightedColumnId,
              let idx = cols.firstIndex(where: { $0.id == highlightId }) else { return }
        let next = cols.index(after: idx)
        guard next < cols.endIndex else { return }
        let newCol = cols[next]
        overviewHighlightedColumnId = newCol.id
        overviewHighlightedTabId = newCol.tabIds.first
    }

    func overviewHighlightUp() {
        guard let highlightedColId = overviewHighlightedColumnId,
              let workspaceId = activeWorkspaceId,
              let col = workspaceColumns(for: workspaceId).first(where: { $0.id == highlightedColId }),
              let currentTab = overviewHighlightedTabId,
              let idx = col.tabIds.firstIndex(of: currentTab),
              idx > col.tabIds.startIndex else { return }
        overviewHighlightedTabId = col.tabIds[col.tabIds.index(before: idx)]
    }

    func overviewHighlightDown() {
        guard let highlightedColId = overviewHighlightedColumnId,
              let workspaceId = activeWorkspaceId,
              let col = workspaceColumns(for: workspaceId).first(where: { $0.id == highlightedColId }),
              let currentTab = overviewHighlightedTabId,
              let idx = col.tabIds.firstIndex(of: currentTab) else { return }
        let next = col.tabIds.index(after: idx)
        guard next < col.tabIds.endIndex else { return }
        overviewHighlightedTabId = col.tabIds[next]
    }
}
