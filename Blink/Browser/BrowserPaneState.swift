import Foundation

struct BrowserPaneTab: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var state: BrowserTabState
    var isPinned: Bool

    init(
        id: String = UUID().uuidString,
        state: BrowserTabState,
        isPinned: Bool = false
    ) {
        self.id = id
        self.state = state
        self.isPinned = isPinned
    }

    var displayTitle: String {
        if let title = state.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }

        if let urlString = state.urlString,
           let host = URL(string: urlString)?.host(percentEncoded: false),
           !host.isEmpty {
            return host
        }

        return "New Tab"
    }

    var displaySubtitle: String? {
        guard let urlString = state.urlString,
              !urlString.isEmpty else { return nil }
        return urlString
    }

    var host: String? {
        guard let urlString = state.urlString,
              let url = URL(string: urlString),
              let host = url.host(percentEncoded: false),
              !host.isEmpty else {
            return nil
        }

        return host
    }

    var faviconURL: URL? {
        guard let host else { return nil }

        var components = URLComponents(string: "https://www.google.com/s2/favicons")
        components?.queryItems = [
            URLQueryItem(name: "sz", value: "64"),
            URLQueryItem(name: "domain", value: host)
        ]
        return components?.url
    }
}

struct BrowserPaneState: Codable, Equatable, Hashable {
    var tabs: [BrowserPaneTab]
    var selectedTabId: String?
    var isSidebarPinned: Bool

    init(
        tabs: [BrowserPaneTab],
        selectedTabId: String? = nil,
        isSidebarPinned: Bool = false
    ) {
        self.tabs = tabs
        self.selectedTabId = selectedTabId
        self.isSidebarPinned = isSidebarPinned
        normalizeSelection()
    }

    var selectedTab: BrowserPaneTab? {
        if let selectedTabId,
           let selectedTab = tabs.first(where: { $0.id == selectedTabId }) {
            return selectedTab
        }

        return tabs.first
    }

    var selectedTabIndex: Int? {
        guard let selectedTab else { return nil }
        return tabs.firstIndex(where: { $0.id == selectedTab.id })
    }

    var pinnedTabs: [BrowserPaneTab] {
        tabs.filter(\.isPinned)
    }

    var unpinnedTabs: [BrowserPaneTab] {
        tabs.filter { !$0.isPinned }
    }

    var orderedTabs: [BrowserPaneTab] {
        pinnedTabs + unpinnedTabs
    }

    func containsTab(_ browserTabId: String) -> Bool {
        tabs.contains(where: { $0.id == browserTabId })
    }

    mutating func selectTab(_ browserTabId: String) {
        guard containsTab(browserTabId) else { return }
        selectedTabId = browserTabId
    }

    mutating func appendTab(_ tab: BrowserPaneTab, selecting: Bool = true) {
        if tab.isPinned {
            let insertionIndex = tabs.lastIndex(where: \.isPinned).map { tabs.index(after: $0) } ?? tabs.startIndex
            tabs.insert(tab, at: insertionIndex)
        } else {
            tabs.append(tab)
        }
        if selecting || selectedTabId == nil {
            selectedTabId = tab.id
        }
        normalizeSelection()
    }

    @discardableResult
    mutating func removeTab(_ browserTabId: String) -> BrowserPaneTab? {
        guard let index = tabs.firstIndex(where: { $0.id == browserTabId }) else { return nil }
        let removedTab = tabs.remove(at: index)

        if selectedTabId == removedTab.id {
            if tabs.indices.contains(index) {
                selectedTabId = tabs[index].id
            } else {
                selectedTabId = tabs.last?.id
            }
        }

        normalizeSelection()
        return removedTab
    }

    mutating func updateState(_ state: BrowserTabState, for browserTabId: String) {
        guard let index = tabs.firstIndex(where: { $0.id == browserTabId }) else { return }
        tabs[index].state = state
    }

    mutating func setPinned(_ isPinned: Bool, for browserTabId: String) {
        guard let index = tabs.firstIndex(where: { $0.id == browserTabId }) else { return }
        guard tabs[index].isPinned != isPinned else { return }
        tabs[index].isPinned = isPinned
        let tab = tabs.remove(at: index)
        if isPinned {
            let insertionIndex = tabs.lastIndex(where: \.isPinned).map { tabs.index(after: $0) } ?? tabs.startIndex
            tabs.insert(tab, at: insertionIndex)
        } else {
            tabs.append(tab)
        }
    }

    private mutating func normalizeSelection() {
        guard !tabs.isEmpty else {
            selectedTabId = nil
            return
        }

        if let selectedTabId, containsTab(selectedTabId) {
            return
        }

        selectedTabId = tabs.first?.id
    }
}

extension BrowserPaneState {
    static let empty = BrowserPaneState(tabs: [])

    static func singleTab(
        urlString: String?,
        preferredFocus: BrowserFocusTarget? = nil
    ) -> BrowserPaneState {
        let resolvedState = BrowserTabState(
            urlString: urlString,
            title: nil,
            canGoBack: false,
            canGoForward: false,
            isLoading: false,
            preferredFocus: preferredFocus ?? (urlString == nil ? .addressBar : .webView)
        )
        let tab = BrowserPaneTab(state: resolvedState)
        return BrowserPaneState(tabs: [tab], selectedTabId: tab.id)
    }
}

extension BrowserPaneState {
    private enum CodingKeys: String, CodingKey {
        case tabs
        case selectedTabId
        case isSidebarPinned

        // Legacy single-tab shape.
        case urlString
        case title
        case canGoBack
        case canGoForward
        case isLoading
        case preferredFocus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if container.contains(.tabs) {
            let tabs = try container.decodeIfPresent([BrowserPaneTab].self, forKey: .tabs) ?? []
            let selectedTabId = try container.decodeIfPresent(String.self, forKey: .selectedTabId)
            let isSidebarPinned = try container.decodeIfPresent(Bool.self, forKey: .isSidebarPinned) ?? false
            self.init(tabs: tabs, selectedTabId: selectedTabId, isSidebarPinned: isSidebarPinned)
            return
        }

        let legacyState = BrowserTabState(
            urlString: try container.decodeIfPresent(String.self, forKey: .urlString),
            title: try container.decodeIfPresent(String.self, forKey: .title),
            canGoBack: try container.decodeIfPresent(Bool.self, forKey: .canGoBack) ?? false,
            canGoForward: try container.decodeIfPresent(Bool.self, forKey: .canGoForward) ?? false,
            isLoading: try container.decodeIfPresent(Bool.self, forKey: .isLoading) ?? false,
            preferredFocus: try container.decodeIfPresent(BrowserFocusTarget.self, forKey: .preferredFocus) ?? .addressBar
        )

        let legacyTab = BrowserPaneTab(id: "legacy", state: legacyState)
        self.init(tabs: [legacyTab], selectedTabId: legacyTab.id, isSidebarPinned: false)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tabs, forKey: .tabs)
        try container.encodeIfPresent(selectedTabId, forKey: .selectedTabId)
        try container.encode(isSidebarPinned, forKey: .isSidebarPinned)
    }
}
