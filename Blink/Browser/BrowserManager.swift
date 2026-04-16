import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class BrowserManager {
    static let willTerminateNotification = Notification.Name("BlinkBrowserManagerWillTerminate")
    static let downloadsDidChangeNotification = Notification.Name("BlinkBrowserManagerDownloadsDidChange")
    private static let downloadsStorageKey = "blink.browserDownloads"
    private static let historyStorageKey = "blink.browserHistory"
    private static let maximumHistoryEntries = 200

    let engine: BrowserEngine
    var downloads: [BrowserDownloadItem] = [] {
        didSet {
            saveDownloads()
            NotificationCenter.default.post(name: Self.downloadsDidChangeNotification, object: self)
        }
    }
    var historyEntries: [BrowserHistoryEntry] = [] {
        didSet {
            saveHistoryEntries()
        }
    }
    var controllerGeneration: Int = 0
    private var controllers: [String: any BrowserHostController] = [:]
    private var controllerProfileIds: [String: String] = [:]
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?
    @ObservationIgnored private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.engine = Self.resolveEngine()
        self.downloads = Self.loadDownloads(from: userDefaults)
        self.historyEntries = Self.loadHistoryEntries(from: userDefaults)
        terminationObserver = NotificationCenter.default.addObserver(
            forName: Self.willTerminateNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.invalidateAllControllers()
            }
        }
    }

    func controller(
        for tabId: String,
        workspaceId: String,
        profileId: String,
        initialState: BrowserTabState,
        onStateChange: @escaping (BrowserTabState) -> Void
    ) -> any BrowserHostController {
        if let existing = controllers[tabId] {
            if controllerProfileIds[tabId] == profileId {
                return existing
            }

            existing.invalidate()
            controllers[tabId] = nil
            controllerProfileIds[tabId] = nil
        }

        let controller = makeController(
            tabId: tabId,
            workspaceId: workspaceId,
            profileId: profileId,
            initialState: initialState,
            onStateChange: onStateChange
        )
        controllers[tabId] = controller
        controllerProfileIds[tabId] = profileId
        return controller
    }

    private func makeController(
        tabId: String,
        workspaceId: String,
        profileId: String,
        initialState: BrowserTabState,
        onStateChange: @escaping (BrowserTabState) -> Void
    ) -> any BrowserHostController {
        let wrappedStateChange: (BrowserTabState) -> Void = { [weak self] state in
            self?.recordHistoryEntry(from: state)
            onStateChange(state)
        }

        switch engine {
        case .webKit:
            return BrowserController(
                tabId: tabId,
                initialState: initialState,
                onStateChange: wrappedStateChange
            )
        case .chromium:
            return ChromiumBrowserController(
                tabId: tabId,
                workspaceId: workspaceId,
                profileId: profileId,
                initialState: initialState,
                onStateChange: wrappedStateChange,
                onDownloadUpdate: { [weak self] download in
                    self?.recordDownloadUpdate(download)
                }
            )
        }
    }

    private static func resolveEngine() -> BrowserEngine {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return .webKit
        }

        guard BrowserEngineSelection.active == .chromium,
              BlinkChromiumRuntime.canStartInCurrentBundle() else {
            return .webKit
        }

        return .chromium
    }

    func destroyController(tabId: String) {
        let removedController = controllers.removeValue(forKey: tabId)
        controllerProfileIds[tabId] = nil
        removedController?.invalidate()
        if removedController != nil {
            controllerGeneration &+= 1
        }
    }

    func destroyControllers(tabIds: [String]) {
        for tabId in tabIds {
            destroyController(tabId: tabId)
        }
    }

    func focusWebView(tabId: String) {
        controllers[tabId]?.focusWebView()
    }

    func focusAddressBar(tabId: String) {
        controllers[tabId]?.focusAddressBar()
    }

    func goBack(tabId: String) {
        controllers[tabId]?.goBack()
    }

    func goForward(tabId: String) {
        controllers[tabId]?.goForward()
    }

    func reload(tabId: String) {
        controllers[tabId]?.reload()
    }

    func toggleDeveloperTools(tabId: String) {
        controllers[tabId]?.toggleDeveloperTools()
    }

    func openInDefaultBrowser(tabId: String) {
        controllers[tabId]?.openInDefaultBrowser()
    }

    func recentDownloads(
        for workspaceId: String,
        limit: Int = 4
    ) -> [BrowserDownloadItem] {
        Array(
            downloads
                .filter { $0.workspaceId == workspaceId }
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(limit)
        )
    }

    func downloads(for workspaceId: String) -> [BrowserDownloadItem] {
        downloads
            .filter { $0.workspaceId == workspaceId }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func clearDownloads(for workspaceId: String) {
        downloads.removeAll { $0.workspaceId == workspaceId }
    }

    func recordHistoryEntry(from state: BrowserTabState) {
        guard !state.isLoading,
              let resolvedURLString = state.urlString.flatMap(BrowserURLResolver.resolve)?.absoluteString,
              resolvedURLString != "about:blank" else {
            return
        }

        let normalizedTitle = normalizedHistoryTitle(state.title)

        if let existingIndex = historyEntries.firstIndex(where: { $0.urlString == resolvedURLString }) {
            var entry = historyEntries.remove(at: existingIndex)
            entry.title = normalizedTitle ?? entry.title
            if existingIndex != 0 {
                entry.lastVisitedAt = Date()
            }
            historyEntries.insert(entry, at: 0)
            return
        }

        historyEntries.insert(
            BrowserHistoryEntry(
                urlString: resolvedURLString,
                title: normalizedTitle,
                lastVisitedAt: Date()
            ),
            at: 0
        )

        if historyEntries.count > Self.maximumHistoryEntries {
            historyEntries.removeLast(historyEntries.count - Self.maximumHistoryEntries)
        }
    }

    func addressBarSuggestions(
        for query: String,
        limit: Int = 6
    ) -> [BrowserHistoryEntry] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return Array(historyEntries.prefix(limit))
        }

        let normalizedQuery = trimmedQuery.lowercased()
        return Array(
            historyEntries
                .compactMap { entry -> (BrowserHistoryEntry, Int)? in
                    let score = addressBarSuggestionScore(for: entry, query: normalizedQuery)
                    guard score > 0 else { return nil }
                    return (entry, score)
                }
                .sorted { lhs, rhs in
                    if lhs.1 != rhs.1 {
                        return lhs.1 > rhs.1
                    }
                    return lhs.0.lastVisitedAt > rhs.0.lastVisitedAt
                }
                .map(\.0)
                .prefix(limit)
        )
    }

    func openDownload(_ download: BrowserDownloadItem) {
        guard let destinationURL = download.destinationURL else { return }
        NSWorkspace.shared.open(destinationURL)
    }

    func revealDownload(_ download: BrowserDownloadItem) {
        guard let destinationURL = download.destinationURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
    }

    private func invalidateAllControllers() {
        let activeControllers = Array(controllers.values)
        controllers.removeAll()
        controllerProfileIds.removeAll()
        for controller in activeControllers {
            controller.invalidate()
        }
        if !activeControllers.isEmpty {
            controllerGeneration &+= 1
        }
    }

    private func recordDownloadUpdate(_ download: BrowserDownloadItem) {
        if let existingIndex = downloads.firstIndex(where: { $0.id == download.id }) {
            downloads[existingIndex] = download
        } else {
            downloads.append(download)
        }

        downloads.sort { $0.updatedAt > $1.updatedAt }
        if downloads.count > 50 {
            downloads.removeLast(downloads.count - 50)
        }
    }

    private func saveDownloads() {
        if let data = try? JSONEncoder().encode(downloads) {
            userDefaults.set(data, forKey: Self.downloadsStorageKey)
        }
    }

    private static func loadDownloads(from userDefaults: UserDefaults) -> [BrowserDownloadItem] {
        guard let data = userDefaults.data(forKey: downloadsStorageKey),
              let downloads = try? JSONDecoder().decode([BrowserDownloadItem].self, from: data) else {
            return []
        }
        return downloads.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func saveHistoryEntries() {
        if let data = try? JSONEncoder().encode(historyEntries) {
            userDefaults.set(data, forKey: Self.historyStorageKey)
        }
    }

    private static func loadHistoryEntries(from userDefaults: UserDefaults) -> [BrowserHistoryEntry] {
        guard let data = userDefaults.data(forKey: historyStorageKey),
              let historyEntries = try? JSONDecoder().decode([BrowserHistoryEntry].self, from: data) else {
            return []
        }
        return historyEntries.sorted { $0.lastVisitedAt > $1.lastVisitedAt }
    }

    private func normalizedHistoryTitle(_ title: String?) -> String? {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return nil
        }

        return title
    }

    private func addressBarSuggestionScore(
        for entry: BrowserHistoryEntry,
        query: String
    ) -> Int {
        let urlString = entry.urlString.lowercased()
        let urlWithoutScheme = urlString
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        let host = entry.host?.lowercased() ?? ""
        let title = entry.title?.lowercased() ?? ""
        let localBonus = entry.isLocal ? 450 : 0

        if host == query || urlString == query || urlWithoutScheme == query {
            return 1000 + localBonus
        }

        if host.hasPrefix(query) {
            return 900 + localBonus
        }

        if urlWithoutScheme.hasPrefix(query) || urlString.hasPrefix(query) {
            return 850 + localBonus
        }

        if title.hasPrefix(query) {
            return 700 + localBonus
        }

        if host.contains(query) {
            return 650 + localBonus
        }

        if title.contains(query) {
            return 500 + localBonus
        }

        if urlWithoutScheme.contains(query) || urlString.contains(query) {
            return 450 + localBonus
        }

        return 0
    }
}
