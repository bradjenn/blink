import AppKit
import Foundation

@MainActor
final class ChromiumBrowserController: NSObject, BrowserHostController {
    let tabId: String
    let projectId: String
    let session: BrowserSessionModel
    let host: BlinkChromiumBrowserHost

    var onInteraction: (() -> Void)?
    var onOpenNewTabRequest: ((URL) -> Void)?
    var hostView: NSView { host.hostView }

    private var onStateChange: ((BrowserTabState) -> Void)?

    private var state: BrowserTabState {
        get { session.state }
        set { session.state = newValue }
    }

    private var addressBarFocusRequestID: Int {
        get { session.addressBarFocusRequestID }
        set { session.addressBarFocusRequestID = newValue }
    }

    init(
        tabId: String,
        projectId: String,
        initialState: BrowserTabState,
        onStateChange: @escaping (BrowserTabState) -> Void
    ) {
        self.tabId = tabId
        self.projectId = projectId
        self.session = BrowserSessionModel(state: initialState)
        self.onStateChange = onStateChange
        self.host = BlinkChromiumBrowserHost(
            tabIdentifier: tabId,
            projectIdentifier: projectId,
            initialURLString: initialState.urlString
        )

        super.init()

        host.delegate = self
    }

    func update(
        initialState: BrowserTabState,
        onStateChange: @escaping (BrowserTabState) -> Void
    ) {
        self.onStateChange = onStateChange

        if state.preferredFocus != initialState.preferredFocus {
            state.preferredFocus = initialState.preferredFocus
            if initialState.preferredFocus == .addressBar {
                addressBarFocusRequestID += 1
            }
        }

        let requestedURLString = normalizedURLString(initialState.urlString)
        let currentURLString = normalizedURLString(state.urlString)
        if let requestedURLString,
           requestedURLString != currentURLString {
            state.urlString = requestedURLString
            state.title = nil
            state.isLoading = true
            host.loadURLString(requestedURLString)
            return
        }

        refreshState(from: host.snapshot)
    }

    func navigate(to rawValue: String) {
        guard let url = BrowserURLResolver.resolve(rawValue) else { return }
        state.urlString = url.absoluteString
        state.title = nil
        state.isLoading = true
        state.preferredFocus = .webView
        host.loadURLString(url.absoluteString)
        publishState()
    }

    func focusWebView() {
        let focusChanged = state.preferredFocus != .webView
        state.preferredFocus = .webView
        host.focusBrowserView()
        if focusChanged {
            publishState()
        }
    }

    func focusAddressBar() {
        let focusChanged = state.preferredFocus != .addressBar
        if focusChanged {
            state.preferredFocus = .addressBar
        }
        addressBarFocusRequestID += 1
        if focusChanged {
            publishState()
        }
    }

    func goBack() {
        host.goBack()
    }

    func goForward() {
        host.goForward()
    }

    func reload() {
        if host.snapshot?.urlString == nil, let urlString = state.urlString {
            navigate(to: urlString)
            return
        }

        host.reload()
    }

    func openInDefaultBrowser() {
        guard let urlString = host.snapshot?.urlString ?? state.urlString,
              let url = BrowserURLResolver.resolve(urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func refreshState(from snapshot: BlinkChromiumBrowserStateSnapshot?) {
        let snapshotURLString = normalizedURLString(snapshot?.urlString)
        let nextState = BrowserTabState(
            urlString: mergedURLString(snapshotURLString),
            title: sanitizedTitle(snapshot?.title) ?? state.title,
            canGoBack: snapshot?.canGoBack ?? state.canGoBack,
            canGoForward: snapshot?.canGoForward ?? state.canGoForward,
            isLoading: snapshot?.isLoading ?? state.isLoading,
            preferredFocus: state.preferredFocus
        )

        guard nextState != state else { return }
        state = nextState
        publishState()
    }

    private func publishState() {
        onStateChange?(state)
    }

    private func sanitizedTitle(_ title: String?) -> String? {
        guard let title else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedURLString(_ value: String?) -> String? {
        guard let value else { return nil }
        return BrowserURLResolver.resolve(value)?.absoluteString ?? value
    }

    private func mergedURLString(_ snapshotURLString: String?) -> String? {
        guard let snapshotURLString else { return state.urlString }

        if snapshotURLString == "about:blank",
           state.isLoading,
           let currentURLString = state.urlString,
           currentURLString != "about:blank" {
            return currentURLString
        }

        return snapshotURLString
    }

    private func handleHostInteraction() {
        let focusChanged = state.preferredFocus != .webView
        state.preferredFocus = .webView
        onInteraction?()
        if focusChanged {
            publishState()
        }
    }

    private func handleHostUpdate(_ snapshot: BlinkChromiumBrowserStateSnapshot) {
        refreshState(from: snapshot)
    }

    private func handleOpenNewTabRequest(urlString: String?) {
        let target = (urlString?.isEmpty == false ? urlString : nil) ?? "about:blank"
        guard let url = BrowserURLResolver.resolve(target) else { return }
        onOpenNewTabRequest?(url)
    }
}

extension ChromiumBrowserController: BlinkChromiumBrowserHostDelegate {
    nonisolated func chromiumBrowserHostDidReceiveInteraction(_ host: BlinkChromiumBrowserHost) {
        Task { @MainActor [weak self] in
            self?.handleHostInteraction()
        }
    }

    nonisolated func chromiumBrowserHost(
        _ host: BlinkChromiumBrowserHost,
        didUpdate snapshot: BlinkChromiumBrowserStateSnapshot
    ) {
        Task { @MainActor [weak self] in
            self?.handleHostUpdate(snapshot)
        }
    }

    nonisolated func chromiumBrowserHost(
        _ host: BlinkChromiumBrowserHost,
        didRequestOpenNewTabWithURLString urlString: String?
    ) {
        Task { @MainActor [weak self] in
            self?.handleOpenNewTabRequest(urlString: urlString)
        }
    }
}
