import SwiftUI

struct BrowserView: View {
    private static let sidebarTransition = Animation.snappy(duration: 0.24, extraBounce: 0)
    private static let sidebarHoverDismissDelay: TimeInterval = 0.18

    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let tab: AppTab
    let project: Project
    let browserManager: BrowserManager
    let isFocused: Bool

    @State private var addressText = ""
    @State private var isSidebarHotspotHovered = false
    @State private var isSidebarPanelHovered = false
    @State private var isSidebarHoverLatched = false
    @FocusState private var addressBarFocused: Bool

    @State private var sidebarHoverDismissWorkItem: DispatchWorkItem?

    private var paneState: BrowserPaneState {
        tab.browserState ?? .empty
    }

    private var selectedBrowserTab: BrowserPaneTab? {
        paneState.selectedTab
    }

    private var sidebarContentInset: CGFloat {
        paneState.isSidebarPinned ? Layout.browserSidebarWidth : 0
    }

    private var hoverRegionWidth: CGFloat {
        isSidebarExpanded ? Layout.browserSidebarHoverBridgeWidth : Layout.browserSidebarHotspotWidth
    }

    private var isSidebarExpanded: Bool {
        paneState.isSidebarPinned
            || isSidebarHoverLatched
            || addressBarFocused
            || selectedBrowserTab?.state.preferredFocus == .addressBar
    }

