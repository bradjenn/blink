import AppKit
import Foundation

@MainActor
final class ChromiumBrowserController: NSObject, BrowserHostController {
    private static let downloadRecoveryDuration: TimeInterval = 4
    private static let minimumRecoveryNavigationInterval: TimeInterval = 0.35

    let tabId: String
    let projectId: String
    let session: BrowserSessionModel
    let host: BlinkChromiumBrowserHost

    var onInteraction: (() -> Void)?
    var onOpenNewTabRequest: ((URL) -> Void)?
    var hostView: NSView { host.hostView }

    private var onStateChange: ((BrowserTabState) -> Void)?
    private var onDownloadUpdate: ((BrowserDownloadItem) -> Void)?
    private var lastStableURLString: String?
    private var recoveredDownloadIdentifiers: Set<String> = []
    private var activeDownloadRecoveryURLString: String?
    private var activeDownloadRecoveryDeadline: Date?
    private var lastDownloadRecoveryNavigationAt: Date?

    private struct BrowserStatePayload: Sendable {
        let urlString: String?
        let title: String?
        let canGoBack: Bool
        let canGoForward: Bool
        let isLoading: Bool
    }

    private struct DownloadPayload: Sendable {
        let downloadIdentifier: String
        let urlString: String?
        let suggestedFileName: String
        let fullPath: String?
        let receivedBytes: Int64
        let totalBytes: Int64
        let percentComplete: Int
        let currentSpeed: Int64
        let isInProgress: Bool
        let isComplete: Bool
        let isCanceled: Bool
        let isInterrupted: Bool
    }

