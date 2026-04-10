import Combine
import AppKit
import SwiftUI

struct BrowserView: View {
    private static let sidebarTransition = Animation.snappy(duration: 0.24, extraBounce: 0)
    private static let sidebarHoverKeepOpenDuration: TimeInterval = 0.7
    private static let sidebarHoverDismissDelay: TimeInterval = 0.12
    private static let indeterminateDownloadProgress: CGFloat = 0.28
    private static let recentDownloadHighlightDuration: TimeInterval = 2.5
    private static let sidebarControlCornerRadius: CGFloat = 9
    private static let swipeIndicatorHideDelay: TimeInterval = 0.18
    private static let swipeIndicatorExitDuration: TimeInterval = 0.16

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let tab: AppTab
    let workspace: Workspace
    let browserManager: BrowserManager
    let workspaceDownloads: [BrowserDownloadItem]
    let isFocused: Bool

    @State private var addressText = ""
    @State private var isSidebarHotspotHovered = false
    @State private var isSidebarPanelHovered = false
    @State private var isSidebarHoverLatched = false
    @State private var isSidebarHoverDismissProtected = false
    @State private var isDownloadsPopoverPresented = false
    @State private var isDownloadActivityAnimating = false
    @State private var isRecentDownloadHighlighted = false
    @State private var recentDownloadHighlightWorkItem: DispatchWorkItem?
    @State private var highlightedAddressSuggestionID: String?
    @State private var isAddressBarSuggestionsActive = false
    @State private var swipeIndicatorHideWorkItem: DispatchWorkItem?
    @State private var swipeNavigationFeedback: BrowserSwipeNavigationFeedback?
    @State private var visibleWorkspaceDownloads: [BrowserDownloadItem] = []
    @State private var addressBarFocused = false

    @State private var sidebarHoverDismissWorkItem: DispatchWorkItem?
    @State private var sidebarHoverProtectionWorkItem: DispatchWorkItem?

    private var paneState: BrowserPaneState {
        tab.browserState ?? .empty
    }

    private var selectedBrowserTab: BrowserPaneTab? {
        paneState.selectedTab
    }

    private var sidebarContentInset: CGFloat {
        paneState.isSidebarPinned ? Layout.browserSidebarWidth : 0
    }

    private var browserContentAnimation: Animation? {
        browserManager.engine == .chromium ? nil : Self.sidebarTransition
    }

    private var isSidebarExpanded: Bool {
        guard !store.hasBlockingModalPresentation || paneState.isSidebarPinned else {
            return false
        }
        return paneState.isSidebarPinned
            || isSidebarHoverLatched
            || addressBarFocused
            || selectedBrowserTab?.state.preferredFocus == .addressBar
    }

    private var addressBarSuggestions: [BrowserHistoryEntry] {
        browserManager.addressBarSuggestions(for: addressText)
    }

    private var isAddressBarSuggestionsPresented: Bool {
        isAddressBarSuggestionsActive && !addressBarSuggestions.isEmpty
    }

    private var shouldHighlightAddressBarSuggestions: Bool {
        addressBarFocused && isAddressBarSuggestionsActive
    }

    private func resolveController(for browserTab: BrowserPaneTab) -> any BrowserHostController {
        browserManager.controller(
            for: browserTab.id,
            workspaceId: workspace.id,
            profileId: store.profileId(for: workspace.id),
            initialState: browserTab.state
        ) { state in
            DispatchQueue.main.async {
                store.updateBrowserState(state, for: browserTab.id, in: tab.id)
            }
        }
    }

