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

    private func resolveController() -> any BrowserHostController {
        browserManager.controller(
            for: tab.id,
            projectId: project.id,
            initialState: tab.browserState ?? .blank
        ) { state in
            DispatchQueue.main.async {
                store.updateBrowserState(state, for: tab.id)
            }
        }
    }

    var body: some View {
        let controller = resolveController()

        VStack(spacing: 0) {
            chrome(controller: controller)
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
            syncAddressTextFromState(controller: controller)
            if isFocused, controller.session.state.preferredFocus == .addressBar {
                requestAddressBarFocus()
            } else if isFocused {
                browserManager.focusWebView(tabId: tab.id)
            }
        }
        .onChange(of: controller.session.state.urlString) { _, _ in
            if !addressBarFocused {
                syncAddressTextFromState(controller: controller)
            }
        }
        .onChange(of: controller.session.addressBarFocusRequestID) { _, _ in
            requestAddressBarFocus()
        }
        .onChange(of: isFocused) { _, focused in
            guard focused else { return }
            if controller.session.state.preferredFocus == .addressBar {
                requestAddressBarFocus()
            } else {
                browserManager.focusWebView(tabId: tab.id)
            }
        }
    }

    private func chrome(controller: any BrowserHostController) -> some View {
        HStack(spacing: 10) {
            navigationButton(systemName: "chevron.left", isEnabled: controller.session.state.canGoBack) {
                browserManager.goBack(tabId: tab.id)
            }

            navigationButton(systemName: "chevron.right", isEnabled: controller.session.state.canGoForward) {
                browserManager.goForward(tabId: tab.id)
            }

            navigationButton(systemName: controller.session.state.isLoading ? "xmark" : "arrow.clockwise", isEnabled: true) {
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

    private func syncAddressTextFromState(controller: any BrowserHostController) {
        addressText = controller.session.state.urlString ?? ""
    }

    private func requestAddressBarFocus() {
        addressBarFocused = false
        DispatchQueue.main.async {
            addressBarFocused = true
        }
    }
}
