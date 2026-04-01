import SwiftUI

struct BrowserView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let tab: AppTab
    let project: Project
    let browserManager: BrowserManager
    let isFocused: Bool

    @State private var addressText = ""
    @FocusState private var addressBarFocused: Bool

    private var browserState: BrowserTabState {
        tab.browserState ?? .blank
    }

    private var controller: BrowserController {
        browserManager.controller(for: tab.id, initialState: browserState) { state in
            store.updateBrowserState(state, for: tab.id)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            chrome
            Divider()
                .overlay(theme.border)
            BrowserContainerView(
                tabId: tab.id,
                projectId: project.id,
                controller: controller
            )
        }
        .background(theme.bg)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onAppear {
            syncAddressTextFromState()
            if isFocused, controller.state.preferredFocus == .addressBar {
                requestAddressBarFocus()
            }
        }
        .onChange(of: controller.state.urlString) { _, _ in
            if !addressBarFocused {
                syncAddressTextFromState()
            }
        }
        .onChange(of: controller.addressBarFocusRequestID) { _, _ in
            requestAddressBarFocus()
        }
        .onChange(of: isFocused) { _, focused in
            guard focused else { return }
            if controller.state.preferredFocus == .addressBar {
                requestAddressBarFocus()
            } else {
                browserManager.focusWebView(tabId: tab.id)
            }
        }
    }

    private var chrome: some View {
        HStack(spacing: 10) {
            navigationButton(systemName: "chevron.left", isEnabled: controller.state.canGoBack) {
                browserManager.goBack(tabId: tab.id)
            }

            navigationButton(systemName: "chevron.right", isEnabled: controller.state.canGoForward) {
                browserManager.goForward(tabId: tab.id)
            }

            navigationButton(systemName: controller.state.isLoading ? "xmark" : "arrow.clockwise", isEnabled: true) {
                browserManager.reload(tabId: tab.id)
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
                    store.setBrowserFocusTarget(.addressBar, for: tab.id)
                }
                .onChange(of: addressBarFocused) { _, focused in
                    guard focused else { return }
                    store.setBrowserFocusTarget(.addressBar, for: tab.id)
                }

            Button {
                browserManager.openInDefaultBrowser(tabId: tab.id)
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

    private func syncAddressTextFromState() {
        addressText = controller.state.urlString ?? ""
    }

    private func requestAddressBarFocus() {
        addressBarFocused = false
        DispatchQueue.main.async {
            addressBarFocused = true
        }
    }
}