    private func resolveController(for browserTab: BrowserPaneTab) -> any BrowserHostController {
        browserManager.controller(
            for: browserTab.id,
            projectId: project.id,
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
                let controller = resolveController(for: selectedBrowserTab)
                ZStack(alignment: .leading) {
                    BrowserContainerView(
                        paneTabId: tab.id,
                        browserTabId: selectedBrowserTab.id,
                        controller: controller
                    )
                    .padding(.leading, sidebarContentInset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(Self.sidebarTransition, value: sidebarContentInset)

                    if !paneState.isSidebarPinned {
                        BrowserSidebarHoverRegion { isHovered in
                            handleSidebarHotspotHoverChange(isHovered)
                        }
                        .frame(width: hoverRegionWidth)
                        .frame(maxHeight: .infinity, alignment: .leading)
                        .zIndex(1)
                    }

                    BrowserSidebarView(
                        paneState: paneState,
                        isPresented: isSidebarExpanded,
                        isPinned: paneState.isSidebarPinned,
                        onHoverChange: { isHovered in
                            handleSidebarPanelHoverChange(isHovered)
                        },
                        onSelectTab: { browserTabId in
                            store.selectBrowserTab(browserTabId, in: tab.id)
                            store.setActiveTab(tab.id)
                        },
                        onCloseTab: { browserTabId in
                            store.closeBrowserTab(browserTabId, in: tab.id)
                        }
                    ) {
                        sidebarHeader(
                            browserTab: selectedBrowserTab,
                            controller: controller
                        )
                    }
                }
                .background(theme.bg)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .animation(Self.sidebarTransition, value: paneState.isSidebarPinned)
                .onAppear {
                    syncAddressText(from: selectedBrowserTab.state)
                    if isFocused {
                        syncFocus(controller: controller, browserTab: selectedBrowserTab)
                    }
                }
                .onChange(of: selectedBrowserTab.id) { _, _ in
                    syncAddressText(from: selectedBrowserTab.state)
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
                .onChange(of: addressBarFocused) { _, focused in
                    if focused {
                        latchSidebarHover()
                    } else {
                        scheduleSidebarHoverDismissIfNeeded()
                    }
                }
                .onChange(of: selectedBrowserTab.state.preferredFocus) { _, preferredFocus in
                    if preferredFocus == .addressBar {
                        latchSidebarHover()
                    } else {
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
                        isSidebarHoverLatched = true
                        return
                    }

                    if !addressBarFocused,
                       selectedBrowserTab.state.preferredFocus != .addressBar {
                        scheduleSidebarHoverDismissIfNeeded()
                    }
                }
                .onDisappear {
                    cancelSidebarHoverDismiss()
                }
            } else {
                VStack(spacing: 12) {
                    Text("No Browser Tabs")
                        .font(Fonts.primary(size: 16, weight: .bold))
                        .foregroundStyle(theme.text)

                    Button("Open Browser Tab") {
                        _ = store.openBrowserTabInPane(tab.id, url: BrowserDefaults.homePageURLString)
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

    private func sidebarHeader(
        browserTab: BrowserPaneTab,
        controller: any BrowserHostController
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Enter URL", text: $addressText)
                .textFieldStyle(.plain)
                .font(Fonts.primary(size: 12))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(theme.bg2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(addressBarFocused ? theme.accent.opacity(0.75) : theme.border, lineWidth: 1)
                )
                .focused($addressBarFocused)
                .onSubmit {
                    controller.navigate(to: addressText)
                }
                .onTapGesture {
                    if store.activeTabId != tab.id {
                        store.setActiveTab(tab.id)
                    }
                    store.selectBrowserTab(browserTab.id, in: tab.id)
                    store.setBrowserFocusTarget(.addressBar, for: browserTab.id, in: tab.id)
                }
                .onChange(of: addressBarFocused) { _, focused in
                    guard focused else { return }
                    store.setBrowserFocusTarget(.addressBar, for: browserTab.id, in: tab.id)
                }

            HStack(spacing: 8) {
                sidebarActionButton(
                    systemName: "plus",
                    accessibilityLabel: "New Browser Tab"
                ) {
                    _ = store.openBrowserTabInPane(tab.id, url: BrowserDefaults.homePageURLString)
                }

                sidebarActionButton(
                    systemName: paneState.isSidebarPinned ? "sidebar.left" : "sidebar.right",
                    accessibilityLabel: paneState.isSidebarPinned ? "Unpin Browser Sidebar" : "Pin Browser Sidebar"
                ) {
                    store.toggleBrowserSidebarPinned(for: tab.id)
                }

                sidebarActionButton(
                    systemName: "chevron.left",
                    isEnabled: controller.session.state.canGoBack,
                    accessibilityLabel: "Back"
                ) {
                    browserManager.goBack(tabId: browserTab.id)
                }

                sidebarActionButton(
                    systemName: "chevron.right",
                    isEnabled: controller.session.state.canGoForward,
                    accessibilityLabel: "Forward"
                ) {
                    browserManager.goForward(tabId: browserTab.id)
                }

                sidebarActionButton(
                    systemName: "arrow.clockwise",
                    accessibilityLabel: "Reload"
                ) {
                    browserManager.reload(tabId: browserTab.id)
                }

                sidebarActionButton(
                    systemName: "safari",
                    accessibilityLabel: "Open in default browser"
                ) {
                    browserManager.openInDefaultBrowser(tabId: browserTab.id)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sidebarActionButton(
        systemName: String,
        isEnabled: Bool = true,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isEnabled ? theme.text : theme.textDim.opacity(0.7))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.bg2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
        .pointerCursor()
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
    }

    private func syncAddressText(from state: BrowserTabState) {
        addressText = state.urlString ?? ""
    }

    private func handleSidebarHotspotHoverChange(_ isHovered: Bool) {
        isSidebarHotspotHovered = isHovered

        if isHovered {
            latchSidebarHover()
        } else {
            scheduleSidebarHoverDismissIfNeeded()
        }
    }

    private func handleSidebarPanelHoverChange(_ isHovered: Bool) {
        isSidebarPanelHovered = isHovered

        if isHovered {
            latchSidebarHover()
        } else {
            scheduleSidebarHoverDismissIfNeeded()
        }
    }

    private func latchSidebarHover() {
        cancelSidebarHoverDismiss()
        isSidebarHoverLatched = true
    }

    private func scheduleSidebarHoverDismissIfNeeded() {
        cancelSidebarHoverDismiss()

        guard !paneState.isSidebarPinned,
              !isSidebarHotspotHovered,
              !isSidebarPanelHovered,
              !addressBarFocused,
              selectedBrowserTab?.state.preferredFocus != .addressBar else {
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

    private func requestAddressBarFocus() {
        addressBarFocused = false
        DispatchQueue.main.async {
            addressBarFocused = true
        }
    }
}