    nonisolated private static func browserStatePayload(from snapshot: BlinkChromiumBrowserStateSnapshot?) -> BrowserStatePayload? {
        guard let snapshot else { return nil }
        return BrowserStatePayload(
            urlString: snapshot.urlString,
            title: snapshot.title,
            canGoBack: snapshot.canGoBack,
            canGoForward: snapshot.canGoForward,
            isLoading: snapshot.isLoading
        )
    }

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
        onStateChange: @escaping (BrowserTabState) -> Void,
        onDownloadUpdate: @escaping (BrowserDownloadItem) -> Void
    ) {
        self.tabId = tabId
        self.projectId = projectId
        self.session = BrowserSessionModel(state: initialState)
        self.onStateChange = onStateChange
        self.onDownloadUpdate = onDownloadUpdate
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

        refreshState(from: Self.browserStatePayload(from: host.snapshot))
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

    func toggleDeveloperTools() {
        host.toggleDeveloperTools()
    }

    func openInDefaultBrowser() {
        guard let urlString = host.snapshot?.urlString ?? state.urlString,
              let url = BrowserURLResolver.resolve(urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    func invalidate() {
        host.invalidate()
    }

    private func refreshState(from payload: BrowserStatePayload?) {
        let snapshotURLString = normalizedURLString(payload?.urlString)
        enforceDownloadRecoveryIfNeeded(for: snapshotURLString)
        let nextState = BrowserTabState(
            urlString: mergedURLString(snapshotURLString),
            title: sanitizedTitle(payload?.title) ?? state.title,
            canGoBack: payload?.canGoBack ?? state.canGoBack,
            canGoForward: payload?.canGoForward ?? state.canGoForward,
            isLoading: payload?.isLoading ?? state.isLoading,
            preferredFocus: state.preferredFocus
        )

        rememberStableURLIfNeeded(from: nextState)

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
           let recoveryURLString = currentDownloadRecoveryURLString() {
            return recoveryURLString
        }

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

    private func handleHostUpdate(_ payload: BrowserStatePayload) {
        refreshState(from: payload)
    }

    private func handleOpenNewTabRequest(urlString: String?) {
        guard let target = urlString,
              !target.isEmpty,
              target != "about:blank" else {
            return
        }
        guard let url = BrowserURLResolver.resolve(target) else { return }
        onOpenNewTabRequest?(url)
    }

    private func handleDownloadUpdate(_ payload: DownloadPayload) {
        let download = BrowserDownloadItem(
            id: "\(projectId):\(payload.downloadIdentifier)",
            browserTabId: tabId,
            projectId: projectId,
            sourceURLString: payload.urlString,
            suggestedFileName: payload.suggestedFileName,
            destinationPath: payload.fullPath,
            receivedBytes: payload.receivedBytes,
            totalBytes: payload.totalBytes,
            percentComplete: payload.percentComplete,
            currentSpeed: payload.currentSpeed,
            isInProgress: payload.isInProgress,
            isComplete: payload.isComplete,
            isCanceled: payload.isCanceled,
            isInterrupted: payload.isInterrupted,
            updatedAt: Date()
        )
        onDownloadUpdate?(download)
        recoverFromBlankDownloadPageIfNeeded(for: payload)
    }

    private func rememberStableURLIfNeeded(from state: BrowserTabState) {
        guard let urlString = normalizedURLString(state.urlString),
              urlString != "about:blank",
              state.title != nil else {
            return
        }

        lastStableURLString = urlString
    }

    private func recoverFromBlankDownloadPageIfNeeded(for payload: DownloadPayload) {
        guard recoveredDownloadIdentifiers.insert(payload.downloadIdentifier).inserted else { return }
        guard payload.isInProgress || payload.isComplete else { return }
        guard let fallbackURLString = lastStableURLString else { return }

        activeDownloadRecoveryURLString = fallbackURLString
        activeDownloadRecoveryDeadline = Date().addingTimeInterval(Self.downloadRecoveryDuration)

        let currentURLString = normalizedURLString(host.snapshot?.urlString) ?? normalizedURLString(state.urlString)
        guard currentURLString != fallbackURLString else {
            return
        }

        navigateToDownloadRecoveryURL(fallbackURLString)
    }

    private func currentDownloadRecoveryURLString() -> String? {
        guard let urlString = activeDownloadRecoveryURLString,
              let deadline = activeDownloadRecoveryDeadline,
              deadline > Date() else {
            activeDownloadRecoveryURLString = nil
            activeDownloadRecoveryDeadline = nil
            return nil
        }

        return urlString
    }

    private func enforceDownloadRecoveryIfNeeded(for snapshotURLString: String?) {
        guard snapshotURLString == "about:blank",
              let recoveryURLString = currentDownloadRecoveryURLString() else {
            return
        }

        let now = Date()
        if let lastDownloadRecoveryNavigationAt,
           now.timeIntervalSince(lastDownloadRecoveryNavigationAt) < Self.minimumRecoveryNavigationInterval {
            return
        }

        navigateToDownloadRecoveryURL(recoveryURLString)
    }

    private func navigateToDownloadRecoveryURL(_ fallbackURLString: String) {
        lastDownloadRecoveryNavigationAt = Date()
        state.urlString = fallbackURLString
        state.title = nil
        state.isLoading = true
        host.loadURLString(fallbackURLString)
        publishState()
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
        guard let payload = Self.browserStatePayload(from: snapshot) else { return }
        Task { @MainActor [weak self] in
            self?.handleHostUpdate(payload)
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

    nonisolated func chromiumBrowserHost(
        _ host: BlinkChromiumBrowserHost,
        didUpdateDownload snapshot: BlinkChromiumDownloadSnapshot
    ) {
        let payload = DownloadPayload(
            downloadIdentifier: snapshot.downloadIdentifier,
            urlString: snapshot.urlString,
            suggestedFileName: snapshot.suggestedFileName,
            fullPath: snapshot.fullPath,
            receivedBytes: snapshot.receivedBytes,
            totalBytes: snapshot.totalBytes,
            percentComplete: snapshot.percentComplete,
            currentSpeed: snapshot.currentSpeed,
            isInProgress: snapshot.isInProgress,
            isComplete: snapshot.isComplete,
            isCanceled: snapshot.isCanceled,
            isInterrupted: snapshot.isInterrupted
        )
        Task { @MainActor [weak self] in
            self?.handleDownloadUpdate(payload)
        }
    }
}
