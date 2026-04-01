import SwiftUI

struct BrowserView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let tab: AppTab
    let project: Project
    let browserManager: BrowserManager
    let isFocused: Bool

    @State private var addressText = ""
    @State private var isSidebarHovered = false
    @FocusState private var addressBarFocused: Bool

    private var paneState: BrowserPaneState {
        tab.browserState ?? .empty
    }

    private var selectedBrowserTab: BrowserPaneTab? {
        paneState.selectedTab
    }

    private var isSidebarExpanded: Bool {
        paneState.isSidebarPinned || isSidebarHovered
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
                HStack(spacing: 0) {
                    BrowserSidebarView(
                        paneState: paneState,
                        expanded: isSidebarExpanded,
                        onHoverChange: { isSidebarHovered = $0 },
                        onTogglePinned: { store.toggleBrowserSidebarPinned(for: tab.id) },
                        onNewTab: { _ = store.openBrowserTabInPane(tab.id, url: BrowserDefaults.homePageURLString) },
                        onSelectTab: { browserTabId in
                            store.selectBrowserTab(browserTabId, in: tab.id)
                            store.setActiveTab(tab.id)
                        },
                        onCloseTab: { browserTabId in
                            store.closeBrowserTab(browserTabId, in: tab.id)
                        }
                    )

                    Divider()
                        .overlay(theme.border)

                    VStack(spacing: 0) {
                        chrome(
                            browserTab: selectedBrowserTab,
                            controller: controller
                        )
                        Divider()
                            .overlay(theme.border)
                        BrowserContainerView(
                            paneTabId: tab.id,
                            browserTabId: selectedBrowserTab.id,
                            controller: controller
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(theme.bg)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .onAppear {
                    syncAddressText(from: selectedBrowserTab.state)
                    syncFocus(controller: controller, browserTab: selectedBrowserTab)
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
                .onChange(of: isFocused) { _, focused in
                    guard focused else { return }
                    syncFocus(controller: controller, browserTab: selectedBrowserTab)
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

    private func chrome(
        browserTab: BrowserPaneTab,
        controller: any BrowserHostController
    ) -> some View {
        HStack(spacing: 10) {
            navigationButton(systemName: "chevron.left", isEnabled: controller.session.state.canGoBack) {
                browserManager.goBack(tabId: browserTab.id)
            }

            navigationButton(systemName: "chevron.right", isEnabled: controller.session.state.canGoForward) {
                browserManager.goForward(tabId: browserTab.id)
            }

            navigationButton(systemName: controller.session.state.isLoading ? "xmark" : "arrow.clockwise", isEnabled: true) {
                browserManager.reload(tabId: browserTab.id)
            }

            TextField("Enter URL", text: $addressText)
                .textFieldStyle(.plain)
                .font(Fonts.primary(size: 12))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(theme.bg2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
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

            Button {
                browserManager.openInDefaultBrowser(tabId: browserTab.id)
            } label: {
                Image(systemName: "safari")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.text)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.bg2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            )
            .pointerCursor()
            .help("Open in default browser")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(theme.bg)
    }

    private func navigationButton(
        systemName: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isEnabled ? theme.text : theme.textDim.opacity(0.7))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.bg2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
        .pointerCursor()
        .disabled(!isEnabled)
    }

    private func syncAddressText(from state: BrowserTabState) {
        addressText = state.urlString ?? ""
    }

    private func syncFocus(
        controller: any BrowserHostController,
        browserTab: BrowserPaneTab
    ) {
        if browserTab.state.preferredFocus == .addressBar {
            requestAddressBarFocus()
        } else {
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