    var body: some View {
        Group {
            if let selectedBrowserTab {
                let resolvedWorkspaceDownloads = visibleWorkspaceDownloads.isEmpty ? workspaceDownloads : visibleWorkspaceDownloads
                let activeDownloads = resolvedWorkspaceDownloads.filter(\.isInProgress)
                let controller = resolveController(for: selectedBrowserTab)
                ZStack(alignment: .leading) {
                    ZStack(alignment: .leading) {
                        BrowserContainerView(
                            paneTabId: tab.id,
                            browserTabId: selectedBrowserTab.id,
                            controller: controller,
                            onSwipeNavigationFeedback: { feedback in
                                DispatchQueue.main.async {
                                    updateSwipeIndicator(feedback)
                                }
                            }
                        )
                        .overlay {
                            swipeNavigationOverlay
                        }
                        .padding(.leading, sidebarContentInset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .animation(browserContentAnimation, value: sidebarContentInset)

                        browserSidebar(
                            selectedBrowserTab: selectedBrowserTab,
                            controller: controller,
                            resolvedWorkspaceDownloads: resolvedWorkspaceDownloads,
                            activeDownloads: activeDownloads
                        )
                        .animation(Self.sidebarTransition, value: isSidebarExpanded)
                    }
                    .background(paneState.isSidebarPinned ? Color.clear : theme.bg)
                    .clipShape(RoundedRectangle(cornerRadius: Layout.browserSurfaceCornerRadius, style: .continuous))

                    if !paneState.isSidebarPinned {
                        sidebarHoverBridge
                    }
                }
                .onAppear {
                    syncVisibleDownloads()
                    syncAddressText(from: selectedBrowserTab.state)
                    if isFocused {
                        syncFocus(controller: controller, browserTab: selectedBrowserTab)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: BrowserManager.downloadsDidChangeNotification)) { _ in
                    syncVisibleDownloads()
                }
                .onChange(of: selectedBrowserTab.id) { _, _ in
                    syncVisibleDownloads()
                    syncAddressText(from: selectedBrowserTab.state)
                    highlightedAddressSuggestionID = nil
                    clearSwipeIndicator()
                    if isFocused {
                        syncFocus(controller: controller, browserTab: selectedBrowserTab)
                    }
                }
                .onChange(of: controller.session.state.urlString) { _, _ in
                    if !addressBarFocused {
                        syncAddressText(from: controller.session.state)
                    }
                }
                .onChange(of: controller.session.addressBarFocusRequestID) { _, _ in
                    requestAddressBarFocus()
                }
                .onChange(of: store.hasBlockingModalPresentation) { _, isPresented in
                    guard isPresented else { return }
                    clearTransientSidebarPresentation()
                }
                .onChange(of: addressBarFocused) { _, focused in
                    if !focused {
                        scheduleSidebarHoverDismissIfNeeded()
                    }
                }
                .onChange(of: selectedBrowserTab.state.preferredFocus) { _, preferredFocus in
                    if preferredFocus != .addressBar {
                        scheduleSidebarHoverDismissIfNeeded()
                    }
                }
                .onChange(of: isFocused) { _, focused in
                    guard focused else { return }
                    syncFocus(controller: controller, browserTab: selectedBrowserTab)
                }
                .onChange(of: paneState.isSidebarPinned) { _, isPinned in
                    guard !isPinned else {
                        cancelSidebarHoverDismiss()
                        cancelSidebarHoverProtection()
                        isSidebarHoverDismissProtected = false
                        isSidebarHoverLatched = true
                        return
                    }

                    scheduleSidebarHoverDismissIfNeeded()
                }
                .onDisappear {
                    cancelSidebarHoverDismiss()
                    cancelSidebarHoverProtection()
                    cancelRecentDownloadHighlight()
                    cancelSwipeIndicatorHide()
                    highlightedAddressSuggestionID = nil
                    swipeNavigationFeedback = nil
                    visibleWorkspaceDownloads = []
                    isDownloadsPopoverPresented = false
                }
            } else {
                VStack(spacing: 12) {
                    Text("No Workspace Browser Tabs")
                        .font(Fonts.primary(size: 16, weight: .bold))
                        .foregroundStyle(theme.text)

                    Button("Open Workspace Browser Tab") {
                        _ = store.openBrowserTabInPane(
                            tab.id,
                            url: BrowserDefaults.homePageURLString,
                            preferredFocus: .addressBar
                        )
                    }
                    .buttonStyle(.plain)
                    .font(Fonts.primary(size: 13))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(theme.bg2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(theme.border, lineWidth: 1)
                    )
                    .pointerCursor()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.bg)
            }
        }
    }

    @ViewBuilder
    private var swipeNavigationOverlay: some View {
        if let swipeNavigationFeedback {
            BrowserSwipeNavigationIndicator(feedback: swipeNavigationFeedback)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: swipeNavigationFeedback.direction == .previous ? .leading : .trailing
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var sidebarHoverBridge: some View {
        BrowserSidebarHoverRegion(
            onHoverChange: { isHovered in
                handleSidebarHotspotHoverChange(isHovered)
            },
            isEnabled: !store.hasBlockingModalPresentation,
            hotspotWidth: Layout.browserSidebarHotspotWidth,
            leadingEdgeInset: Layout.workspacePaddingH
        )
        .frame(width: Layout.browserSidebarHoverBridgeWidth)
        .frame(maxHeight: .infinity, alignment: .leading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .opacity(0.001)
        .zIndex(3)
    }

    @ViewBuilder
    private func browserSidebar(
        selectedBrowserTab: BrowserPaneTab,
        controller: any BrowserHostController,
        resolvedWorkspaceDownloads: [BrowserDownloadItem],
        activeDownloads: [BrowserDownloadItem]
    ) -> some View {
        if isSidebarExpanded {
            BrowserSidebarView(
                paneState: paneState,
                isPresented: true,
                isPinned: paneState.isSidebarPinned,
                onHoverChange: { isHovered in
                    handleSidebarPanelHoverChange(isHovered)
                },
                onSelectTab: { browserTabId in
                    dismissAddressBarFocus(for: selectedBrowserTab.id)
                    store.selectBrowserTab(browserTabId, in: tab.id)
                    store.setActiveTab(tab.id)
                },
                onTogglePin: { browserTabId in
                    dismissAddressBarFocus(for: selectedBrowserTab.id)
                    store.toggleBrowserTabPinned(browserTabId, in: tab.id)
                },
                onCloseTab: { browserTabId in
                    dismissAddressBarFocus(for: selectedBrowserTab.id)
                    store.closeBrowserTab(browserTabId, in: tab.id)
                }
            ) {
                sidebarHeader(
                    browserTab: selectedBrowserTab,
                    controller: controller,
                    workspaceDownloads: resolvedWorkspaceDownloads,
                    activeDownloads: activeDownloads
                )
            }
            .transition(
                .offset(x: -(Layout.browserSidebarWidth + Layout.browserSidebarFloatingInset))
                .combined(with: .opacity)
            )
        }
    }

    private func sidebarHeader(
        browserTab: BrowserPaneTab,
        controller: any BrowserHostController,
        workspaceDownloads: [BrowserDownloadItem],
        activeDownloads: [BrowserDownloadItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                sidebarActionButton(
                    systemName: paneState.isSidebarPinned ? "sidebar.left" : "sidebar.right",
                    accessibilityLabel: paneState.isSidebarPinned ? "Unpin Workspace Browser Sidebar" : "Pin Workspace Browser Sidebar"
                ) {
                    dismissAddressBarFocus(for: browserTab.id)
                    store.toggleBrowserSidebarPinned(for: tab.id)
                }

                Spacer(minLength: 0)

                sidebarActionButton(
                    systemName: "chevron.left",
                    isEnabled: controller.session.state.canGoBack,
                    accessibilityLabel: "Back"
                ) {
                    dismissAddressBarFocus(for: browserTab.id)
                    browserManager.goBack(tabId: browserTab.id)
                }

                sidebarActionButton(
                    systemName: "chevron.right",
                    isEnabled: controller.session.state.canGoForward,
                    accessibilityLabel: "Forward"
                ) {
                    dismissAddressBarFocus(for: browserTab.id)
                    browserManager.goForward(tabId: browserTab.id)
                }

                sidebarActionButton(
                    systemName: "arrow.clockwise",
                    accessibilityLabel: "Reload"
                ) {
                    dismissAddressBarFocus(for: browserTab.id)
                    browserManager.reload(tabId: browserTab.id)
                }

                downloadsButton(
                    workspaceDownloads: workspaceDownloads,
                    activeDownloads: activeDownloads
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            addressBarField(
                browserTab: browserTab,
                controller: controller
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func addressBarField(
        browserTab: BrowserPaneTab,
        controller: any BrowserHostController
    ) -> some View {
        BrowserAddressBarTextField(
            text: $addressText,
            isFocused: Binding(
                get: { addressBarFocused },
                set: { addressBarFocused = $0 }
            ),
            placeholder: "Enter URL",
            theme: theme,
            onSubmit: {
                submitAddressBar(controller: controller)
            },
            onEscape: {
                dismissAddressBarFocus(for: browserTab.id)
            },
            onMoveSelection: { delta in
                moveAddressSuggestionSelection(by: delta)
            },
            onActivate: {
                if store.activeTabId != tab.id {
                    store.setActiveTab(tab.id)
                }
                store.selectBrowserTab(browserTab.id, in: tab.id)
                store.setBrowserFocusTarget(.addressBar, for: browserTab.id, in: tab.id)
                activateAddressBarSuggestions()
            }
        )
            .frame(height: 16, alignment: .center)
            .padding(.top, addressBarFocused ? 1 : 0)
            .padding(.bottom, addressBarFocused ? -1 : 0)
            .padding(.leading, 12)
            .padding(.trailing, 72)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: Self.sidebarControlCornerRadius, style: .continuous)
                    .fill(theme.bg2)
            )
            .overlay(alignment: .trailing) {
                HStack(spacing: 4) {
                    Button {
                        dismissAddressBarFocus(for: browserTab.id)
                        _ = store.openBrowserTabInPane(
                            tab.id,
                            url: BrowserDefaults.homePageURLString,
                            preferredFocus: .addressBar
                        )
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.textDim)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                    .help("New Workspace Browser Tab")

                    Button {
                        dismissAddressBarFocus(for: browserTab.id)
                        browserManager.openInDefaultBrowser(tabId: browserTab.id)
                    } label: {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(theme.textDim)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                    .help("Open in default browser")
                }
                .padding(.trailing, 8)
            }
            .overlay(
                RoundedRectangle(cornerRadius: Self.sidebarControlCornerRadius + 1, style: .continuous)
                    .stroke(addressBarFocused ? theme.accent.opacity(0.75) : theme.border, lineWidth: 1)
                    .padding(-1)
            )
            .overlay(alignment: .topLeading) {
                addressBarSuggestionsOverlay(controller: controller)
            }
            .zIndex(isAddressBarSuggestionsPresented ? 4 : 0)
            .onChange(of: addressBarFocused) { _, focused in
                if focused {
                    store.setBrowserFocusTarget(.addressBar, for: browserTab.id, in: tab.id)
                    activateAddressBarSuggestions()
                } else {
                    clearAddressBarSuggestions()
                }
            }
            .onChange(of: addressText) {
                if shouldHighlightAddressBarSuggestions {
                    activateAddressBarSuggestions()
                }
                syncHighlightedAddressSuggestion()
            }
    }

    @ViewBuilder
    private func addressBarSuggestionsOverlay(
        controller: any BrowserHostController
    ) -> some View {
        let suggestions = addressBarSuggestions

        if !suggestions.isEmpty {
            BrowserAddressBarSuggestionsView(
                entries: suggestions,
                highlightedID: highlightedAddressSuggestionID,
                onSelect: { suggestion in
                    selectAddressSuggestion(suggestion, controller: controller)
                }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 44)
            .opacity(isAddressBarSuggestionsPresented ? 1 : 0)
            .allowsHitTesting(isAddressBarSuggestionsPresented)
            .accessibilityHidden(!isAddressBarSuggestionsPresented)
        }
    }

    private func downloadsButton(
        workspaceDownloads: [BrowserDownloadItem],
        activeDownloads: [BrowserDownloadItem]
    ) -> some View {
        let hasActiveDownloads = !activeDownloads.isEmpty
        let activeDownloadProgress = downloadProgress(for: activeDownloads)
        let isDownloadHighlighted = hasActiveDownloads || isRecentDownloadHighlighted
        let latestDownloadActivity = workspaceDownloads.first?.updatedAt
        let latestDownloadCompleted = workspaceDownloads.first.map { !$0.isInProgress && $0.isComplete } ?? false
        return Button {
            dismissAddressBarFocus(for: selectedBrowserTab?.id ?? activeDownloads.first?.browserTabId ?? "")
            isDownloadsPopoverPresented.toggle()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: Self.sidebarControlCornerRadius, style: .continuous)
                    .fill(downloadButtonBackgroundColor(
                        hasActiveDownloads: hasActiveDownloads,
                        isDownloadHighlighted: isDownloadHighlighted,
                        latestDownloadCompleted: latestDownloadCompleted
                    ))

                RoundedRectangle(cornerRadius: Self.sidebarControlCornerRadius, style: .continuous)
                    .stroke(downloadButtonBorderColor(
                        hasActiveDownloads: hasActiveDownloads,
                        isDownloadHighlighted: isDownloadHighlighted,
                        latestDownloadCompleted: latestDownloadCompleted
                    ), lineWidth: 1)

                if hasActiveDownloads {
                    Circle()
                        .stroke(theme.textDim.opacity(0.22), lineWidth: 2.4)
                        .padding(6)

                    DownloadProgressRing(
                        progress: activeDownloadProgress,
                        indeterminateAmount: Self.indeterminateDownloadProgress,
                        color: theme.accent
                    )
                    .padding(6)
                }

                Image(systemName: downloadButtonSymbolName(
                    hasActiveDownloads: hasActiveDownloads,
                    isRecentDownloadHighlighted: isRecentDownloadHighlighted,
                    latestDownloadCompleted: latestDownloadCompleted
                ))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(downloadButtonForegroundColor(
                    hasActiveDownloads: hasActiveDownloads,
                    isDownloadHighlighted: isDownloadHighlighted,
                    latestDownloadCompleted: latestDownloadCompleted
                ))
            }
            .frame(width: 32, height: 32)
            .contentShape(RoundedRectangle(cornerRadius: Self.sidebarControlCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .accessibilityLabel("Downloads")
        .help("Downloads")
        .popover(isPresented: $isDownloadsPopoverPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            BrowserDownloadsPopoverView(
                downloads: workspaceDownloads,
                onOpen: { download in
                    browserManager.openDownload(download)
                },
                onReveal: { download in
                    browserManager.revealDownload(download)
                },
                onClear: {
                    browserManager.clearDownloads(for: workspace.id)
                }
            )
            .padding(6)
        }
        .onAppear {
            updateRecentDownloadHighlight(for: latestDownloadActivity)
            updateDownloadActivityAnimation(isDownloadHighlighted: isDownloadHighlighted)
        }
        .onChange(of: hasActiveDownloads) { _, active in
            if active {
                cancelRecentDownloadHighlight()
                isRecentDownloadHighlighted = false
            }
            updateDownloadActivityAnimation(isDownloadHighlighted: isDownloadHighlighted)
        }
        .onChange(of: latestDownloadActivity) { _, newValue in
            updateRecentDownloadHighlight(for: newValue)
            updateDownloadActivityAnimation(
                isDownloadHighlighted: hasActiveDownloads || isRecentDownloadHighlighted
            )
        }
    }

    private func downloadProgress(for activeDownloads: [BrowserDownloadItem]) -> CGFloat? {
        let determinateDownloads = activeDownloads.compactMap { download -> CGFloat? in
            if let fraction = download.progressFraction {
                return CGFloat(fraction)
            }

            if download.percentComplete >= 0 {
                return CGFloat(download.percentComplete) / 100
            }

            return nil
        }

        guard !determinateDownloads.isEmpty else { return nil }
        let average = determinateDownloads.reduce(0, +) / CGFloat(determinateDownloads.count)
        return min(max(average, 0), 1)
    }

    private func sidebarActionButton(
        systemName: String,
        isEnabled: Bool = true,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: Self.sidebarControlCornerRadius, style: .continuous)
                    .fill(theme.bg2)

                RoundedRectangle(cornerRadius: Self.sidebarControlCornerRadius, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)

                Image(systemName: systemName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isEnabled ? theme.text : theme.textDim.opacity(0.7))
            }
            .frame(width: 32, height: 32)
            .contentShape(RoundedRectangle(cornerRadius: Self.sidebarControlCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
    }

    private func syncAddressText(from state: BrowserTabState) {
        addressText = state.urlString ?? ""
        clearAddressBarSuggestions()
    }

    private func syncHighlightedAddressSuggestion() {
        guard addressBarSuggestions.contains(where: { $0.id == highlightedAddressSuggestionID }) else {
            highlightedAddressSuggestionID = nil
            return
        }
    }

    private func moveAddressSuggestionSelection(
        by delta: Int
    ) {
        let suggestions = addressBarSuggestions
        guard !suggestions.isEmpty else { return }

        activateAddressBarSuggestions()

        if let currentHighlightedID = highlightedAddressSuggestionID,
           let currentIndex = suggestions.firstIndex(where: { $0.id == currentHighlightedID }) {
            let count = suggestions.count
            let nextIndex = (currentIndex + delta + count) % count
            highlightedAddressSuggestionID = suggestions[nextIndex].id
            return
        }

        highlightedAddressSuggestionID = delta >= 0 ? suggestions.first?.id : suggestions.last?.id
    }

    private func submitAddressBar(controller: any BrowserHostController) {
        if let highlightedAddressSuggestionID,
           let suggestion = addressBarSuggestions.first(where: { $0.id == highlightedAddressSuggestionID }) {
            selectAddressSuggestion(suggestion, controller: controller)
            return
        }

        clearAddressBarSuggestions()
        controller.navigate(to: addressText)
    }

    private func selectAddressSuggestion(
        _ suggestion: BrowserHistoryEntry,
        controller: any BrowserHostController
    ) {
        clearAddressBarSuggestions()
        addressText = suggestion.urlString
        controller.navigate(to: suggestion.urlString)
    }

    private func clearTransientSidebarPresentation() {
        isSidebarHotspotHovered = false
        isSidebarPanelHovered = false
        cancelSidebarHoverDismiss()
        cancelSidebarHoverProtection()
        isSidebarHoverDismissProtected = false
        if !paneState.isSidebarPinned {
            isSidebarHoverLatched = false
        }
    }

    private func handleSidebarHotspotHoverChange(_ isHovered: Bool) {
        guard !store.hasBlockingModalPresentation else {
            clearTransientSidebarPresentation()
            return
        }
        isSidebarHotspotHovered = isHovered

        if isHovered {
            latchSidebarHover(protectDismissal: true)
        } else {
            scheduleSidebarHoverDismissIfNeeded()
        }
    }

    private func handleSidebarPanelHoverChange(_ isHovered: Bool) {
        guard !store.hasBlockingModalPresentation else {
            clearTransientSidebarPresentation()
            return
        }
        isSidebarPanelHovered = isHovered

        if isHovered {
            latchSidebarHover()
        } else {
            scheduleSidebarHoverDismissIfNeeded()
        }
    }

    private func latchSidebarHover(protectDismissal: Bool = false) {
        guard !store.hasBlockingModalPresentation else { return }
        cancelSidebarHoverDismiss()
        isSidebarHoverLatched = true

        if protectDismissal {
            protectSidebarHoverDismissal()
        }
    }

    private func scheduleSidebarHoverDismissIfNeeded() {
        cancelSidebarHoverDismiss()

        if store.hasBlockingModalPresentation {
            clearTransientSidebarPresentation()
            return
        }

        guard !paneState.isSidebarPinned,
              !isSidebarPanelHovered,
              !isSidebarHoverDismissProtected else {
            return
        }

        let workItem = DispatchWorkItem {
            isSidebarHoverLatched = false
        }
        sidebarHoverDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.sidebarHoverDismissDelay,
            execute: workItem
        )
    }

    private func cancelSidebarHoverDismiss() {
        sidebarHoverDismissWorkItem?.cancel()
        sidebarHoverDismissWorkItem = nil
    }

    private func protectSidebarHoverDismissal() {
        cancelSidebarHoverProtection()
        isSidebarHoverDismissProtected = true

        let workItem = DispatchWorkItem {
            isSidebarHoverDismissProtected = false
            scheduleSidebarHoverDismissIfNeeded()
        }
        sidebarHoverProtectionWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.sidebarHoverKeepOpenDuration,
            execute: workItem
        )
    }

    private func cancelSidebarHoverProtection() {
        sidebarHoverProtectionWorkItem?.cancel()
        sidebarHoverProtectionWorkItem = nil
    }

    private func syncFocus(
        controller: any BrowserHostController,
        browserTab: BrowserPaneTab
    ) {
        if browserTab.state.preferredFocus == .addressBar {
            requestAddressBarFocus()
        } else {
            addressBarFocused = false
            browserManager.focusWebView(tabId: browserTab.id)
        }
    }

    private func dismissAddressBarFocus(for browserTabId: String) {
        clearAddressBarSuggestions()
        addressBarFocused = false

        guard !browserTabId.isEmpty else { return }
        store.setBrowserFocusTarget(.webView, for: browserTabId, in: tab.id)
        browserManager.focusWebView(tabId: browserTabId)
    }

    private func requestAddressBarFocus() {
        guard !store.hasBlockingModalPresentation else { return }
        activateAddressBarSuggestions()
        if !paneState.isSidebarPinned {
            latchSidebarHover(protectDismissal: true)
        }
        DispatchQueue.main.async {
            DispatchQueue.main.async {
                addressBarFocused = true
            }
        }
    }

    private func activateAddressBarSuggestions() {
        isAddressBarSuggestionsActive = true
    }

    private func clearAddressBarSuggestions() {
        highlightedAddressSuggestionID = nil
        isAddressBarSuggestionsActive = false
    }

    private func updateDownloadActivityAnimation(isDownloadHighlighted: Bool) {
        isDownloadActivityAnimating = isDownloadHighlighted && !reduceMotion
    }

    private func updateRecentDownloadHighlight(for latestDownloadActivity: Date?) {
        guard let latestDownloadActivity else {
            cancelRecentDownloadHighlight()
            isRecentDownloadHighlighted = false
            return
        }

        let age = Date().timeIntervalSince(latestDownloadActivity)
        guard age < Self.recentDownloadHighlightDuration else {
            cancelRecentDownloadHighlight()
            isRecentDownloadHighlighted = false
            return
        }

        cancelRecentDownloadHighlight()
        isRecentDownloadHighlighted = true

        let workItem = DispatchWorkItem {
            isRecentDownloadHighlighted = false
            updateDownloadActivityAnimation(isDownloadHighlighted: false)
        }
        recentDownloadHighlightWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + (Self.recentDownloadHighlightDuration - age),
            execute: workItem
        )
    }

    private func cancelRecentDownloadHighlight() {
        recentDownloadHighlightWorkItem?.cancel()
        recentDownloadHighlightWorkItem = nil
    }

    private func updateSwipeIndicator(_ feedback: BrowserSwipeNavigationFeedback?) {
        if let feedback {
            cancelSwipeIndicatorHide()
            let shouldAnimate = swipeNavigationFeedback == nil
                || swipeNavigationFeedback?.direction != feedback.direction
                || (feedback.isCommitted && swipeNavigationFeedback?.isCommitted != true)

            if shouldAnimate {
                withAnimation(Self.sidebarTransition) {
                    swipeNavigationFeedback = feedback
                }
            } else {
                swipeNavigationFeedback = feedback
            }

            if feedback.isCommitted {
                let workItem = DispatchWorkItem {
                    animateSwipeIndicatorDismissal(forCommit: true)
                }
                swipeIndicatorHideWorkItem = workItem
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + Self.swipeIndicatorHideDelay,
                    execute: workItem
                )
            }
            return
        }

        guard swipeNavigationFeedback?.isCommitted != true else { return }
        clearSwipeIndicator()
    }

    private func clearSwipeIndicator() {
        cancelSwipeIndicatorHide()
        animateSwipeIndicatorDismissal(forCommit: false)
    }

    private func cancelSwipeIndicatorHide() {
        swipeIndicatorHideWorkItem?.cancel()
        swipeIndicatorHideWorkItem = nil
    }

    private func animateSwipeIndicatorDismissal(forCommit: Bool) {
        guard let currentFeedback = swipeNavigationFeedback else { return }

        let dismissedFeedback = BrowserSwipeNavigationFeedback(
            direction: currentFeedback.direction,
            progress: forCommit ? max(currentFeedback.progress, 1) + 0.12 : 0,
            isArmed: currentFeedback.isArmed,
            isCommitted: currentFeedback.isCommitted
        )

        withAnimation(.easeOut(duration: Self.swipeIndicatorExitDuration)) {
            swipeNavigationFeedback = dismissedFeedback
        }

        let workItem = DispatchWorkItem {
            swipeNavigationFeedback = nil
        }
        swipeIndicatorHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.swipeIndicatorExitDuration,
            execute: workItem
        )
    }

    private func syncVisibleDownloads() {
        visibleWorkspaceDownloads = browserManager.downloads(for: workspace.id)
    }

    private func downloadButtonBackgroundColor(
        hasActiveDownloads: Bool,
        isDownloadHighlighted: Bool,
        latestDownloadCompleted: Bool
    ) -> Color {
        if hasActiveDownloads {
            return theme.bg2
        }

        if isDownloadHighlighted && latestDownloadCompleted {
            return theme.accent.opacity(0.92)
        }

        if isDownloadHighlighted {
            return theme.accent.opacity(0.18)
        }

        return theme.bg2
    }

    private func downloadButtonBorderColor(
        hasActiveDownloads: Bool,
        isDownloadHighlighted: Bool,
        latestDownloadCompleted: Bool
    ) -> Color {
        if hasActiveDownloads {
            return theme.accent.opacity(0.95)
        }

        if isDownloadHighlighted && latestDownloadCompleted {
            return theme.accent.opacity(0.95)
        }

        if isDownloadHighlighted {
            return theme.accent.opacity(0.65)
        }

        return theme.border
    }

    private func downloadButtonForegroundColor(
        hasActiveDownloads: Bool,
        isDownloadHighlighted: Bool,
        latestDownloadCompleted: Bool
    ) -> Color {
        if hasActiveDownloads {
            return theme.accent
        }

        if isDownloadHighlighted && latestDownloadCompleted {
            return theme.bg
        }

        if isDownloadHighlighted {
            return theme.accent
        }

        return theme.text
    }

    private func downloadButtonSymbolName(
        hasActiveDownloads: Bool,
        isRecentDownloadHighlighted: Bool,
        latestDownloadCompleted: Bool
    ) -> String {
        if hasActiveDownloads {
            return "arrow.down"
        }

        if isRecentDownloadHighlighted && latestDownloadCompleted {
            return "checkmark"
        }

        return "arrow.down.circle"
    }
}

private struct BrowserAddressBarTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    let placeholder: String
    let theme: Theme
    let onSubmit: () -> Void
    let onEscape: () -> Void
    let onMoveSelection: (Int) -> Void
    let onActivate: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField(string: text)
        textField.delegate = context.coordinator
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.isAutomaticTextCompletionEnabled = false
        textField.font = NSFont(name: "MesloLGSNFM-Regular", size: 12) ?? .monospacedSystemFont(ofSize: 12, weight: .regular)
        textField.textColor = NSColor(theme.text)
        textField.placeholderString = placeholder
        textField.lineBreakMode = .byTruncatingTail
        textField.maximumNumberOfLines = 1
        textField.cell?.wraps = false
        textField.cell?.isScrollable = true
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.parent = self

        if textField.stringValue != text {
            textField.stringValue = text
        }

        textField.placeholderString = placeholder
        textField.textColor = NSColor(theme.text)
        textField.font = NSFont(name: "MesloLGSNFM-Regular", size: 12) ?? .monospacedSystemFont(ofSize: 12, weight: .regular)

        DispatchQueue.main.async {
            guard textField.window != nil else { return }

            let currentEditor = textField.currentEditor()
            if isFocused {
                if currentEditor == nil {
                    textField.window?.makeFirstResponder(textField)
                }
            } else if currentEditor != nil {
                textField.window?.makeFirstResponder(nil)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate, NSControlTextEditingDelegate {
        var parent: BrowserAddressBarTextField

        init(parent: BrowserAddressBarTextField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            if !parent.isFocused {
                parent.isFocused = true
            }
            parent.onActivate()
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            if parent.text != textField.stringValue {
                parent.text = textField.stringValue
            }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            if parent.isFocused {
                parent.isFocused = false
            }
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                parent.onMoveSelection(-1)
                return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onMoveSelection(1)
                return true
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onEscape()
                return true
            default:
                return false
            }
        }
    }
}

private struct BrowserSwipeNavigationIndicator: View {
    @Environment(\.theme) private var theme

    let feedback: BrowserSwipeNavigationFeedback

    private let indicatorSize: CGFloat = 58
    private let visibleInset: CGFloat = 12
    private let hiddenEdgeOffset: CGFloat = 26

    private var symbolName: String {
        feedback.direction == .previous ? "chevron.left" : "chevron.right"
    }

    private var edgeOffset: CGFloat {
        let travel = hiddenEdgeOffset + visibleInset
        let resolved = (-hiddenEdgeOffset) + (feedback.progress * travel)
        return feedback.direction == .previous ? resolved : -resolved
    }

    private var indicatorOpacity: CGFloat {
        let clampedProgress = min(max(feedback.progress, 0), 1)
        let baseOpacity = clampedProgress
        if feedback.progress > 1 {
            let dismissalFade = max(0, 1 - ((feedback.progress - 1) / 0.12))
            return baseOpacity * dismissalFade
        }
        return baseOpacity
    }

    private var indicatorScale: CGFloat {
        let clampedProgress = min(max(feedback.progress, 0), 1)
        return 0.94 + (clampedProgress * 0.06)
    }

    private var backgroundOpacity: CGFloat {
        (feedback.isArmed || feedback.isCommitted) ? 0.98 : 0.94
    }

    private var borderColor: Color {
        (feedback.isArmed || feedback.isCommitted) ? theme.accent.opacity(0.9) : theme.border.opacity(0.95)
    }

    private var symbolColor: Color {
        (feedback.isArmed || feedback.isCommitted) ? theme.accent : theme.text
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(theme.bg.opacity(backgroundOpacity))

            Circle()
                .stroke(borderColor, lineWidth: (feedback.isArmed || feedback.isCommitted) ? 2 : 1)

            Image(systemName: symbolName)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(symbolColor)
        }
        .frame(width: indicatorSize, height: indicatorSize)
        .shadow(color: Color.black.opacity(0.18), radius: 14, y: 6)
        .opacity(indicatorOpacity)
        .scaleEffect(indicatorScale)
        .offset(x: edgeOffset)
    }
}
