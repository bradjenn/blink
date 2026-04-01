import AppKit
import Foundation
import Observation
import WebKit

@MainActor
final class BlinkBrowserWebView: WKWebView {
    var onInteraction: (() -> Void)?
    var suppressNextInteraction = false

    private func notifyInteractionIfNeeded() {
        if suppressNextInteraction {
            suppressNextInteraction = false
            return
        }
        onInteraction?()
    }

    override func mouseDown(with event: NSEvent) {
        notifyInteractionIfNeeded()
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        notifyInteractionIfNeeded()
        super.rightMouseDown(with: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        notifyInteractionIfNeeded()
        super.otherMouseDown(with: event)
    }
}

@MainActor
@Observable
final class BrowserController: NSObject {
    let tabId: String
    let webView: BlinkBrowserWebView

    var state: BrowserTabState
    var addressBarFocusRequestID: Int = 0
    var onInteraction: (() -> Void)?
    var onOpenNewTabRequest: ((URL) -> Void)?

    private var onStateChange: ((BrowserTabState) -> Void)?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    init(
        tabId: String,
        initialState: BrowserTabState,
        onStateChange: @escaping (BrowserTabState) -> Void
    ) {
        self.tabId = tabId
        self.state = initialState
        self.onStateChange = onStateChange

        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = BlinkBrowserWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        self.webView = webView

        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.onInteraction = { [weak self] in
            guard let self else { return }
            self.state.preferredFocus = .webView
            self.onInteraction?()
            self.publishState()
        }

        installObservers()

        if let urlString = initialState.urlString,
           let url = BrowserURLResolver.resolve(urlString) {
            load(url: url)
        }
    }

    deinit {
        observations.forEach { $0.invalidate() }
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

        let currentURLString = webView.url?.absoluteString ?? state.urlString
        if let requestedURLString = initialState.urlString,
           requestedURLString != currentURLString,
           let url = BrowserURLResolver.resolve(requestedURLString) {
            load(url: url)
            return
        }

        refreshState()
    }

    func navigate(to rawValue: String) {
        guard let url = BrowserURLResolver.resolve(rawValue) else { return }
        state.urlString = url.absoluteString
        state.title = nil
        state.isLoading = true
        load(url: url)
        if state.preferredFocus != .webView {
            state.preferredFocus = .webView
        }
        publishState()
    }

    func focusWebView() {
        let focusChanged = state.preferredFocus != .webView
        state.preferredFocus = .webView
        let responderChanged = makeWebViewFirstResponder()
        guard focusChanged || responderChanged else { return }
        publishState()
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
        guard webView.canGoBack else { return }
        webView.goBack()
    }

    func goForward() {
        guard webView.canGoForward else { return }
        webView.goForward()
    }

    func reload() {
        if webView.url == nil, let urlString = state.urlString {
            navigate(to: urlString)
            return
        }
        webView.reload()
    }

    func openInDefaultBrowser() {
        guard let url = webView.url ?? state.urlString.flatMap(BrowserURLResolver.resolve) else { return }
        NSWorkspace.shared.open(url)
    }

    private func load(url: URL) {
        webView.load(URLRequest(url: url))
    }

    @discardableResult
    private func makeWebViewFirstResponder() -> Bool {
        guard let window = webView.window else { return false }
        guard window.firstResponder !== webView else { return false }
        webView.suppressNextInteraction = true
        window.makeFirstResponder(webView)
        return true
    }

    private func installObservers() {
        observations = [
            webView.observe(\.title, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in
                    self?.refreshState()
                }
            },
            webView.observe(\.url, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in
                    self?.refreshState()
                }
            },
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in
                    self?.refreshState()
                }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in
                    self?.refreshState()
                }
            },
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in
                    self?.refreshState()
                }
            }
        ]
    }

    private func refreshState() {
        let nextState = BrowserTabState(
            urlString: webView.url?.absoluteString ?? state.urlString,
            title: sanitizedTitle(webView.title) ?? state.title,
            canGoBack: webView.canGoBack,
            canGoForward: webView.canGoForward,
            isLoading: webView.isLoading,
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
}

extension BrowserController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        refreshState()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        refreshState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refreshState()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        refreshState()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        refreshState()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        if let scheme = url.scheme?.lowercased(),
           !["http", "https", "file", "about"].contains(scheme) {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }
}

extension BrowserController: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil,
              let url = navigationAction.request.url else {
            return nil
        }

        onOpenNewTabRequest?(url)
        return nil
    }
}
