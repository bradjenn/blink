import Foundation

enum BrowserFocusTarget: String, Codable, Equatable, Hashable {
    case webView
    case addressBar
}

struct BrowserTabState: Codable, Equatable, Hashable {
    var urlString: String?
    var title: String?
    var canGoBack: Bool
    var canGoForward: Bool
    var isLoading: Bool
    var preferredFocus: BrowserFocusTarget

    init(
        urlString: String? = nil,
        title: String? = nil,
        canGoBack: Bool = false,
        canGoForward: Bool = false,
        isLoading: Bool = false,
        preferredFocus: BrowserFocusTarget = .addressBar
    ) {
        self.urlString = urlString
        self.title = title
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.isLoading = isLoading
        self.preferredFocus = preferredFocus
    }

    static let blank = BrowserTabState()
}
